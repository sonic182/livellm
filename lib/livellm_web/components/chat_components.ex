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
      class="flex flex-col w-64 h-full bg-base-200 border-r border-base-300 shrink-0"
    >
      <%!-- Brand --%>
      <div class="flex items-center gap-2.5 px-4 py-4 border-b border-base-300">
        <div class="size-7 rounded-lg bg-violet-600 flex items-center justify-center shrink-0">
          <.icon name="hero-cpu-chip" class="size-4 text-white" />
        </div>
        <span class="font-semibold text-sm tracking-tight text-base-content">LiveLLM</span>
      </div>

      <%!-- New Chat --%>
      <div class="px-3 pt-3">
        <.link
          navigate={~p"/"}
          id="new-chat-btn"
          class="flex items-center gap-2 w-full px-3 py-2 rounded-lg text-sm text-base-content/60 hover:text-base-content hover:bg-base-300 transition-colors duration-150"
        >
          <.icon name="hero-pencil-square" class="size-4 shrink-0" /> New Chat
        </.link>
      </div>

      <%!-- Chats list --%>
      <nav id="chats-nav" class="flex-1 overflow-y-auto px-3 py-2">
        <p class="px-3 py-2 text-xs font-medium text-base-content/40 uppercase tracking-wider">
          Recent
        </p>
        <%= if @chats == [] do %>
          <p class="px-3 py-2 text-xs text-base-content/30 italic">No chats yet</p>
        <% else %>
          <%= for chat <- @chats do %>
            <div id={"chat-item-#{chat.id}"} class="group relative flex items-center rounded-lg">
              <.link
                navigate={~p"/chats/#{chat.id}"}
                id={"chat-#{chat.id}"}
                class={[
                  "flex items-center gap-2 w-full px-3 py-2 pr-8 rounded-lg text-sm truncate transition-colors duration-150",
                  chat.id == @current_chat_id && "bg-base-300 text-base-content",
                  chat.id != @current_chat_id &&
                    "text-base-content/60 hover:text-base-content hover:bg-base-300"
                ]}
              >
                <.icon name="hero-chat-bubble-left-ellipsis" class="size-4 shrink-0 mt-0.5" />
                <div class="flex flex-col min-w-0">
                  <span class="truncate">{chat.title}</span>
                  <span class="text-xs text-base-content/40 group-hover:text-base-content/60">
                    {Calendar.strftime(chat.inserted_at, "%b %-d %H:%M")}
                  </span>
                </div>
              </.link>
              <button
                phx-click="delete_chat"
                phx-value-id={chat.id}
                id={"delete-chat-#{chat.id}"}
                data-confirm="Delete this chat? This cannot be undone."
                class="absolute right-1.5 p-1 rounded opacity-0 group-hover:opacity-100 text-base-content/40 hover:text-red-400 hover:bg-base-300 transition-all duration-150"
                title="Delete chat"
              >
                <.icon name="hero-trash" class="size-3.5" />
              </button>
            </div>
          <% end %>
        <% end %>
      </nav>

      <%!-- Bottom: Settings --%>
      <div class="border-t border-base-300 px-3 py-3">
        <.link
          navigate={~p"/settings"}
          id="settings-link"
          class={[
            "flex items-center gap-2 w-full px-3 py-2 rounded-lg text-sm transition-colors duration-150",
            @current_page == :settings && "bg-base-300 text-base-content",
            @current_page != :settings &&
              "text-base-content/60 hover:text-base-content hover:bg-base-300"
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
        @message.role == "user" && "bg-base-300 text-base-content"
      ]}>
        <%= if @message.role == "assistant" do %>
          <.icon name="hero-cpu-chip" class="size-4" />
        <% else %>
          <span>U</span>
        <% end %>
      </div>

      <%!-- Bubble --%>
      <div class="max-w-[72%] w-fit space-y-2">
        <%= if @message.role == "assistant" and message_reasoning_steps(@message) != [] do %>
          <details
            id={"#{@id}-reasoning"}
            class="chat-reasoning group rounded-2xl rounded-tl-sm border px-3 py-2.5 text-sm"
          >
            <summary class="flex cursor-pointer list-none items-center justify-between gap-3">
              <div class="flex min-w-0 items-center gap-2">
                <.icon name="hero-light-bulb" class="size-3.5 shrink-0 chat-reasoning-label" />
                <span class="chat-reasoning-label text-[11px] font-semibold uppercase tracking-[0.18em]">
                  Trace
                </span>
                <span class="text-xs text-base-content/45">
                  {reasoning_step_count_label(message_reasoning_steps(@message))}
                </span>
              </div>

              <div class="flex items-center gap-2">
                <%= if (@message.reasoning_tokens || 0) > 0 do %>
                  <span
                    id={"#{@id}-reasoning-tokens"}
                    class="chat-metric-badge chat-metric-badge--reasoning text-[11px]"
                  >
                    {@message.reasoning_tokens} reasoning
                  </span>
                <% end %>

                <.icon
                  name="hero-chevron-down"
                  class="size-4 text-base-content/35 transition-transform duration-200 group-open:rotate-180"
                />
              </div>
            </summary>

            <div class="mt-3">
              <.reasoning_timeline steps={message_reasoning_steps(@message)} streaming={false} />
            </div>
          </details>
        <% end %>

        <div class={[
          "rounded-2xl text-sm",
          @message.role == "assistant" &&
            "bg-base-200 text-base-content rounded-tl-sm px-4 py-3 leading-relaxed",
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

  @doc """
  Renders a reasoning timeline showing the model's thought process.
  """
  attr :steps, :list, required: true, doc: "list of reasoning steps"
  attr :streaming, :boolean, default: false, doc: "whether the timeline is still streaming"

  def reasoning_timeline(assigns) do
    ~H"""
    <div class="reasoning-timeline space-y-2">
      <%= for {step, index} <- Enum.with_index(@steps) do %>
        <div class={[
          "relative pl-5",
          index < length(@steps) - 1 && "pb-2"
        ]}>
          <%= if index < length(@steps) - 1 do %>
            <div class="absolute bottom-0 left-[0.45rem] top-5 w-px bg-base-300/80"></div>
          <% end %>

          <%= if reasoning_step_type(step) == :reasoning do %>
            <div class="rounded-xl border border-base-300 bg-base-100/55 px-3 py-2.5">
              <div class="flex min-w-0 items-center gap-2">
                <div class="absolute left-0 top-1 flex size-4 items-center justify-center rounded-full bg-base-300 text-base-content/65">
                  <.icon name="hero-light-bulb" class="size-2.5" />
                </div>
                <span class="text-[11px] font-semibold uppercase tracking-[0.18em] text-base-content/55">
                  Reasoning
                </span>
              </div>
              <div class="mt-2 whitespace-pre-wrap pl-0 text-sm leading-relaxed text-base-content/80">
                <%= if reasoning_step_content(step) not in [nil, ""] do %>
                  {reasoning_step_content(step)}
                <% else %>
                  <span class="italic text-base-content/45">Working...</span>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if reasoning_step_type(step) == :tool_call do %>
            <div class={[
              "rounded-xl border px-3 py-2.5",
              reasoning_step_status(step) == :running &&
                "border-emerald-500/20 bg-emerald-500/10 text-emerald-200",
              reasoning_step_status(step) == :completed &&
                "border-base-300 bg-base-100/55 text-base-content"
            ]}>
              <div class="flex items-center gap-2.5">
                <div class={[
                  "absolute left-0 top-1 flex size-4 items-center justify-center rounded-full",
                  reasoning_step_status(step) == :running && "bg-emerald-500/20 text-emerald-300",
                  reasoning_step_status(step) == :completed && "bg-base-300 text-base-content/65"
                ]}>
                  <%= if reasoning_step_status(step) == :running do %>
                    <span class="size-2.5 rounded-full border border-current border-t-transparent animate-spin">
                    </span>
                  <% else %>
                    <.icon name="hero-wrench-screwdriver" class="size-2.5" />
                  <% end %>
                </div>

                <div class={[
                  "text-[11px] font-semibold uppercase tracking-[0.18em]",
                  reasoning_step_status(step) == :running && "text-emerald-300/85",
                  reasoning_step_status(step) == :completed && "text-base-content/50"
                ]}>
                  {if reasoning_step_status(step) == :running, do: "Calling", else: "Used tool"}
                </div>
                <div class="min-w-0 flex-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <code class="rounded-md bg-black/10 px-2 py-1 font-mono text-xs text-current dark:bg-white/5">
                      {reasoning_step_tool_name(step)}
                    </code>
                    <%= if reasoning_step_status(step) == :completed do %>
                      <span class="text-xs text-base-content/45">done</span>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
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
        formatter:
          {:html_multi_themes,
           themes: [light: "github_light", dark: "github_dark"], default_theme: "light-dark()"}
      ]
    ]
  end

  defp message_reasoning_steps(message) do
    case Map.get(message, :reasoning_steps) do
      [_ | _] = steps -> steps
      _ -> build_fallback_reasoning_steps(message)
    end
  end

  defp build_fallback_reasoning_steps(message) do
    []
    |> maybe_add_fallback_reasoning(Map.get(message, :reasoning))
    |> maybe_add_fallback_tool_calls(Map.get(message, :tool_calls))
  end

  defp maybe_add_fallback_reasoning(steps, reasoning) when reasoning in [nil, ""], do: steps

  defp maybe_add_fallback_reasoning(steps, reasoning),
    do: steps ++ [%{"type" => "reasoning", "content" => reasoning}]

  defp maybe_add_fallback_tool_calls(steps, tool_calls) when tool_calls in [nil, []], do: steps

  defp maybe_add_fallback_tool_calls(steps, tool_calls) do
    steps ++
      Enum.map(tool_calls, fn tool_call ->
        %{
          "type" => "tool_call",
          "tool_name" => Map.get(tool_call, "name") || Map.get(tool_call, :name),
          "status" => "completed"
        }
      end)
  end

  defp reasoning_step_count_label(steps) do
    count = length(steps)
    if count == 1, do: "1 step", else: "#{count} steps"
  end

  defp reasoning_step_type(%{type: type}) when type in [:reasoning, :tool_call], do: type
  defp reasoning_step_type(%{"type" => "reasoning"}), do: :reasoning
  defp reasoning_step_type(%{"type" => "tool_call"}), do: :tool_call

  defp reasoning_step_content(%{content: content}), do: content
  defp reasoning_step_content(%{"content" => content}), do: content
  defp reasoning_step_content(_step), do: nil

  defp reasoning_step_status(%{status: status}) when status in [:running, :completed], do: status
  defp reasoning_step_status(%{"status" => "running"}), do: :running
  defp reasoning_step_status(%{"status" => "completed"}), do: :completed
  defp reasoning_step_status(_step), do: nil

  defp reasoning_step_tool_name(%{tool_name: tool_name}), do: tool_name
  defp reasoning_step_tool_name(%{"tool_name" => tool_name}), do: tool_name
  defp reasoning_step_tool_name(_step), do: nil
end
