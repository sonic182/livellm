This is a web application written using the Phoenix web framework.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use `:req` (`Req`) for HTTP requests — **avoid** `:httpoison`, `:tesla`, and `:httpc`

## Phoenix v1.8

- **Always** begin LiveView templates with `<Layouts.app flash={@flash} ...>` wrapping all inner content
- `MyAppWeb.Layouts` is aliased in `my_app_web.ex` — no need to alias it again
- No `current_scope` assign = wrong `live_session` or missing `current_scope` passed to `<Layouts.app>`
- `<.flash_group>` is **forbidden** outside `layouts.ex`
- **Always** use `<.icon name="hero-...">` for icons, never `Heroicons` modules
- **Always** use the imported `<.input>` component; overriding `class=` loses all defaults so you must fully restyle

## JS and CSS

- Tailwind v4 uses this import syntax in `app.css` — always maintain it:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- **Never** use `@apply` in raw CSS; **never** use daisyUI; **never** write inline `<script>` tags in templates
- Only `app.js` and `app.css` bundles are supported — import vendor deps into those files

## Elixir

- Elixir lists **do not support index access** — never do `mylist[i]`, always use `Enum.at/2` or pattern matching
- Variables **cannot be rebound inside** `if`/`case`/`cond` blocks — bind the result of the expression:

      # INVALID
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file (cyclic deps)
- **Never** use map access syntax on structs (`changeset[:field]` fails) — use `my_struct.field` or `Ecto.Changeset.get_field/2`
- Don't use `String.to_atom/1` on user input (memory leak)
- Predicate names must end in `?`, not start with `is_`
- OTP primitives require a `name:` in child spec: `{DynamicSupervisor, name: MyApp.MyDyn}`
- Use `Task.async_stream(collection, callback, timeout: :infinity)` for concurrent enumeration

## Mix / Tests

- Prefer `mix test test/my_test.exs` or `mix test --failed` to debug failures
- **Always** use `start_supervised!/1` in tests for process cleanup
- **Never** use `Process.sleep/1` — use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

- To synchronize before the next call, use `_ = :sys.get_state(pid)` instead of sleeping

## Phoenix

- `scope` aliases are prefixed automatically — never add your own `alias` for routes:

      scope "/admin", AppWeb.Admin do
        live "/users", UserLive, :index   # resolves to AppWeb.Admin.UserLive
      end

- `Phoenix.View` is not included in Phoenix — don't use it

## Ecto

- **Always** preload associations in queries when accessed in templates
- `Ecto.Schema` fields always use `:string` type, even for text columns
- `validate_number/2` has no `:allow_nil` option — it's not needed
- **Always** use `Ecto.Changeset.get_field(changeset, :field)` to read changeset fields
- Programmatic fields like `user_id` must not be in `cast` — set them explicitly
- **Always** run `mix ecto.gen.migration name_with_underscores` to generate migrations

## Phoenix HTML / HEEx

- Templates always use `~H` or `.html.heex`, never `~E`
- **Always** use `Phoenix.Component.form/1` and `to_form/2` — never `Phoenix.HTML.form_for`
- **Always** assign `form: to_form(...)` in the LiveView, then use `@form[:field]` in the template
- Add unique DOM IDs to forms and key elements
- Elixir has no `else if` / `elsif` — **always** use `cond` or `case`:

      <%!-- INVALID --%>
      <%= if condition do %>...<% else if other %><% end %>

      <%!-- VALID --%>
      <%= cond do %>
        <% condition -> %> ...
        <% other -> %> ...
        <% true -> %> ...
      <% end %>

- Use `phx-no-curly-interpolation` on tags containing literal `{` or `}`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

- HEEx class attrs **must** use list syntax for multiple/conditional classes:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@cond, do: "border-red-500", else: "border-blue-100"),
      ]}>

- **Never** use `<% Enum.each %>` for template content — always use `<%= for item <- @col do %>`
- **Always** use `{...}` for attr interpolation and value interpolation in tag bodies; use `<%= %>` for block constructs (`if`, `cond`, `case`, `for`) in tag bodies. **Never** use `<%= %>` inside tag attributes:

      <%!-- VALID --%>
      <div id={@id}>
        {@value}
        <%= if @flag do %>{@other}<% end %>
      </div>

      <%!-- INVALID — syntax error --%>
      <div id="<%= @id %>">
        {if @flag do}{end}
      </div>

## Phoenix LiveView

- **Never** use deprecated `live_redirect`/`live_patch` — use `<.link navigate={}>`, `<.link patch={}>`, `push_navigate`, `push_patch`
- LiveViews are named `AppWeb.FooLive`; the default `:browser` scope is already aliased so just `live "/foo", FooLive`

### Streams

- **Always** use LiveView streams for collections (not regular list assigns):

      stream(socket, :messages, [new_msg])                        # append
      stream(socket, :messages, [new_msg], reset: true)           # reset
      stream(socket, :messages, [new_msg], at: -1)                # prepend
      stream_delete(socket, :messages, msg)                       # delete

- Stream template requires `phx-update="stream"` on parent and stream id on each child:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>{msg.text}</div>
      </div>

- Streams are **not enumerable** — to filter, refetch and reset:

      messages = list_messages(filter)
      socket |> stream(:messages, messages, reset: true)

- Streams have no count/empty state — track count with a separate assign; use `hidden only:block` for empty UI
- When an assign affects content inside streamed items, **re-stream those items** alongside the assign change
- **Never** use deprecated `phx-update="append"` or `phx-update="prepend"`

### JS Hooks

- When a hook manages its own DOM, also set `phx-update="ignore"`
- Always provide a unique DOM id alongside `phx-hook`
- **Never** write raw `<script>` in HEEx — always use colocated hooks with `:type={Phoenix.LiveView.ColocatedHook}`. Names **must** start with `.`:

      <input id="phone" phx-hook=".PhoneNumber" />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
        export default {
          mounted() {
            this.el.addEventListener("input", e => { /* ... */ })
          }
        }
      </script>

- External hooks go in `assets/js/` and are passed to `LiveSocket`:

      let liveSocket = new LiveSocket("/live", Socket, { hooks: { MyHook } })

- **Always** rebind the socket on `push_event/3`:

      socket = push_event(socket, "my_event", %{key: val})

### LiveView Tests

- Use `Phoenix.LiveViewTest` with `element/2`, `has_element/2` — **never** assert on raw HTML strings
- Drive form tests with `render_submit/2` and `render_change/2`
- Reference the DOM IDs you added in templates for selectors

### Forms

Create a form from params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

Create from a changeset (`:as` is auto-computed from the schema):

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

In the template — **always** use `@form`, never pass the changeset directly:

    <%!-- VALID --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

    <%!-- INVALID — causes errors --%>
    <.form for={@changeset}>
      <.input field={@changeset[:field]} />
    </.form>
