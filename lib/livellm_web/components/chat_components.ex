defmodule LivellmWeb.ChatComponents do
  @moduledoc """
  Shared function components for the chat interface: sidebar and message bubbles.
  """

  use LivellmWeb, :html

  alias MDEx.Document

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
            <div id={"chat-item-#{chat.id}"} class="group relative flex items-center rounded-lg">
              <.link
                navigate={~p"/chats/#{chat.id}"}
                id={"chat-#{chat.id}"}
                class={[
                  "flex items-center gap-2 w-full px-3 py-2 pr-8 rounded-lg text-sm truncate transition-colors duration-150",
                  chat.id == @current_chat_id && "bg-zinc-800 text-zinc-100",
                  chat.id != @current_chat_id && "text-zinc-400 hover:text-zinc-100 hover:bg-zinc-800"
                ]}
              >
                <.icon name="hero-chat-bubble-left-ellipsis" class="size-4 shrink-0 mt-0.5" />
                <div class="flex flex-col min-w-0">
                  <span class="truncate">{chat.title}</span>
                  <span class="text-xs text-zinc-500 group-hover:text-zinc-400">
                    {Calendar.strftime(chat.inserted_at, "%b %-d %H:%M")}
                  </span>
                </div>
              </.link>
              <button
                phx-click="delete_chat"
                phx-value-id={chat.id}
                id={"delete-chat-#{chat.id}"}
                data-confirm="Delete this chat? This cannot be undone."
                class="absolute right-1.5 p-1 rounded opacity-0 group-hover:opacity-100 text-zinc-500 hover:text-red-400 hover:bg-zinc-700 transition-all duration-150"
                title="Delete chat"
              >
                <.icon name="hero-trash" class="size-3.5" />
              </button>
            </div>
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
        "flex gap-3 px-6 py-1.5 group",
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
      <div class="max-w-[72%] w-fit space-y-2">
        <%= if @message.role == "assistant" and
              ((is_binary(@message.reasoning) and @message.reasoning != "") or
                 ((@message.reasoning_tokens || 0) > 0)) do %>
          <details
            id={"#{@id}-reasoning"}
            class="rounded-2xl rounded-tl-sm border border-amber-500/20 bg-amber-500/10 px-4 py-3 text-sm text-amber-100"
          >
            <summary class="flex cursor-pointer list-none items-center justify-between gap-3">
              <span class="text-[11px] font-semibold uppercase tracking-[0.18em] text-amber-200/80">
                Thinking
              </span>
              <%= if (@message.reasoning_tokens || 0) > 0 do %>
                <span
                  id={"#{@id}-reasoning-tokens"}
                  class="rounded-full border border-amber-500/20 bg-amber-500/10 px-2 py-0.5 text-[11px] font-medium text-amber-200"
                >
                  {@message.reasoning_tokens} reasoning
                </span>
              <% end %>
            </summary>
            <%= if is_binary(@message.reasoning) and @message.reasoning != "" do %>
              <div id={"#{@id}-reasoning-content"} class="mt-3 whitespace-pre-wrap leading-relaxed">
                {@message.reasoning}
              </div>
            <% end %>
          </details>
        <% end %>

        <div class={[
          "rounded-2xl text-sm",
          @message.role == "assistant" &&
            "bg-zinc-800 text-zinc-100 rounded-tl-sm px-4 py-3 leading-relaxed",
          @message.role == "user" && "bg-violet-600 text-white rounded-tr-sm px-3 py-2 break-words"
        ]}>
          <%= if @message.role == "assistant" do %>
            <.markdown_content markdown={@message.content} class="chat-markdown" />
          <% else %>
            {@message.content}
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :markdown, :string, required: true, doc: "markdown content to render"
  attr :class, :string, default: nil, doc: "extra classes for the wrapper"
  attr :streaming, :boolean, default: false, doc: "whether the markdown is partial"

  def markdown_content(assigns) do
    assigns =
      assign(assigns, :rendered_markdown, render_markdown(assigns.markdown, assigns.streaming))

    ~H"""
    <div class={@class}>
      {@rendered_markdown}
    </div>
    """
  end

  defp render_markdown(nil, _streaming), do: ""

  defp render_markdown(markdown, streaming) when is_binary(markdown) do
    markdown
    |> MDEx.to_html!(mdex_options(streaming))
    |> raw()
  rescue
    _error ->
      html_escape(markdown)
  end

  defp mdex_options(streaming) do
    [
      extension: [
        autolink: true,
        footnotes: true,
        shortcodes: true,
        strikethrough: true,
        table: true,
        tasklist: true
      ],
      parse: [
        relaxed_autolinks: true,
        relaxed_tasklist_matching: true
      ],
      render: [
        escape: true,
        full_info_string: true,
        github_pre_lang: true,
        unsafe: false
      ],
      sanitize: Document.default_sanitize_options(),
      streaming: streaming,
      syntax_highlight: [
        formatter: {:html_inline, theme: "onedark"}
      ]
    ]
  end
end
