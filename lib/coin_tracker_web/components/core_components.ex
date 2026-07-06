defmodule CoinTrackerWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: CoinTrackerWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 w-80 sm:w-96 max-w-80 sm:max-w-96 p-4 rounded-lg shadow-lg border text-wrap",
        @kind == :info &&
          "bg-blue-50 border-blue-200 text-blue-800 dark:bg-blue-900/30 dark:border-blue-800 dark:text-blue-200",
        @kind == :error &&
          "bg-red-50 border-red-200 text-red-800 dark:bg-red-900/30 dark:border-red-800 dark:text-red-200"
      ]}>
        <.icon
          :if={@kind == :info}
          name="hero-information-circle"
          class="size-5 shrink-0 text-blue-600 dark:text-blue-400"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle"
          class="size-5 shrink-0 text-red-600 dark:text-red-400"
        />
        <div class="flex-1 min-w-0">
          <p :if={@title} class="font-semibold">{@title}</p>
          <p class="text-sm">{msg}</p>
        </div>
        <button type="button" class="group shrink-0 cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-50 group-hover:opacity-100" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" =>
        "bg-blue-600 text-white hover:bg-blue-700 dark:bg-blue-500 dark:hover:bg-blue-600 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600",
      nil =>
        "bg-zinc-900 text-white hover:bg-zinc-700 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-zinc-600"
    }

    # Build base classes from variant
    base_classes = [
      "inline-flex items-center justify-center gap-2 rounded-lg px-4 py-2.5 text-sm font-semibold transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed",
      Map.fetch!(variants, assigns[:variant])
    ]

    # Merge with any custom classes provided by the user
    assigns =
      assign(assigns, :class, [
        base_classes,
        assigns[:class]
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :description, :string, default: nil, doc: "help text displayed below the input"

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="flex gap-3">
      <div class="flex h-6 shrink-0 items-center">
        <div class="group grid size-4 grid-cols-1">
          <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={
              @class ||
                "col-start-1 row-start-1 appearance-none rounded border border-zinc-950/20 bg-white checked:border-blue-600 checked:bg-blue-600 indeterminate:border-blue-600 indeterminate:bg-blue-600 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600 disabled:border-zinc-300 disabled:bg-zinc-100 disabled:checked:bg-zinc-100 dark:border-white/20 dark:bg-white/5 dark:checked:border-blue-500 dark:checked:bg-blue-500 dark:indeterminate:border-blue-500 dark:indeterminate:bg-blue-500 dark:focus-visible:outline-blue-500 dark:disabled:border-white/10 dark:disabled:bg-white/10 dark:disabled:checked:bg-white/10 forced-colors:appearance-auto"
            }
            {@rest}
          />
          <svg
            viewBox="0 0 14 14"
            fill="none"
            class="pointer-events-none col-start-1 row-start-1 size-3.5 self-center justify-self-center stroke-white group-has-disabled:stroke-zinc-950/25 dark:group-has-disabled:stroke-white/25"
          >
            <path
              d="M3 8L6 11L11 3.5"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="opacity-0 group-has-checked:opacity-100"
            />
          </svg>
        </div>
      </div>
      <div class="text-sm/6">
        <label for={@id} class="font-medium text-zinc-950 dark:text-white">{@label}</label>
        <p :if={@description} class="text-zinc-500">{@description}</p>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <label for={@id} class="block text-sm/6 font-medium text-zinc-950 dark:text-white">
        {@label}
      </label>
      <div class="mt-2 grid grid-cols-1">
        <select
          id={@id}
          name={@name}
          class={
            @class ||
              [
                "col-start-1 row-start-1 w-full appearance-none rounded-lg bg-white py-2 pr-8 pl-3 text-base text-zinc-950 border border-zinc-950/10 focus:outline-2 focus:-outline-offset-2 focus:outline-blue-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:border-white/10 dark:*:bg-zinc-800 dark:focus:outline-blue-500",
                @errors != [] && "border-red-600 dark:border-red-500"
              ]
          }
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
        <svg
          viewBox="0 0 16 16"
          fill="currentColor"
          data-slot="icon"
          aria-hidden="true"
          class="pointer-events-none col-start-1 row-start-1 mr-2 size-5 self-center justify-self-end text-zinc-500 sm:size-4"
        >
          <path
            d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
            clip-rule="evenodd"
            fill-rule="evenodd"
          />
        </svg>
      </div>
      <p :if={@description} class="mt-3 text-sm/6 text-zinc-500">{@description}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <label for={@id} class="block text-sm/6 font-medium text-zinc-950 dark:text-white">
        {@label}
      </label>
      <div class="mt-2">
        <textarea
          id={@id}
          name={@name}
          class={
            @class ||
              [
                "block w-full rounded-lg bg-white px-3 py-2 text-base text-zinc-950 border border-zinc-950/10 placeholder:text-zinc-400 focus:outline-2 focus:-outline-offset-2 focus:outline-blue-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:border-white/10 dark:placeholder:text-zinc-500 dark:focus:outline-blue-500",
                @errors != [] && "border-red-600 dark:border-red-500"
              ]
          }
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </div>
      <p :if={@description} class="mt-3 text-sm/6 text-zinc-500">{@description}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div>
      <label for={@id} class="block text-sm/6 font-medium text-zinc-950 dark:text-white">
        {@label}
      </label>
      <div class="mt-2">
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={
            @class ||
              [
                "block w-full rounded-lg bg-white px-3 py-2 text-base text-zinc-950 border border-zinc-950/10 placeholder:text-zinc-400 focus:outline-2 focus:-outline-offset-2 focus:outline-blue-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:border-white/10 dark:placeholder:text-zinc-500 dark:focus:outline-blue-500",
                @errors != [] && "border-red-600 dark:border-red-500"
              ]
          }
          {@rest}
        />
      </div>
      <p :if={@description} class="mt-3 text-sm/6 text-zinc-500">{@description}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-2 flex gap-2 items-center text-sm text-red-600 dark:text-red-400">
      <.icon name="hero-exclamation-circle" class="size-4" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-6"]}>
      <div>
        <h1 class="text-lg font-semibold text-zinc-950 dark:text-white">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-1 text-sm text-zinc-500">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-hidden rounded-lg border border-zinc-950/10 dark:border-white/10">
      <table class="min-w-full divide-y divide-zinc-950/10 dark:divide-white/10">
        <thead class="bg-zinc-50 dark:bg-zinc-900">
          <tr>
            <th
              :for={col <- @col}
              class="px-4 py-3 text-left text-xs font-semibold text-zinc-500 uppercase tracking-wider"
            >
              {col[:label]}
            </th>
            <th :if={@action != []} class="px-4 py-3 text-right">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
          class="bg-white dark:bg-zinc-900 divide-y divide-zinc-950/5 dark:divide-white/5"
        >
          <tr
            :for={row <- @rows}
            id={@row_id && @row_id.(row)}
            class="hover:bg-zinc-50 dark:hover:bg-zinc-800/50 transition-colors"
          >
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={[
                "px-4 py-4 text-sm text-zinc-950 dark:text-white",
                @row_click && "hover:cursor-pointer"
              ]}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="px-4 py-4 text-right text-sm font-medium">
              <div class="flex justify-end gap-3">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="divide-y divide-zinc-950/5 dark:divide-white/5">
      <li :for={item <- @item} class="py-4 first:pt-0 last:pb-0">
        <div>
          <dt class="text-sm font-medium text-zinc-500">{item.title}</dt>
          <dd class="mt-1 text-sm text-zinc-950 dark:text-white">{render_slot(item)}</dd>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders an inline SVG sparkline for a series of integer ranks (1 = top).

  The Y axis is inverted: rank 1 is drawn at the top and the maximum rank
  (typically 10) at the bottom, so an upward-trending line reads as
  "rank improving."

  Returns an empty span when fewer than 2 points are provided so the layout
  doesn't shift while the series is still warming up.

  ## Examples

      <.sparkline points={[7, 5, 4, 3, 2]} />
      <.sparkline points={[3, 4, 6, 9]} class="text-red-500" />
  """
  attr :points, :list, required: true
  attr :class, :string, default: "text-zinc-400 dark:text-zinc-500"
  attr :width, :integer, default: 80
  attr :height, :integer, default: 20
  attr :max_rank, :integer, default: 10
  attr :rest, :global

  def sparkline(assigns) do
    points = assigns.points || []

    if length(points) < 2 do
      ~H"""
      <span data-role="sparkline-empty" class="inline-block" style={"width: #{@width}px"}></span>
      """
    else
      assigns = assign(assigns, :polyline_points, build_polyline(points, assigns))

      ~H"""
      <svg
        viewBox={"0 0 #{@width} #{@height}"}
        width={@width}
        height={@height}
        class={["inline-block align-middle", @class]}
        preserveAspectRatio="none"
        aria-hidden="true"
        data-role="sparkline"
        {@rest}
      >
        <polyline
          fill="none"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          points={@polyline_points}
        />
      </svg>
      """
    end
  end

  defp build_polyline(points, %{width: width, height: height, max_rank: max_rank}) do
    n = length(points)
    step = if n > 1, do: width / (n - 1), else: 0

    points
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {rank, idx} ->
      x = idx * step
      # Invert: rank 1 at the top, max_rank at the bottom.
      clamped = max(1, min(rank, max_rank))
      y = (clamped - 1) / max(max_rank - 1, 1) * height
      "#{Float.round(x, 2)},#{Float.round(y, 2)}"
    end)
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(CoinTrackerWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(CoinTrackerWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
