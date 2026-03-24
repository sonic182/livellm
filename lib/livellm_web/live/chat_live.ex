defmodule LivellmWeb.ChatLive do
  @moduledoc false

  use LivellmWeb, :live_view

  import LivellmWeb.ChatComponents

  alias Livellm.Chats
  alias Livellm.Chats.ActiveTasks
  alias Livellm.Config
  alias Livellm.Usage
  alias LlmComposer

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

    {:noreply,
     socket
     |> assign(:selected_provider_id, new_provider_id)
     |> assign(:selected_model, selected_model)
     |> assign(:selected_reasoning_effort, reasoning_effort)
     |> assign(:stream_mode, stream_mode)
     |> push_event("save_chat_settings", %{
       provider_id: new_provider_id,
       model: selected_model,
       reasoning_effort: reasoning_effort,
       streaming: stream_mode
     })}
  end

  @impl true
  def handle_event("restore_chat_settings", params, socket) do
    provider_id = parse_provider_id(params["provider_id"])
    model = params["model"] || ""
    reasoning_effort = parse_effort(params["reasoning_effort"])
    stream_mode = Map.get(params, "streaming", true) in [true, "true"]

    valid_provider_id =
      if Enum.any?(socket.assigns.provider_configs, &(&1.id == provider_id)),
        do: provider_id,
        else: nil

    {:noreply,
     socket
     |> assign(:selected_provider_id, valid_provider_id)
     |> assign(:selected_model, model)
     |> assign(:selected_reasoning_effort, reasoning_effort)
     |> assign(:stream_mode, stream_mode)}
  end

  @impl true
  def handle_info({:llm_done, _chat, assistant_msg}, socket) do
    {:noreply,
     socket
     |> assign(:waiting, false)
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
     |> put_flash(:error, "LLM error: #{inspect(reason)}")
     |> push_event("focus_input", %{})}
  end

  @impl true
  def handle_info({:stream_chunk, _chat, content}, socket) do
    {:noreply, assign(socket, :streaming_content, content)}
  end

  @impl true
  def handle_info({:stream_reasoning, _chat, reasoning}, socket) do
    {:noreply, assign(socket, :streaming_reasoning, reasoning)}
  end

  @impl true
  def handle_info({:stream_done, _chat, %Livellm.Chats.Message{} = assistant_msg}, socket) do
    {:noreply,
     socket
     |> assign(:waiting, false)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_reasoning, nil)
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
    req
    |> run_llm_request(history, chat.id)
    |> handle_llm_result(chat, req)
  rescue
    error ->
      Logger.error(
        "[chat_live] task crashed chat_id=#{chat.id} error=#{Exception.message(error)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      broadcast(chat.id, {:llm_response, chat, {:error, error}})
  after
    ActiveTasks.mark_done(chat.id)
  end

  defp run_llm_request(req, history, chat_id) do
    llm_runner().run(
      req.provider_config,
      req.model,
      history,
      req.reasoning_effort,
      chat_id,
      stream: req.stream_mode
    )
  end

  defp handle_llm_result({:ok, %{stream: stream, provider: provider}}, chat, req)
       when not is_nil(stream) do
    Logger.debug("[chat_live] streaming started chat_id=#{chat.id} provider=#{provider}")

    final = run_stream(stream, provider, req.model, chat)

    Logger.debug(
      "[chat_live] streaming done chat_id=#{chat.id} content_length=#{String.length(final.content)} usage=#{inspect(final.final_chunk && final.final_chunk.usage)}"
    )

    case Chats.create_message(chat, build_stream_message_attrs(final)) do
      {:ok, assistant_msg} ->
        broadcast(chat.id, {:stream_done, chat, assistant_msg})

      {:error, changeset} ->
        Logger.error(
          "[chat_live] failed to save stream message chat_id=#{chat.id} errors=#{inspect(changeset.errors)}"
        )

        broadcast(chat.id, {:stream_save_failed, chat})
    end
  end

  defp handle_llm_result({:ok, llm_response}, chat, _req) do
    %{content: content, reasoning: reasoning, reasoning_details: reasoning_details} =
      llm_response.main_response

    attrs =
      %{
        role: "assistant",
        content: content,
        reasoning: reasoning,
        reasoning_details: reasoning_details,
        raw_response: llm_response.raw
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

  defp handle_llm_result({:error, reason}, chat, _req) do
    broadcast(chat.id, {:llm_response, chat, {:error, reason}})
  end

  defp run_stream(stream, provider, model, chat) do
    initial_acc = %{
      content: "",
      reasoning: "",
      reasoning_details: [],
      final_chunk: nil,
      chat: chat
    }

    stream
    # |> Stream.map(fn data ->
    #   Logger.debug("[debug][stream] data=#{inspect(data)}")
    #   data
    # end)
    |> LlmComposer.parse_stream_response(provider, track_costs: true, model: model)
    |> Enum.reduce(initial_acc, &handle_stream_chunk/2)
  end

  defp handle_stream_chunk(chunk, acc) do
    acc
    |> maybe_append_text(chunk)
    |> maybe_append_reasoning(chunk)
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

  defp build_stream_message_attrs(final) do
    %{
      role: "assistant",
      content: final.content,
      reasoning: blank_to_nil(final.reasoning),
      reasoning_details: blank_list_to_nil(final.reasoning_details),
      raw_response: final.final_chunk && final.final_chunk.raw
    }
    |> Map.merge(Usage.stream_chunk_attrs(final.final_chunk))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp blank_list_to_nil(nil), do: nil
  defp blank_list_to_nil([]), do: nil
  defp blank_list_to_nil(value), do: value

  defp llm_runner do
    Application.get_env(:livellm, :llm_runner, Livellm.Chats.LlmRunner)
  end
end
