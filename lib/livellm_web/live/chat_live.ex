defmodule LivellmWeb.ChatLive do
  use LivellmWeb, :live_view

  import LivellmWeb.ChatComponents

  alias Livellm.Chats
  alias Livellm.Config
  alias Livellm.Usage
  alias LlmComposer

  require Logger

  def mount(_params, _session, socket) do
    provider_configs = Config.list_provider_configs()
    enabled = Enum.find(provider_configs, & &1.enabled)

    {:ok,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:chats, Chats.list_chats())
     |> assign(:chat, nil)
     |> assign(:current_chat_id, nil)
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

  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    {:noreply,
     socket
     |> assign(:page_title, "New Chat")
     |> assign(:chat, nil)
     |> assign(:current_chat_id, nil)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_reasoning, nil)
     |> assign(:chat_metrics, Usage.empty_chat_metrics())
     |> stream(:messages, [], reset: true)}
  end

  def handle_params(%{"id" => id}, _uri, %{assigns: %{live_action: :show}} = socket) do
    chat = Chats.get_chat!(id)
    messages = Chats.list_messages(chat)

    {:noreply,
     socket
     |> assign(:page_title, chat.title)
     |> assign(:chat, chat)
     |> assign(:current_chat_id, chat.id)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_reasoning, nil)
     |> assign(:chat_metrics, Usage.aggregate_chat_metrics(messages))
     |> stream(:messages, messages, reset: true)}
  end

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
        pid = self()

        reasoning_effort = socket.assigns.selected_reasoning_effort
        stream_mode = socket.assigns.stream_mode

        Task.Supervisor.start_child(Livellm.TaskSupervisor, fn ->
          run_llm_task(
            provider_config,
            model,
            history,
            reasoning_effort,
            chat,
            stream_mode,
            pid
          )
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

  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

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

  def handle_event("restore_chat_settings", params, socket) do
    provider_id = parse_provider_id_from_restore(params["provider_id"])
    model = params["model"] || ""
    reasoning_effort = parse_effort(params["reasoning_effort"])
    stream_mode = Map.get(params, "streaming", true)

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

  defp parse_provider_id(""), do: nil
  defp parse_provider_id(id), do: String.to_integer(id)

  defp parse_provider_id_from_restore(nil), do: nil
  defp parse_provider_id_from_restore(id) when is_integer(id), do: id
  defp parse_provider_id_from_restore(id) when is_binary(id), do: String.to_integer(id)

  defp parse_effort(""), do: nil
  defp parse_effort(val), do: val

  defp resolve_model(%{"provider_id" => ""}, _assigns, _new_id), do: ""

  defp resolve_model(params, assigns, new_provider_id) do
    if new_provider_id != assigns.selected_provider_id do
      config = Enum.find(assigns.provider_configs, &(&1.id == new_provider_id))
      (config && config.default_model) || ""
    else
      params["model"] || assigns.selected_model
    end
  end

  def handle_info({:llm_response, chat, {:ok, llm_response}}, socket) do
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

    {:ok, assistant_msg} =
      Chats.create_message(chat, attrs)

    {:noreply,
     socket
     |> assign(:waiting, false)
     |> assign(
       :chat_metrics,
       Usage.merge_chat_metrics(socket.assigns.chat_metrics, assistant_msg)
     )
     |> stream_insert(:messages, assistant_msg)}
  end

  def handle_info({:llm_response, _chat, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:waiting, false)
     |> put_flash(:error, "LLM error: #{inspect(reason)}")}
  end

  def handle_info({:stream_chunk, _chat, content}, socket) do
    {:noreply, assign(socket, :streaming_content, content)}
  end

  def handle_info({:stream_reasoning, _chat, reasoning}, socket) do
    {:noreply, assign(socket, :streaming_reasoning, reasoning)}
  end

  def handle_info(
        {:stream_done, chat,
         %{
           content: content,
           reasoning: reasoning,
           reasoning_details: reasoning_details,
           usage: usage,
           usage_raw: usage_raw,
           provider: provider
         }},
        socket
      ) do
    attrs =
      %{
        role: "assistant",
        content: content,
        reasoning: blank_to_nil(reasoning),
        reasoning_details: blank_list_to_nil(reasoning_details),
        raw_response: usage_raw
      }
      |> Map.merge(Usage.stream_cost_tracking_attrs(provider, usage, usage_raw))

    {:ok, assistant_msg} = Chats.create_message(chat, attrs)

    {:noreply,
     socket
     |> assign(:waiting, false)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_reasoning, nil)
     |> assign(
       :chat_metrics,
       Usage.merge_chat_metrics(socket.assigns.chat_metrics, assistant_msg)
     )
     |> stream_insert(:messages, assistant_msg)}
  end

  defp run_llm_task(provider_config, model, history, reasoning_effort, chat, stream_mode, pid) do
    provider_config
    |> run_llm_request(model, history, reasoning_effort, chat.id, stream_mode)
    |> handle_llm_result(chat, pid)
  rescue
    error ->
      Logger.error(
        "[chat_live] task crashed chat_id=#{chat.id} error=#{Exception.message(error)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      send(pid, {:llm_response, chat, {:error, error}})
  end

  defp run_llm_request(
         provider_config,
         model,
         history,
         reasoning_effort,
         chat_id,
         stream_mode
       ) do
    llm_runner().run(provider_config, model, history, reasoning_effort, chat_id,
      stream: stream_mode
    )
  end

  defp handle_llm_result({:ok, %{stream: stream, provider: provider}}, chat, pid)
       when not is_nil(stream) do
    Logger.debug("[chat_live] streaming started chat_id=#{chat.id} provider=#{provider}")

    final = run_stream(stream, provider, chat, pid)

    Logger.debug(
      "[chat_live] streaming done chat_id=#{chat.id} content_length=#{String.length(final.content)} usage=#{inspect(final.usage)}"
    )

    send(pid, {:stream_done, chat, final})
  end

  defp handle_llm_result(result, chat, pid) do
    send(pid, {:llm_response, chat, result})
  end

  defp run_stream(stream, provider, chat, pid) do
    stream
    # useful for debugging stream case
    # |> Stream.map(fn data ->
    #   Logger.debug("[debug][stream] data=#{inspect(data)}")
    #
    #   data
    # end)
    |> LlmComposer.parse_stream_response(provider)
    |> Enum.reduce(
      %{
        content: "",
        reasoning: "",
        reasoning_details: [],
        usage: nil,
        usage_raw: nil,
        provider: provider
      },
      &handle_stream_chunk(&1, &2, pid, chat)
    )
  end

  defp handle_stream_chunk(%{type: :text_delta} = chunk, acc, pid, chat) do
    new_content = acc.content <> (chunk.text || "")
    Logger.debug("[chat_live] stream chunk chat_id=#{chat.id} text=#{inspect(chunk.text)}")
    send(pid, {:stream_chunk, chat, new_content})
    %{acc | content: new_content}
  end

  defp handle_stream_chunk(%{type: :reasoning_delta} = chunk, acc, pid, chat) do
    new_reasoning = acc.reasoning <> (chunk.reasoning || "")
    new_reasoning_details = acc.reasoning_details ++ (chunk.reasoning_details || [])

    Logger.debug(
      "[chat_live] stream reasoning chat_id=#{chat.id} reasoning=#{inspect(chunk.reasoning)} details=#{inspect(chunk.reasoning_details)}"
    )

    send(pid, {:stream_reasoning, chat, new_reasoning})
    %{acc | reasoning: new_reasoning, reasoning_details: new_reasoning_details}
  end

  defp handle_stream_chunk(%{type: :done, usage: usage} = chunk, acc, pid, chat)
       when not is_nil(usage) do
    acc =
      if (chunk.reasoning || "") != "" or (chunk.reasoning_details || []) != [] do
        handle_stream_chunk(%{chunk | type: :reasoning_delta}, acc, pid, chat)
      else
        acc
      end

    Logger.debug(
      "[chat_live] stream done-with-usage chat_id=#{chat.id} usage=#{inspect(chunk.usage)} raw=#{inspect(chunk.raw)}"
    )

    %{acc | usage: chunk.usage, usage_raw: chunk.raw}
  end

  defp handle_stream_chunk(%{type: :usage} = chunk, acc, _pid, chat) do
    Logger.debug(
      "[chat_live] stream usage chat_id=#{chat.id} usage=#{inspect(chunk.usage)} raw=#{inspect(chunk.raw)}"
    )

    %{acc | usage: chunk.usage, usage_raw: chunk.raw}
  end

  defp handle_stream_chunk(%{type: type} = _chunk, acc, _pid, chat) do
    Logger.debug("[chat_live] stream chunk (ignored) chat_id=#{chat.id} type=#{type}")
    acc
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
