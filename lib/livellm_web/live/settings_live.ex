defmodule LivellmWeb.SettingsLive do
  use LivellmWeb, :live_view

  import LivellmWeb.ChatComponents

  alias Livellm.Config
  alias Livellm.Config.ProviderConfig

  @conversations [
    %{id: 1, title: "What is Elixir?", active: false},
    %{id: 2, title: "Phoenix LiveView tutorial", active: false},
    %{id: 3, title: "How to use Ecto associations", active: false},
    %{id: 4, title: "Tailwind CSS v4 changes", active: false},
    %{id: 5, title: "BEAM concurrency model", active: false}
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:conversations, @conversations)
     |> assign(:form, to_form(Config.change_provider_config(%ProviderConfig{})))
     |> stream(:provider_configs, Config.list_provider_configs())}
  end

  def handle_event("save_config", %{"provider_config" => params}, socket) do
    case Config.create_provider_config(params) do
      {:ok, config} ->
        {:noreply,
         socket
         |> stream_insert(:provider_configs, config)
         |> assign(:form, to_form(Config.change_provider_config(%ProviderConfig{})))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("enable_config", %{"id" => id}, socket) do
    config = Config.get_provider_config!(id)
    {:ok, _} = Config.set_enabled(config)
    {:noreply, stream(socket, :provider_configs, Config.list_provider_configs(), reset: true)}
  end

  def handle_event("delete_config", %{"id" => id}, socket) do
    config = Config.get_provider_config!(id)
    {:ok, _} = Config.delete_provider_config(config)
    {:noreply, stream_delete(socket, :provider_configs, config)}
  end
end
