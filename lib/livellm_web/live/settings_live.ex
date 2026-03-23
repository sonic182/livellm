defmodule LivellmWeb.SettingsLive do
  use LivellmWeb, :live_view

  import LivellmWeb.ChatComponents

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
     |> assign(:conversations, @conversations)}
  end
end
