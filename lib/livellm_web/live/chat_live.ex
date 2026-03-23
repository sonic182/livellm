defmodule LivellmWeb.ChatLive do
  use LivellmWeb, :live_view

  import LivellmWeb.ChatComponents

  alias Livellm.Chats
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

    Task.start(fn ->
      result = call_llm(provider_config, model, history)
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
    provider_id = params["provider_id"]
    current_provider_id = socket.assigns.selected_provider_id

    new_provider_id =
      case provider_id do
        "" -> nil
        id -> String.to_integer(id)
      end

    selected_model =
      cond do
        provider_id == "" ->
          ""

        new_provider_id != current_provider_id ->
          config = Enum.find(socket.assigns.provider_configs, &(&1.id == new_provider_id))
          (config && config.default_model) || ""

        true ->
          params["model"] || socket.assigns.selected_model
      end

    {:noreply,
     socket
     |> assign(:selected_provider_id, new_provider_id)
     |> assign(:selected_model, selected_model)}
  end

  def handle_info({:llm_response, chat, {:ok, llm_response}}, socket) do
    content = llm_response.main_response.content

    {:ok, assistant_msg} =
      Chats.create_message(chat, %{
        role: "assistant",
        content: content,
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

  defp call_llm(nil, _model, _history), do: {:error, :no_provider}
  defp call_llm(_config, "", _history), do: {:error, :no_model}

  defp call_llm(config, model, history) do
    provider_mod = provider_module(config.provider)
    opts = [model: model, api_key: config.api_key]
    opts = if config.base_url, do: Keyword.put(opts, :url, config.base_url), else: opts

    settings = %LlmComposer.Settings{
      providers: [{provider_mod, opts}],
      system_prompt: "You are a helpful assistant."
    }

    messages = Enum.map(history, &LlmComposer.Message.new(String.to_existing_atom(&1.role), &1.content))

    LlmComposer.run_completion(settings, messages)
  end

  defp provider_module("openai"), do: LlmComposer.Providers.OpenAI
  defp provider_module("openrouter"), do: LlmComposer.Providers.OpenRouter
  defp provider_module("ollama"), do: LlmComposer.Providers.Ollama
  defp provider_module("google"), do: LlmComposer.Providers.Google
end
