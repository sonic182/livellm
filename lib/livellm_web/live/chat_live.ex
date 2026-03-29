defmodule LivellmWeb.ChatLive do
  @moduledoc false

  use LivellmWeb, :live_view

  import LivellmWeb.ChatComponents

  alias Livellm.Chats
  alias Livellm.Chats.ActiveTasks
  alias Livellm.Chats.Message.ReasoningStep
  alias Livellm.Config
  alias Livellm.Memories.Tool, as: MemoriesTool
  alias Livellm.Usage
  alias LlmComposer
  alias LlmComposer.FunctionCallHelpers
  alias LlmComposer.FunctionExecutor
  alias LlmComposer.LlmResponse

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    provider_configs = Config.list_provider_configs()
    enabled = Enum.find(provider_configs, & &1.enabled)

    {:ok,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:chats, Chats.list_chats())
     |> assign(:chat, nil)
     |> assign(:current_chat_id, nil)
     |> assign(:subscribed_chat_id, nil)
     |> assign(:provider_configs, provider_configs)
     |> assign(:selected_provider_id, enabled && enabled.id)
     |> assign(:selected_model, (enabled && enabled.default_model) || "")
     |> assign(:selected_reasoning_effort, nil)
     |> assign(:waiting, false)
     |> assign(:stream_mode, true)
     |> assign(:use_memory_tool, false)
     |> assign(:tools_panel_open, false)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_reasoning, nil)
     |> assign(:reasoning_steps, [])
     |> assign(:tool_call_status, nil)
     |> assign(:chat_metrics, Usage.empty_chat_metrics())
     |> stream(:messages, [])}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    if connected?(socket), do: maybe_unsubscribe(socket)

    {:noreply,
     socket
     |> assign(:page_title, "New Chat")
     |> assign(:chat, nil)
     |> assign(:current_chat_id, nil)
     |> assign(:subscribed_chat_id, nil)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_reasoning, nil)
     |> assign(:reasoning_steps, [])
     |> assign(:chat_metrics, Usage.empty_chat_metrics())
     |> stream(:messages, [], reset: true)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, %{assigns: %{live_action: :show}} = socket) do
    chat = Chats.get_chat!(id)
    messages = Chats.list_messages(chat)

    if connected?(socket) do
      maybe_unsubscribe(socket)
      Phoenix.PubSub.subscribe(Livellm.PubSub, stream_topic(chat.id))
    end

    waiting = connected?(socket) && ActiveTasks.active?(chat.id)

    {:noreply,
     socket
     |> assign(:page_title, chat.title)
     |> assign(:chat, chat)
     |> assign(:current_chat_id, chat.id)
     |> assign(:subscribed_chat_id, chat.id)
     |> assign(:selected_provider_id, chat.provider_config_id)
     |> assign(:selected_model, chat.model)
     |> assign(:selected_reasoning_effort, chat.reasoning_effort)
     |> assign(:waiting, waiting)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_reasoning, nil)
     |> assign(:chat_metrics, Usage.aggregate_chat_metrics(messages))
     |> stream(:messages, messages, reset: true)}
  end

  @impl true
  def handle_event(
        "send_message",
        %{"message" => content},
        %{assigns: %{waiting: false}} = socket
      )
      when content != "" do
    %{
      chat: chat,
      selected_provider_id: provider_id,
      selected_model: model,
      provider_configs: configs
    } = socket.assigns

    chat_result =
      case chat do
        nil ->
          Chats.create_chat(%{
            title: String.slice(content, 0, 60),
            model: model,
            reasoning_effort: socket.assigns.selected_reasoning_effort,
            provider_config_id: provider_id
          })

        existing ->
          {:ok, existing}
      end

    case chat_result do
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not start chat.")}

      {:ok, chat} ->
        Logger.debug("[chat_live] user_message chat_id=#{chat.id} content=#{inspect(content)}")

        {:ok, user_msg} = Chats.create_message(chat, %{role: "user", content: content})

        provider_config = Enum.find(configs, &(&1.id == provider_id))
        history = Chats.list_messages(chat)

        req = %{
          provider_config: provider_config,
          model: model,
          reasoning_effort: socket.assigns.selected_reasoning_effort,
          stream_mode: socket.assigns.stream_mode,
          use_memory_tool: socket.assigns.use_memory_tool
        }

        ActiveTasks.mark_active(chat.id)

        Task.Supervisor.start_child(Livellm.TaskSupervisor, fn ->
          run_llm_task(req, history, chat)
        end)

        {:noreply,
         socket
         |> assign(:chat, chat)
         |> assign(:current_chat_id, chat.id)
         |> assign(:chats, Chats.list_chats())
         |> assign(:waiting, true)
         |> stream_insert(:messages, user_msg)
         |> push_patch(to: ~p"/chats/#{chat.id}")}
    end
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_chat", %{"id" => id}, socket) do
    chat = Chats.get_chat!(String.to_integer(id))
    {:ok, _} = Chats.delete_chat(chat)

    socket = assign(socket, :chats, Chats.list_chats())

    if socket.assigns.current_chat_id == chat.id do
      {:noreply,
       socket
       |> assign(:chat, nil)
       |> assign(:current_chat_id, nil)
       |> push_navigate(to: ~p"/")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_chat_settings", params, socket) do
    new_provider_id = parse_provider_id(params["provider_id"])
    selected_model = resolve_model(params, socket.assigns, new_provider_id)
    reasoning_effort = parse_effort(params["reasoning_effort"])
    stream_mode = params["streaming"] == "true"

    socket =
      if socket.assigns.chat do
        {:ok, updated_chat} =
          Chats.update_chat(socket.assigns.chat, %{
            model: selected_model,
            reasoning_effort: reasoning_effort,
            provider_config_id: new_provider_id
          })

        assign(socket, :chat, updated_chat)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:selected_provider_id, new_provider_id)
     |> assign(:selected_model, selected_model)
     |> assign(:selected_reasoning_effort, reasoning_effort)
     |> assign(:stream_mode, stream_mode)
     |> push_event("save_chat_settings", %{
       streaming: stream_mode,
       use_memory_tool: socket.assigns.use_memory_tool
     })}
  end

  @impl true
  def handle_event("restore_chat_settings", params, socket) do
    stream_mode = Map.get(params, "streaming", true) in [true, "true"]
    use_memory_tool = Map.get(params, "use_memory_tool", false) in [true, "true"]

    {:noreply,
     socket
     |> assign(:stream_mode, stream_mode)
     |> assign(:use_memory_tool, use_memory_tool)}
  end

  @impl true
  def handle_event("toggle_tools_panel", _params, socket) do
    {:noreply, assign(socket, :tools_panel_open, !socket.assigns.tools_panel_open)}
  end

  @impl true
  def handle_event("toggle_tool", %{"tool" => "memory"}, socket) do
    new_val = !socket.assigns.use_memory_tool

    {:noreply,
     socket
     |> assign(:use_memory_tool, new_val)
     |> push_event("save_chat_settings", %{
       streaming: socket.assigns.stream_mode,
       use_memory_tool: new_val
     })}
  end

  @impl true
  def handle_info({:llm_done, _chat, assistant_msg}, socket) do
    {:noreply,
     socket
     |> assign(:waiting, false)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_reasoning, nil)
     |> assign(:tool_call_status, nil)
     |> assign(:reasoning_steps, [])
     |> assign(
       :chat_metrics,
       Usage.merge_chat_metrics(socket.assigns.chat_metrics, assistant_msg)
     )
     |> stream_insert(:messages, assistant_msg)
     |> push_event("focus_input", %{})}
  end

  @impl true
  def handle_info({:llm_response, _chat, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:waiting, false)
     |> assign(:tool_call_status, nil)
     |> assign(:reasoning_steps, [])
     |> put_flash(:error, "LLM error: #{inspect(reason)}")
     |> push_event("focus_input", %{})}
  end

  @impl true
  def handle_info({:tool_call_start, _chat, tool_name}, socket) do
    new_step = ReasoningStep.tool_call(tool_name, :running)

    {:noreply,
     socket
     |> assign(:tool_call_status, tool_name)
     |> assign(:streaming_content, nil)
     |> assign(:reasoning_steps, socket.assigns.reasoning_steps ++ [new_step])}
  end

  @impl true
  def handle_info({:tool_call_end, _chat, tool_name}, socket) do
    steps = socket.assigns.reasoning_steps

    updated_steps =
      Enum.map(steps, fn step ->
        if step.type == :tool_call && step.tool_name == tool_name do
          ReasoningStep.update_status(step, :completed)
        else
          step
        end
      end)

    {:noreply, assign(socket, :reasoning_steps, updated_steps)}
  end

  @impl true
  def handle_info({:stream_chunk, _chat, content}, socket) do
    {:noreply, assign(socket, :streaming_content, content)}
  end

  @impl true
  def handle_info({:stream_reasoning, _chat, reasoning}, socket) do
    steps = socket.assigns.reasoning_steps

    updated_steps =
      case List.last(steps) do
        %{type: :reasoning, content: _} = last_step ->
          List.replace_at(steps, -1, %{last_step | content: reasoning})

        _ ->
          steps ++ [ReasoningStep.reasoning(reasoning)]
      end

    {:noreply,
     socket
     |> assign(:streaming_reasoning, reasoning)
     |> assign(:reasoning_steps, updated_steps)}
  end

  @impl true
  def handle_info({:stream_done, _chat, %Livellm.Chats.Message{} = assistant_msg}, socket) do
    {:noreply,
     socket
     |> assign(:waiting, false)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_reasoning, nil)
     |> assign(:tool_call_status, nil)
     |> assign(:reasoning_steps, [])
     |> assign(
       :chat_metrics,
       Usage.merge_chat_metrics(socket.assigns.chat_metrics, assistant_msg)
     )
     |> stream_insert(:messages, assistant_msg)
     |> push_event("focus_input", %{})}
  end

  @impl true
  def handle_info({:stream_save_failed, _chat}, socket) do
    {:noreply,
     socket
     |> assign(:waiting, false)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_reasoning, nil)
     |> assign(:tool_call_status, nil)
     |> assign(:reasoning_steps, [])
     |> put_flash(:error, "Stream completed but failed to save response.")
     |> push_event("focus_input", %{})}
  end

  # --- Private ---

  defp stream_topic(chat_id), do: "chat_stream:#{chat_id}"

  defp broadcast(chat_id, message) do
    Phoenix.PubSub.broadcast(Livellm.PubSub, stream_topic(chat_id), message)
  end

  defp maybe_unsubscribe(%{assigns: %{subscribed_chat_id: id}}) when not is_nil(id) do
    Phoenix.PubSub.unsubscribe(Livellm.PubSub, stream_topic(id))
  end

  defp maybe_unsubscribe(_socket), do: :ok

  defp parse_provider_id(nil), do: nil
  defp parse_provider_id(""), do: nil
  defp parse_provider_id(id) when is_integer(id), do: id
  defp parse_provider_id(id) when is_binary(id), do: String.to_integer(id)

  defp parse_effort(""), do: nil
  defp parse_effort(nil), do: nil
  defp parse_effort(val) when is_binary(val), do: val

  defp resolve_model(%{"provider_id" => ""}, _assigns, _new_id), do: ""

  defp resolve_model(params, assigns, new_provider_id) do
    if new_provider_id != assigns.selected_provider_id do
      config = Enum.find(assigns.provider_configs, &(&1.id == new_provider_id))
      (config && config.default_model) || ""
    else
      params["model"] || assigns.selected_model
    end
  end

  defp run_llm_task(req, history, chat) do
    functions = if req.use_memory_tool, do: MemoriesTool.definitions(), else: []
    run_llm_loop(req, history, chat, functions)
  rescue
    error ->
      Logger.error(
        "[chat_live] task crashed chat_id=#{chat.id} error=#{Exception.message(error)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      broadcast(chat.id, {:llm_response, chat, {:error, error}})
  after
    ActiveTasks.mark_done(chat.id)
  end

  @max_tool_iterations 10

  defp run_llm_loop(
         req,
         history,
         chat,
         functions,
         iteration \\ 0,
         tool_calls_history \\ [],
         reasoning_steps \\ []
       )

  defp run_llm_loop(
         req,
         _history,
         chat,
         _functions,
         iteration,
         _tool_calls_history,
         _reasoning_steps
       )
       when iteration >= @max_tool_iterations do
    Logger.error("[chat_live] tool loop limit reached chat_id=#{chat.id} iteration=#{iteration}")
    handle_final_llm_result({:error, :tool_loop_limit}, chat, req)
  end

  defp run_llm_loop(req, history, chat, functions, iteration, tool_calls_history, reasoning_steps) do
    req
    |> run_llm_request(history, chat.id, functions: functions)
    |> handle_llm_result(
      chat,
      req,
      history,
      functions,
      iteration,
      tool_calls_history,
      reasoning_steps
    )
  end

  defp run_llm_request(req, history, chat_id, extra_opts) do
    opts = [stream: req.stream_mode] ++ extra_opts

    llm_runner().run(
      req.provider_config,
      req.model,
      history,
      req.reasoning_effort,
      chat_id,
      opts
    )
  end

  # Non-streaming response with active functions: check for tool calls and loop
  defp handle_llm_result(
         {:ok, %{stream: nil} = llm_response},
         chat,
         req,
         history,
         [_ | _] = functions,
         iteration,
         tool_calls_history,
         reasoning_steps
       ) do
    case LlmResponse.function_calls(llm_response) do
      calls when calls not in [nil, []] ->
        Logger.debug(
          "[chat_live] tool_calls chat_id=#{chat.id} iteration=#{iteration} history_len=#{length(history)} calls=#{inspect(Enum.map(calls, & &1.name))} args=#{inspect(Enum.map(calls, & &1.arguments))}"
        )

        provider_mod = provider_module(req.provider_config.provider)

        executed =
          Enum.map(calls, fn fc ->
            broadcast(chat.id, {:tool_call_start, chat, fc.name})
            {:ok, result} = FunctionExecutor.execute(fc, functions)

            Logger.debug(
              "[chat_live] tool_result chat_id=#{chat.id} name=#{fc.name} result=#{inspect(result.result)}"
            )

            broadcast(chat.id, {:tool_call_end, chat, fc.name})
            result
          end)

        dummy_user = %LlmComposer.Message{type: :user, content: ""}

        asst_msg =
          FunctionCallHelpers.build_assistant_with_tools(provider_mod, llm_response, dummy_user)

        tool_msgs = FunctionCallHelpers.build_tool_result_messages(executed)
        new_tool_calls = Enum.map(executed, &tool_call_entry/1)

        next_reasoning_steps =
          reasoning_steps ++
            build_reasoning_steps(llm_response.main_response.reasoning, new_tool_calls)

        run_llm_loop(
          req,
          history ++ [asst_msg | tool_msgs],
          chat,
          functions,
          iteration + 1,
          tool_calls_history ++ new_tool_calls,
          next_reasoning_steps
        )

      _ ->
        handle_final_llm_result(
          {:ok, llm_response},
          chat,
          req,
          tool_calls_history,
          reasoning_steps
        )
    end
  end

  # Streaming response with active functions: accumulate chunks, then check for tool calls
  defp handle_llm_result(
         {:ok, %{stream: stream, provider: provider}},
         chat,
         req,
         history,
         [_ | _] = functions,
         iteration,
         tool_calls_history,
         reasoning_steps
       )
       when not is_nil(stream) do
    Logger.debug(
      "[chat_live] streaming started (with functions) chat_id=#{chat.id} provider=#{provider}"
    )

    final = run_stream(stream, provider, req.model, chat)

    Logger.debug(
      "[chat_live] streaming done chat_id=#{chat.id} content_length=#{String.length(final.content)} tool_calls=#{inspect(final.tool_calls && Enum.map(final.tool_calls, & &1.name))}"
    )

    case final.tool_calls do
      calls when calls not in [nil, []] ->
        Logger.debug(
          "[chat_live] stream tool_calls chat_id=#{chat.id} iteration=#{iteration} calls=#{inspect(Enum.map(calls, & &1.name))}"
        )

        executed =
          Enum.map(calls, fn fc ->
            broadcast(chat.id, {:tool_call_start, chat, fc.name})
            {:ok, result} = FunctionExecutor.execute(fc, functions)

            Logger.debug(
              "[chat_live] tool_result chat_id=#{chat.id} name=#{fc.name} result=#{inspect(result.result)}"
            )

            result
          end)

        asst_msg = %LlmComposer.Message{
          type: :assistant,
          content: blank_to_nil(final.content),
          function_calls: calls
        }

        tool_msgs = FunctionCallHelpers.build_tool_result_messages(executed)
        new_tool_calls = Enum.map(executed, &tool_call_entry/1)

        next_reasoning_steps =
          reasoning_steps ++ build_reasoning_steps(final.reasoning, new_tool_calls)

        run_llm_loop(
          req,
          history ++ [asst_msg | tool_msgs],
          chat,
          functions,
          iteration + 1,
          tool_calls_history ++ new_tool_calls,
          next_reasoning_steps
        )

      _ ->
        save_stream_result(final, chat, tool_calls_history, reasoning_steps)
    end
  end

  defp handle_llm_result(
         result,
         chat,
         req,
         _history,
         _functions,
         _iteration,
         tool_calls_history,
         reasoning_steps
       ) do
    handle_final_llm_result(result, chat, req, tool_calls_history, reasoning_steps)
  end

  defp handle_final_llm_result(result, chat, req, tool_calls_history \\ [], reasoning_steps \\ [])

  defp handle_final_llm_result(
         {:ok, %{stream: stream, provider: provider}},
         chat,
         req,
         tool_calls_history,
         reasoning_steps
       )
       when not is_nil(stream) do
    Logger.debug("[chat_live] streaming started chat_id=#{chat.id} provider=#{provider}")

    final = run_stream(stream, provider, req.model, chat)

    Logger.debug(
      "[chat_live] streaming done chat_id=#{chat.id} content_length=#{String.length(final.content)} usage=#{inspect(final.final_chunk && final.final_chunk.usage)}"
    )

    save_stream_result(final, chat, tool_calls_history, reasoning_steps)
  end

  defp handle_final_llm_result(
         {:ok, llm_response},
         chat,
         _req,
         tool_calls_history,
         reasoning_steps
       ) do
    %{content: content, reasoning: reasoning, reasoning_details: reasoning_details} =
      llm_response.main_response

    all_reasoning_steps = reasoning_steps ++ build_reasoning_steps(reasoning, [])

    attrs =
      %{
        role: "assistant",
        content: content,
        reasoning: reasoning,
        reasoning_steps: all_reasoning_steps,
        reasoning_details: reasoning_details,
        raw_response: llm_response.raw,
        tool_calls: blank_list_to_nil(tool_calls_history)
      }
      |> Map.merge(Usage.cost_tracking_attrs(llm_response))

    case Chats.create_message(chat, attrs) do
      {:ok, assistant_msg} ->
        broadcast(chat.id, {:llm_done, chat, assistant_msg})

      {:error, changeset} ->
        Logger.error(
          "[chat_live] failed to save non-stream message chat_id=#{chat.id} errors=#{inspect(changeset.errors)}"
        )

        broadcast(chat.id, {:llm_response, chat, {:error, :save_failed}})
    end
  end

  defp handle_final_llm_result(
         {:error, reason},
         chat,
         _req,
         _tool_calls_history,
         _reasoning_steps
       ) do
    broadcast(chat.id, {:llm_response, chat, {:error, reason}})
  end

  defp save_stream_result(final, chat, tool_calls_history, reasoning_steps) do
    case Chats.create_message(
           chat,
           build_stream_message_attrs(final, tool_calls_history, reasoning_steps)
         ) do
      {:ok, assistant_msg} ->
        broadcast(chat.id, {:stream_done, chat, assistant_msg})

      {:error, changeset} ->
        Logger.error(
          "[chat_live] failed to save stream message chat_id=#{chat.id} errors=#{inspect(changeset.errors)}"
        )

        broadcast(chat.id, {:stream_save_failed, chat})
    end
  end

  defp run_stream(stream, provider, model, chat) do
    initial_acc = %{
      content: "",
      reasoning: "",
      reasoning_details: [],
      final_chunk: nil,
      tool_calls_acc: %{},
      reasoning_steps: [],
      chat: chat
    }

    final =
      stream
      |> LlmComposer.parse_stream_response(provider, track_costs: true, model: model)
      |> Enum.reduce(initial_acc, &handle_stream_chunk/2)

    tool_calls = build_tool_calls_from_stream_acc(final.tool_calls_acc)
    %{final | tool_calls_acc: nil} |> Map.put(:tool_calls, tool_calls)
  end

  defp handle_stream_chunk(chunk, acc) do
    acc
    |> maybe_append_text(chunk)
    |> maybe_append_reasoning(chunk)
    |> maybe_accumulate_tool_call_delta(chunk)
    |> maybe_capture_final_chunk(chunk)
  end

  defp maybe_append_text(acc, %{text: text}) when text not in [nil, ""] do
    new_content = acc.content <> text

    Logger.debug("[chat_live] stream chunk chat_id=#{acc.chat.id} text=#{inspect(text)}")
    broadcast(acc.chat.id, {:stream_chunk, acc.chat, new_content})

    %{acc | content: new_content}
  end

  defp maybe_append_text(acc, _chunk), do: acc

  defp maybe_append_reasoning(acc, chunk) do
    reasoning = chunk.reasoning || ""
    reasoning_details = chunk.reasoning_details || []

    if reasoning == "" and reasoning_details == [] do
      acc
    else
      new_reasoning = acc.reasoning <> reasoning
      new_reasoning_details = acc.reasoning_details ++ reasoning_details

      Logger.debug(
        "[chat_live] stream reasoning chat_id=#{acc.chat.id} reasoning=#{inspect(chunk.reasoning)} details=#{inspect(chunk.reasoning_details)}"
      )

      broadcast(acc.chat.id, {:stream_reasoning, acc.chat, new_reasoning})

      %{acc | reasoning: new_reasoning, reasoning_details: new_reasoning_details}
    end
  end

  defp maybe_capture_final_chunk(acc, %{type: :usage} = chunk) do
    Logger.debug(
      "[chat_live] stream usage chat_id=#{acc.chat.id} usage=#{inspect(chunk.usage)} raw=#{inspect(chunk.raw)}"
    )

    %{acc | final_chunk: chunk}
  end

  defp maybe_capture_final_chunk(acc, %{type: :done} = chunk) do
    Logger.debug(
      "[chat_live] stream done-with-usage chat_id=#{acc.chat.id} usage=#{inspect(chunk.usage)} raw=#{inspect(chunk.raw)}"
    )

    final_chunk =
      if not is_nil(chunk.usage) or not is_nil(chunk.cost_info) or is_nil(acc.final_chunk) do
        chunk
      else
        acc.final_chunk
      end

    %{acc | final_chunk: final_chunk}
  end

  defp maybe_capture_final_chunk(acc, %{type: type}) do
    Logger.debug("[chat_live] stream chunk (ignored) chat_id=#{acc.chat.id} type=#{type}")
    acc
  end

  defp build_stream_message_attrs(final, tool_calls_history, reasoning_steps) do
    all_reasoning_steps = reasoning_steps ++ build_reasoning_steps(final.reasoning, [])

    %{
      role: "assistant",
      content: final.content,
      reasoning: blank_to_nil(final.reasoning),
      reasoning_steps: all_reasoning_steps,
      reasoning_details: blank_list_to_nil(final.reasoning_details),
      raw_response: final.final_chunk && final.final_chunk.raw,
      tool_calls: blank_list_to_nil(tool_calls_history)
    }
    |> Map.merge(Usage.stream_chunk_attrs(final.final_chunk))
  end

  defp maybe_accumulate_tool_call_delta(acc, %{type: :tool_call_delta, tool_call: deltas})
       when is_list(deltas) do
    new_acc =
      Enum.reduce(deltas, acc.tool_calls_acc, fn delta, tool_calls ->
        idx = delta["index"]

        if is_nil(idx) do
          tool_calls
        else
          existing = Map.get(tool_calls, idx, %{})
          args_so_far = get_in(existing, ["function", "arguments"]) || ""
          new_args = args_so_far <> (get_in(delta, ["function", "arguments"]) || "")

          # Deep-merge the "function" sub-map so the "name" from the first chunk
          # is not overwritten by later chunks that only carry "arguments".
          merged_function =
            Map.merge(
              Map.get(existing, "function", %{}),
              Map.get(delta, "function", %{})
            )
            |> Map.put("arguments", new_args)

          updated =
            existing
            |> Map.merge(delta)
            |> Map.put("function", merged_function)

          Map.put(tool_calls, idx, updated)
        end
      end)

    %{acc | tool_calls_acc: new_acc}
  end

  defp maybe_accumulate_tool_call_delta(acc, _chunk), do: acc

  defp build_tool_calls_from_stream_acc(tool_calls_acc) when map_size(tool_calls_acc) == 0,
    do: nil

  defp build_tool_calls_from_stream_acc(tool_calls_acc) do
    alias LlmComposer.FunctionCallExtractors

    sorted =
      tool_calls_acc
      |> Map.values()
      |> Enum.sort_by(& &1["index"])

    FunctionCallExtractors.from_tool_calls(%{"tool_calls" => sorted})
  end

  defp tool_call_entry(%{name: name, arguments: arguments, result: result}) do
    %{"name" => name, "arguments" => arguments, "result" => to_string(result)}
  end

  defp build_reasoning_steps(reasoning, tool_calls_history) do
    []
    |> maybe_add_reasoning_step(reasoning)
    |> maybe_add_tool_steps(tool_calls_history)
  end

  defp maybe_add_reasoning_step(steps, reasoning) when reasoning in [nil, ""], do: steps

  defp maybe_add_reasoning_step(steps, reasoning) do
    steps ++ [%{"type" => "reasoning", "content" => reasoning}]
  end

  defp maybe_add_tool_steps(steps, tool_calls_history) when tool_calls_history in [nil, []],
    do: steps

  defp maybe_add_tool_steps(steps, tool_calls_history) do
    steps ++
      Enum.map(tool_calls_history, fn %{"name" => name} ->
        %{"type" => "tool_call", "tool_name" => name, "status" => "completed"}
      end)
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp blank_list_to_nil(nil), do: nil
  defp blank_list_to_nil([]), do: nil
  defp blank_list_to_nil(value), do: value

  defp provider_module("openai"), do: LlmComposer.Providers.OpenAI
  defp provider_module("openai_responses"), do: LlmComposer.Providers.OpenAIResponses
  defp provider_module("openrouter"), do: LlmComposer.Providers.OpenRouter
  defp provider_module("ollama"), do: LlmComposer.Providers.Ollama
  defp provider_module("google"), do: LlmComposer.Providers.Google

  defp llm_runner do
    Application.get_env(:livellm, :llm_runner, Livellm.Chats.LlmRunner)
  end
end
