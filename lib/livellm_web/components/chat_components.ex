defmodule LivellmWeb.ChatComponents do
  @moduledoc """
  Shared function components for the chat interface: sidebar and message bubbles.
  """

  use LivellmWeb, :html

  @doc """
  Renders the sidebar with conversation list, new chat button, and settings link.
  """
  attr :current_page, :atom, required: true, doc: "current page: :chat or :settings"
  attr :chats, :list, required: true, doc: "list of Chat structs"
  attr :current_chat_id, :any, default: nil, doc: "id of the currently active chat"

  def sidebar(assigns) do
    ~H"""
    <aside
      id="sidebar"
      class="flex flex-col w-64 h-full bg-zinc-900 border-r border-zinc-800 shrink-0"
    >
      <%!-- Brand --%>
      <div class="flex items-center gap-2.5 px-4 py-4 border-b border-zinc-800">
        <div class="size-7 rounded-lg bg-violet-600 flex items-center justify-center shrink-0">
          <.icon name="hero-cpu-chip" class="size-4 text-white" />
        </div>
        <span class="font-semibold text-sm tracking-tight text-zinc-100">LiveLLM</span>
      </div>

      <%!-- New Chat --%>
      <div class="px-3 pt-3">
        <.link
          navigate={~p"/"}
          id="new-chat-btn"
          class="flex items-center gap-2 w-full px-3 py-2 rounded-lg text-sm text-zinc-400 hover:text-zinc-100 hover:bg-zinc-800 transition-colors duration-150"
        >
          <.icon name="hero-pencil-square" class="size-4 shrink-0" /> New Chat
        </.link>
      </div>

      <%!-- Chats list --%>
      <nav id="chats-nav" class="flex-1 overflow-y-auto px-3 py-2">
        <p class="px-3 py-2 text-xs font-medium text-zinc-500 uppercase tracking-wider">Recent</p>
        <%= if @chats == [] do %>
          <p class="px-3 py-2 text-xs text-zinc-600 italic">No chats yet</p>
        <% else %>
          <%= for chat <- @chats do %>
            <.link
              navigate={~p"/chats/#{chat.id}"}
              id={"chat-#{chat.id}"}
              class={[
                "flex items-center gap-2 w-full px-3 py-2 rounded-lg text-sm truncate transition-colors duration-150",
                chat.id == @current_chat_id && "bg-zinc-800 text-zinc-100",
                chat.id != @current_chat_id && "text-zinc-400 hover:text-zinc-100 hover:bg-zinc-800"
              ]}
            >
              <.icon name="hero-chat-bubble-left-ellipsis" class="size-4 shrink-0" />
              <span class="truncate">{chat.title}</span>
            </.link>
          <% end %>
        <% end %>
      </nav>

      <%!-- Bottom: Settings --%>
      <div class="border-t border-zinc-800 px-3 py-3">
        <.link
          navigate={~p"/settings"}
          id="settings-link"
          class={[
            "flex items-center gap-2 w-full px-3 py-2 rounded-lg text-sm transition-colors duration-150",
            @current_page == :settings && "bg-zinc-800 text-zinc-100",
            @current_page != :settings && "text-zinc-400 hover:text-zinc-100 hover:bg-zinc-800"
          ]}
        >
          <.icon name="hero-cog-6-tooth" class="size-4 shrink-0" /> Settings
        </.link>
      </div>
    </aside>
    """
  end

  @doc """
  Renders a single chat message bubble.
  The root element must have the stream `id` for LiveView stream diffing.
  """
  attr :id, :string, required: true, doc: "DOM id (from LiveView stream)"
  attr :message, :map, required: true, doc: "message map with :role and :content"

  def chat_message(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "flex gap-3 px-6 py-3 group",
        @message.role == "user" && "flex-row-reverse"
      ]}
    >
      <%!-- Avatar --%>
      <div class={[
        "size-8 rounded-full shrink-0 flex items-center justify-center text-xs font-semibold mt-0.5",
        @message.role == "assistant" && "bg-violet-700 text-white",
        @message.role == "user" && "bg-zinc-700 text-zinc-300"
      ]}>
        <%= if @message.role == "assistant" do %>
          <.icon name="hero-cpu-chip" class="size-4" />
        <% else %>
          <span>U</span>
        <% end %>
      </div>

      <%!-- Bubble --%>
      <div class={[
        "max-w-[72%] rounded-2xl px-4 py-3 text-sm leading-relaxed",
        @message.role == "assistant" && "bg-zinc-800 text-zinc-100 rounded-tl-sm",
        @message.role == "user" && "bg-violet-600 text-white rounded-tr-sm"
      ]}>
        {@message.content}
      </div>
    </div>
    """
  end
end
