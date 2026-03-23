defmodule LivellmWeb.ChatLive do
  use LivellmWeb, :live_view

  import LivellmWeb.ChatComponents

  alias Livellm.Chats
  alias Livellm.Chats.LlmRunner
  alias Livellm.Config

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
     |> stream(:messages, [])}
  end

  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    {:noreply,
     socket
     |> assign(:page_title, "New Chat")
     |> assign(:chat, nil)
     |> assign(:current_chat_id, nil)
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

    chat =
      chat ||
        case Chats.create_chat(%{
               title: String.slice(content, 0, 60),
               model: model,
               provider_config_id: provider_id
             }) do
          {:ok, c} -> c
        end

    {:ok, user_msg} = Chats.create_message(chat, %{role: "user", content: content})

    provider_config = Enum.find(configs, &(&1.id == provider_id))
    history = Chats.list_messages(chat)
    pid = self()

    reasoning_effort = socket.assigns.selected_reasoning_effort

    Task.start(fn ->
      result = LlmRunner.run(provider_config, model, history, reasoning_effort, chat.id)
      send(pid, {:llm_response, chat, result})
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

  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_chat_settings", params, socket) do
    new_provider_id = parse_provider_id(params["provider_id"])
    selected_model = resolve_model(params, socket.assigns, new_provider_id)
    reasoning_effort = parse_effort(params["reasoning_effort"])

    {:noreply,
     socket
     |> assign(:selected_provider_id, new_provider_id)
     |> assign(:selected_model, selected_model)
     |> assign(:selected_reasoning_effort, reasoning_effort)
     |> push_event("save_chat_settings", %{
       provider_id: new_provider_id,
       model: selected_model,
       reasoning_effort: reasoning_effort
     })}
  end

  def handle_event("restore_chat_settings", params, socket) do
    provider_id = parse_provider_id_from_restore(params["provider_id"])
    model = params["model"] || ""
    reasoning_effort = parse_effort(params["reasoning_effort"])

    valid_provider_id =
      if Enum.any?(socket.assigns.provider_configs, &(&1.id == provider_id)),
        do: provider_id,
        else: nil

    {:noreply,
     socket
     |> assign(:selected_provider_id, valid_provider_id)
     |> assign(:selected_model, model)
     |> assign(:selected_reasoning_effort, reasoning_effort)}
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

    {:ok, assistant_msg} =
      Chats.create_message(chat, %{
        role: "assistant",
        content: content,
        reasoning: reasoning,
        reasoning_details: reasoning_details,
        raw_response: llm_response.raw
      })

    {:noreply,
     socket
     |> assign(:waiting, false)
     |> stream_insert(:messages, assistant_msg)}
  end

  def handle_info({:llm_response, _chat, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:waiting, false)
     |> put_flash(:error, "LLM error: #{inspect(reason)}")}
  end
end
