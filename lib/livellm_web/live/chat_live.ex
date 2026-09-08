defmodule LivellmWeb.ChatLive do
  @moduledoc false

  use LivellmWeb, :live_view

  import LivellmWeb.ChatComponents

  alias Livellm.Chats
  alias Livellm.Chats.ActiveTasks
  alias Livellm.Config
  alias Livellm.Usage
  alias LlmComposer.Agent.Result, as: AgentResult
  alias LlmComposer.Agent.StreamCollector
  alias LlmComposer.StreamChunk

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
     |> assign(:streaming_content, nil)
     |> assign(:streaming_reasoning, nil)
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
        {:ok, user_msg} = Chats.create_message(chat, %{role: "user", content: content})

        provider_config = Enum.find(configs, &(&1.id == provider_id))
        history = Chats.list_messages(chat)

        req = %{
          provider_config: provider_config,
          model: model,
          reasoning_effort: socket.assigns.selected_reasoning_effort,
          stream_mode: socket.assigns.stream_mode
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
     |> push_event("save_chat_settings", %{streaming: stream_mode})}
  end

  @impl true
  def handle_event("restore_chat_settings", params, socket) do
    stream_mode = Map.get(params, "streaming", true) in [true, "true"]
    {:noreply, assign(socket, :stream_mode, stream_mode)}
  end

  @impl true
  def handle_info({:llm_done, chat, assistant_msg}, socket) do
    {:noreply,
     socket
     |> assign(:waiting, false)
     |> assign(:chat_metrics, chat_metrics(chat))
     |> stream_insert(:messages, assistant_msg)
     |> push_event("focus_input", %{})}
  end

  @impl true
  def handle_info({:llm_response, _chat, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:waiting, false)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_reasoning, nil)
     |> put_flash(:error, "LLM error: #{inspect(reason)}")
     |> push_event("focus_input", %{})}
  end

  @impl true
  def handle_info({:stream_chunk, _chat, delta}, socket) do
    {:noreply,
     assign(socket, :streaming_content, (socket.assigns.streaming_content || "") <> delta)}
  end

  @impl true
  def handle_info({:stream_reasoning, _chat, delta}, socket) do
    {:noreply,
     assign(socket, :streaming_reasoning, (socket.assigns.streaming_reasoning || "") <> delta)}
  end

  @impl true
  def handle_info({:stream_done, chat, %Livellm.Chats.Message{} = assistant_msg}, socket) do
    {:noreply,
     socket
     |> assign(:waiting, false)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_reasoning, nil)
     |> assign(:chat_metrics, chat_metrics(chat))
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
     |> put_flash(:error, "Stream completed but failed to save response.")
     |> push_event("focus_input", %{})}
  end

  # --- Private ---

  defp stream_topic(chat_id), do: "chat_stream:#{chat_id}"

  # Recomputed rather than merged: a finished turn can race the `push_patch` that re-aggregates
  # the chat, and merging would then count the same message twice.
  defp chat_metrics(chat) do
    chat
    |> Chats.list_messages()
    |> Usage.aggregate_chat_metrics()
  end

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
    attach_reasoning_handler(chat)

    req
    |> run_llm_request(history, chat.id)
    |> handle_llm_result(chat)
  rescue
    error ->
      Logger.error(
        "[chat_live] task crashed chat_id=#{chat.id} error=#{Exception.message(error)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      broadcast(chat.id, {:llm_response, chat, {:error, error}})
  after
    detach_reasoning_handler(chat)
    ActiveTasks.mark_done(chat.id)
  end

  defp run_llm_request(req, history, chat_id) do
    llm_runner().run(
      req.provider_config,
      req.model,
      history,
      req.reasoning_effort,
      chat_id,
      stream: req.stream_mode,
      telemetry_metadata: %{chat_id: chat_id}
    )
  end

  # `Agent` keeps reasoning off the answer stream and emits it as telemetry instead, so the
  # live reasoning panel is fed from a run-scoped handler.
  defp reasoning_handler_id(chat), do: {__MODULE__, :reasoning, chat.id}

  defp attach_reasoning_handler(chat) do
    chat_id = chat.id

    :telemetry.attach(
      reasoning_handler_id(chat),
      [:llm_composer, :agent, :reasoning, :delta],
      fn
        _event, _measurements, %{chat_id: ^chat_id, reasoning: reasoning}, _config
        when is_binary(reasoning) ->
          broadcast(chat_id, {:stream_reasoning, chat, reasoning})

        _event, _measurements, _metadata, _config ->
          :ok
      end,
      nil
    )
  end

  defp detach_reasoning_handler(chat) do
    :telemetry.detach(reasoning_handler_id(chat))
  end

  defp handle_llm_result({:ok, %AgentResult{} = result}, chat) do
    cost_info = StreamCollector.aggregate_cost_infos(result.cost_infos)
    save_and_broadcast(chat, agent_message_attrs(result, cost_info), :llm_done)
  end

  defp handle_llm_result({:ok, stream}, chat) do
    Logger.debug("[chat_live] streaming started chat_id=#{chat.id}")

    case run_agent_stream(stream, chat) do
      %StreamChunk{type: :done, cost_info: cost_info, metadata: %{agent_result: result}} ->
        save_and_broadcast(chat, agent_message_attrs(result, cost_info), :stream_done)

      %StreamChunk{type: :error, metadata: metadata} ->
        broadcast(chat.id, {:llm_response, chat, {:error, metadata[:reason]}})

      nil ->
        broadcast(chat.id, {:llm_response, chat, {:error, :empty_stream}})
    end
  end

  defp handle_llm_result({:error, reason}, chat) do
    broadcast(chat.id, {:llm_response, chat, {:error, reason}})
  end

  # The agent stream carries only the final, tool-free answer plus a terminal :done/:error chunk.
  defp run_agent_stream(stream, chat) do
    Enum.reduce(stream, nil, fn
      %StreamChunk{type: :text_delta, text: text}, acc when text not in [nil, ""] ->
        broadcast(chat.id, {:stream_chunk, chat, text})
        acc

      %StreamChunk{type: type} = chunk, _acc when type in [:done, :error] ->
        chunk

      _chunk, acc ->
        acc
    end)
  end

  # ponytail: in stream mode `LlmComposer.Agent` reassembles the turn into a synthetic response
  # that carries no `raw`, `response_id` or `reasoning_details`, so those persist as nil (and
  # openai_responses follow-ups lose `previous_response_id` reuse). Fix belongs in llm_composer.
  defp agent_message_attrs(%AgentResult{response: response}, cost_info) do
    response = %{response | cost_info: cost_info}
    main = response.main_response

    %{
      role: "assistant",
      content: main.content,
      reasoning: main.reasoning,
      reasoning_details: main.reasoning_details,
      raw_response: response.raw
    }
    |> Map.merge(Usage.cost_tracking_attrs(response))
  end

  defp save_and_broadcast(chat, attrs, event) do
    case Chats.create_message(chat, attrs) do
      {:ok, assistant_msg} ->
        broadcast(chat.id, {event, chat, assistant_msg})

      {:error, changeset} ->
        Logger.error(
          "[chat_live] failed to save assistant message chat_id=#{chat.id} errors=#{inspect(changeset.errors)}"
        )

        broadcast(chat.id, save_failure(chat, event))
    end
  end

  defp save_failure(chat, :stream_done), do: {:stream_save_failed, chat}
  defp save_failure(chat, :llm_done), do: {:llm_response, chat, {:error, :save_failed}}

  defp llm_runner do
    Application.get_env(:livellm, :llm_runner, Livellm.Chats.LlmRunner)
  end
end
