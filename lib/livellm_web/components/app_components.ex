defmodule LivellmWeb.AppComponents do
  @moduledoc """
  Application-level UI components built on top of the generated core components.
  """

  use Phoenix.Component
  use Gettext, backend: LivellmWeb.Gettext

  alias Phoenix.HTML.Form

  import LivellmWeb.CoreComponents

  attr :id, :string, default: nil
  attr :name, :string, default: nil
  attr :label, :string, default: nil
  attr :hint, :string, default: nil
  attr :value, :any, default: nil
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :errors, :list, default: []
  attr :density, :atom, values: [:default, :compact], default: :default
  attr :class, :any, default: nil
  attr :input_class, :any, default: nil

  attr :type, :string,
    default: "text",
    values: ~w(color date datetime-local email month number password search tel text url week)

  attr :rest, :global,
    include: ~w(autocomplete disabled form inputmode list max maxlength min minlength pattern
         phx-debounce placeholder readonly required step)

  def text_input(assigns) do
    assigns =
      assigns
      |> normalize_field_assigns()
      |> assign(:input_value, Form.normalize_value(assigns.type, assigns.value))

    ~H"""
    <.field_shell
      id={@id}
      label={@label}
      hint={@hint}
      errors={@errors}
      density={@density}
      class={@class}
    >
      <input
        type={@type}
        id={@id}
        name={@name}
        value={@input_value}
        class={field_input_classes(@density, @errors, @input_class)}
        {@rest}
      />
    </.field_shell>
    """
  end

  attr :id, :string, default: nil
  attr :name, :string, default: nil
  attr :label, :string, default: nil
  attr :hint, :string, default: nil
  attr :value, :any, default: nil
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :errors, :list, default: []
  attr :density, :atom, values: [:default, :compact], default: :default
  attr :class, :any, default: nil
  attr :input_class, :any, default: nil

  attr :options, :list, required: true
  attr :prompt, :string, default: nil
  attr :multiple, :boolean, default: false

  attr :rest, :global, include: ~w(disabled form required)

  def select_input(assigns) do
    assigns = normalize_field_assigns(assigns)

    ~H"""
    <.field_shell
      id={@id}
      label={@label}
      hint={@hint}
      errors={@errors}
      density={@density}
      class={@class}
    >
      <select
        id={@id}
        name={@name}
        class={field_input_classes(@density, @errors, @input_class)}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
    </.field_shell>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, default: nil
  attr :label, :string, default: nil
  attr :hint, :string, default: nil
  attr :value, :any, default: nil
  attr :density, :atom, values: [:default, :compact], default: :default
  attr :class, :any, default: nil
  attr :input_class, :any, default: nil

  attr :options, :list, required: true
  attr :open, :boolean, default: false
  attr :loading, :boolean, default: false
  attr :highlight, :integer, default: 0
  attr :empty_message, :string, default: "No matches"

  attr :on_open, :string, required: true
  attr :on_close, :string, required: true
  attr :on_select, :string, required: true
  attr :on_key, :string, required: true

  attr :rest, :global, include: ~w(disabled form phx-debounce placeholder readonly required)

  @doc """
  Text input that doubles as a filterable option list: focusing it opens the list,
  typing filters it (the parent owns the filtering), clicking an option selects it.

  Arrow up/down move `highlight`, Enter picks the highlighted option and Escape closes —
  the keys are pushed to `on_key` as `%{"key" => key}`; the parent owns that state too.
  """
  def combobox_input(assigns) do
    ~H"""
    <div
      id={"#{@id}-combobox"}
      class={["relative", @class]}
      phx-hook=".ComboboxKeys"
      data-key-event={@on_key}
      phx-click-away={@on_close}
    >
      <.field_shell id={@id} label={@label} hint={@hint} density={@density}>
        <input
          type="text"
          id={@id}
          name={@name}
          value={@value}
          role="combobox"
          autocomplete="off"
          aria-expanded={to_string(@open)}
          aria-controls={"#{@id}-options"}
          phx-focus={@on_open}
          class={field_input_classes(@density, [], @input_class)}
          {@rest}
        />
      </.field_shell>

      <div
        :if={@open}
        id={"#{@id}-options"}
        role="listbox"
        class="absolute right-0 z-30 mt-1 max-h-72 w-72 max-w-[80vw] overflow-y-auto rounded-xl border border-base-300 bg-base-100 py-1 shadow-2xl shadow-black/20"
      >
        <p :if={@loading} class="px-3 py-2 text-xs text-base-content/50">Loading models…</p>
        <p
          :if={not @loading and @options == []}
          id={"#{@id}-empty"}
          class="px-3 py-2 text-xs text-base-content/50"
        >
          {@empty_message}
        </p>
        <button
          :for={{option, index} <- Enum.with_index(@options)}
          type="button"
          role="option"
          aria-selected={to_string(index == @highlight)}
          data-option={option}
          data-highlighted={index == @highlight}
          phx-click={@on_select}
          phx-value-option={option}
          class={[
            "block w-full truncate px-3 py-1.5 text-left text-xs",
            index == @highlight && "bg-base-200 text-base-content",
            index != @highlight && "text-base-content/70 hover:bg-base-200/60",
            option == @value && "font-semibold"
          ]}
        >
          {option}
        </button>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ComboboxKeys">
        const KEYS = ["ArrowDown", "ArrowUp", "Enter", "Escape"]

        export default {
          mounted() {
            this.el.addEventListener("keydown", (event) => {
              if (!KEYS.includes(event.key)) return
              event.preventDefault()

              // Keep the input in sync ourselves: LiveView will not patch the value of the
              // input the user is focused on, and Enter never blurs it.
              const highlighted = this.el.querySelector("[data-highlighted]")
              if (event.key === "Enter" && highlighted) {
                this.el.querySelector("input").value = highlighted.dataset.option
              }

              this.pushEvent(this.el.dataset.keyEvent, {key: event.key})
            })
          },
          updated() {
            this.el
              .querySelector("[data-highlighted]")
              ?.scrollIntoView({block: "nearest"})
          }
        }
      </script>
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :name, :string, default: nil
  attr :label, :string, default: nil
  attr :hint, :string, default: nil
  attr :value, :any, default: nil
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :errors, :list, default: []
  attr :density, :atom, values: [:default, :compact], default: :default
  attr :class, :any, default: nil
  attr :input_class, :any, default: nil

  attr :rest, :global,
    include:
      ~w(cols disabled form maxlength minlength phx-hook placeholder readonly required rows)

  def textarea_input(assigns) do
    assigns =
      assigns
      |> normalize_field_assigns()
      |> assign(:input_value, Form.normalize_value("textarea", assigns.value))

    ~H"""
    <.field_shell
      id={@id}
      label={@label}
      hint={@hint}
      errors={@errors}
      density={@density}
      class={@class}
    >
      <textarea
        id={@id}
        name={@name}
        class={field_textarea_classes(@density, @errors, @input_class)}
        {@rest}
      >{@input_value}</textarea>
    </.field_shell>
    """
  end

  attr :id, :string, default: nil
  attr :name, :string, default: nil
  attr :label, :string, required: true
  attr :hint, :string, default: nil
  attr :value, :any, default: nil
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :errors, :list, default: []
  attr :checked, :boolean, default: false
  attr :density, :atom, values: [:default, :compact], default: :default
  attr :class, :any, default: nil
  attr :input_class, :any, default: nil

  attr :rest, :global, include: ~w(disabled form phx-click required)

  def checkbox_input(assigns) do
    assigns =
      assigns
      |> normalize_field_assigns()
      |> assign_new(:checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class={["ui-checkbox-field", @class]}>
      <label for={@id} class="ui-checkbox-label">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={checkbox_classes(@density, @errors, @input_class)}
          {@rest}
        />
        <span class="ui-checkbox-copy">
          <span class="ui-label">{@label}</span>
          <span :if={@hint} class="ui-hint">{@hint}</span>
        </span>
      </label>
      <.field_errors errors={@errors} />
    </div>
    """
  end

  attr :id, :string, default: "theme-selector"
  attr :class, :any, default: nil
  attr :size, :atom, values: [:default, :compact], default: :default

  def theme_selector(assigns) do
    ~H"""
    <div
      id={@id}
      data-theme-picker
      phx-hook="ThemePicker"
      class={["ui-segmented-control", theme_selector_classes(@size), @class]}
    >
      <button type="button" data-phx-theme="system" data-theme-option class="ui-segment">
        <.icon name="hero-computer-desktop" class="size-4" />
        <span>Auto</span>
      </button>
      <button type="button" data-phx-theme="light" data-theme-option class="ui-segment">
        <.icon name="hero-sun" class="size-4" />
        <span>Light</span>
      </button>
      <button type="button" data-phx-theme="dark" data-theme-option class="ui-segment">
        <.icon name="hero-moon" class="size-4" />
        <span>Dark</span>
      </button>
    </div>
    """
  end

  attr :tone, :atom, values: [:neutral, :success, :warning, :accent], default: :neutral
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={["ui-status-badge", badge_tone_class(@tone), @class]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :id, :string, default: nil
  attr :class, :any, default: nil
  attr :tone, :atom, values: [:default, :subtle], default: :default
  attr :rest, :global
  slot :inner_block, required: true

  def surface(assigns) do
    ~H"""
    <div id={@id} class={["ui-surface", surface_tone_class(@tone), @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :label, :string, default: nil
  attr :hint, :string, default: nil
  attr :errors, :list, default: []
  attr :density, :atom, values: [:default, :compact], default: :default
  attr :class, :any, default: nil
  slot :inner_block, required: true

  defp field_shell(assigns) do
    ~H"""
    <div class={["ui-field-shell", shell_density_class(@density), @class]}>
      <label :if={@label} for={@id} class="ui-label">
        {@label}
      </label>
      {render_slot(@inner_block)}
      <p :if={@hint && @errors == []} class="ui-hint">
        {@hint}
      </p>
      <.field_errors errors={@errors} />
    </div>
    """
  end

  attr :errors, :list, default: []

  defp field_errors(assigns) do
    ~H"""
    <p :for={msg <- @errors} class="ui-error">
      <.icon name="hero-exclamation-circle" class="size-4 shrink-0" />
      <span>{msg}</span>
    </p>
    """
  end

  defp normalize_field_assigns(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors =
      if Phoenix.Component.used_input?(field) do
        Enum.map(field.errors, &LivellmWeb.CoreComponents.translate_error/1)
      else
        []
      end

    assigns
    |> assign(:id, assigns.id || field.id)
    |> assign(:name, assigns.name || field.name)
    |> assign(:value, if(is_nil(assigns.value), do: field.value, else: assigns.value))
    |> assign(:errors, errors)
  end

  defp normalize_field_assigns(assigns), do: assigns

  defp field_input_classes(density, errors, input_class) do
    [
      "ui-field",
      density == :compact && "ui-field-compact",
      errors != [] && "ui-field-error",
      input_class
    ]
  end

  defp field_textarea_classes(density, errors, input_class) do
    [
      "ui-field ui-textarea",
      density == :compact && "ui-field-compact",
      errors != [] && "ui-field-error",
      input_class
    ]
  end

  defp checkbox_classes(density, errors, input_class) do
    [
      "ui-checkbox",
      density == :compact && "ui-checkbox-compact",
      errors != [] && "ui-checkbox-error",
      input_class
    ]
  end

  defp shell_density_class(:default), do: "ui-field-shell-default"
  defp shell_density_class(:compact), do: "ui-field-shell-compact"

  defp theme_selector_classes(:default), do: "ui-segmented-default"
  defp theme_selector_classes(:compact), do: "ui-segmented-compact"

  defp surface_tone_class(:default), do: "ui-surface-default"
  defp surface_tone_class(:subtle), do: "ui-surface-subtle"

  defp badge_tone_class(:neutral), do: "ui-status-badge-neutral"
  defp badge_tone_class(:success), do: "ui-status-badge-success"
  defp badge_tone_class(:warning), do: "ui-status-badge-warning"
  defp badge_tone_class(:accent), do: "ui-status-badge-accent"
end
