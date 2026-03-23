defmodule LivellmWeb.ChatLive do
  use LivellmWeb, :live_view

  import LivellmWeb.ChatComponents

  @conversations [
    %{id: 1, title: "What is Elixir?", active: true},
    %{id: 2, title: "Phoenix LiveView tutorial", active: false},
    %{id: 3, title: "How to use Ecto associations", active: false},
    %{id: 4, title: "Tailwind CSS v4 changes", active: false},
    %{id: 5, title: "BEAM concurrency model", active: false}
  ]

  @messages [
    %{
      id: 1,
      role: :user,
      content: "What is Elixir and why should I use it?"
    },
    %{
      id: 2,
      role: :assistant,
      content:
        "Elixir is a dynamic, functional language built on the Erlang VM (BEAM). It excels at building scalable, fault-tolerant distributed systems with excellent concurrency primitives. If you need high availability, low latency, or real-time features, Elixir is a fantastic choice."
    },
    %{
      id: 3,
      role: :user,
      content: "How does Phoenix LiveView work?"
    },
    %{
      id: 4,
      role: :assistant,
      content:
        "LiveView keeps a persistent WebSocket connection between the browser and server. When state changes on the server, it computes a minimal HTML diff and sends only the changed parts to the client. This means you get rich, real-time interactivity without writing custom JavaScript for most use cases."
    }
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:conversations, @conversations)
     |> stream(:messages, @messages)}
  end

  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end
end
