defmodule CoinTrackerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CoinTrackerWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title} current_path={@current_path}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :page_title, :string, default: nil, doc: "the page title for the header"

  attr :current_path, :string, default: "/", doc: "the current path for navigation active state"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col">
      <nav class="bg-white dark:bg-zinc-900 border-b border-zinc-950/10 dark:border-white/10">
        <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div class="flex h-16 items-center justify-between">
            <div class="flex items-center">
              <div class="shrink-0">
                <.link
                  navigate={if(@current_scope, do: ~p"/signals", else: ~p"/")}
                  class="flex items-center gap-2"
                >
                  <span class="text-2xl" aria-label={app_name()}>🦉</span>
                  <span class="hidden sm:block text-lg font-semibold text-zinc-950 dark:text-white">
                    {app_name()}
                  </span>
                </.link>
              </div>
              <div class="hidden md:block">
                <div class="ml-10 flex items-baseline space-x-1">
                  <%= if @current_scope do %>
                    <.link
                      navigate={~p"/positions"}
                      class={nav_link_class(@current_path, "/positions")}
                    >
                      {gettext("Positions")}
                    </.link>
                    <.link
                      navigate={~p"/signals"}
                      class={nav_link_class(@current_path, "/signals")}
                    >
                      {gettext("Signals")}
                    </.link>
                    <.link
                      navigate={~p"/market-status"}
                      class={nav_link_class(@current_path, "/market-status")}
                    >
                      {gettext("Market Status")}
                    </.link>
                  <% end %>
                  <.link
                    navigate={~p"/historical"}
                    class={nav_link_class(@current_path, "/historical")}
                  >
                    {gettext("Historical")}
                  </.link>
                  <%= if @current_scope do %>
                    <.link
                      navigate={~p"/tutorial"}
                      class={nav_link_class(@current_path, "/tutorial")}
                    >
                      {gettext("Tutorial")}
                    </.link>
                    <.link
                      navigate={~p"/users/settings"}
                      class={nav_link_class(@current_path, "/users/settings")}
                    >
                      {gettext("Settings")}
                    </.link>
                    <%= if CoinTracker.Accounts.User.admin?(@current_scope.user) do %>
                      <.link
                        navigate={~p"/admin"}
                        class={nav_link_class(@current_path, "/admin")}
                      >
                        {gettext("Admin")}
                      </.link>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>

            <%= if @current_scope do %>
              <div class="hidden md:block">
                <div class="ml-4 flex items-center md:ml-6">
                  <div class="relative ml-3">
                    <button
                      phx-click={JS.toggle(to: "#user-menu")}
                      class="relative flex max-w-xs cursor-pointer items-center rounded-full text-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-500"
                    >
                      <span class="sr-only">{gettext("Open user menu")}</span>
                      <div class="size-8 rounded-full bg-blue-600 dark:bg-blue-500 flex items-center justify-center text-white font-semibold text-sm">
                        {String.first(@current_scope.user.email) |> String.upcase()}
                      </div>
                    </button>
                    <div
                      id="user-menu"
                      phx-click-away={JS.hide(to: "#user-menu")}
                      class="hidden absolute right-0 z-10 mt-2 w-56 origin-top-right rounded-lg bg-white dark:bg-zinc-900 shadow-lg ring-1 ring-zinc-950/10 dark:ring-white/10"
                    >
                      <div class="px-4 py-3 border-b border-zinc-950/10 dark:border-white/10">
                        <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          {gettext("Signed in as")}
                        </p>
                        <p class="mt-1 text-sm font-medium text-zinc-950 dark:text-white truncate">
                          {@current_scope.user.email}
                        </p>
                      </div>
                      <div class="py-1">
                        <%= if CoinTracker.Accounts.User.admin?(@current_scope.user) do %>
                          <.link
                            navigate={~p"/admin"}
                            class="block px-4 py-2 text-sm text-zinc-700 dark:text-zinc-300 hover:bg-zinc-50 dark:hover:bg-zinc-800"
                          >
                            {gettext("Admin Panel")}
                          </.link>
                        <% end %>
                        <.link
                          navigate={~p"/users/settings"}
                          class="block px-4 py-2 text-sm text-zinc-700 dark:text-zinc-300 hover:bg-zinc-50 dark:hover:bg-zinc-800"
                        >
                          {gettext("Settings")}
                        </.link>
                        <.link
                          href={~p"/users/log-out"}
                          method="delete"
                          class="block px-4 py-2 text-sm text-zinc-700 dark:text-zinc-300 hover:bg-zinc-50 dark:hover:bg-zinc-800"
                        >
                          {gettext("Sign out")}
                        </.link>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            <% else %>
              <div class="hidden md:flex items-center gap-4">
                <.link
                  navigate={~p"/users/log-in"}
                  class="text-sm font-medium text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-white transition-colors"
                >
                  {gettext("Log in")}
                </.link>
                <.link
                  navigate={~p"/users/register"}
                  class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-700 transition-colors"
                >
                  {gettext("Get Started")}
                </.link>
              </div>
            <% end %>

            <div class="-mr-2 flex md:hidden">
              <button
                type="button"
                phx-click={JS.toggle(to: "#mobile-menu")}
                class="relative inline-flex items-center justify-center rounded-lg p-2 text-zinc-500 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800 hover:text-zinc-700 dark:hover:text-zinc-200 focus:outline-2 focus:outline-offset-2 focus:outline-blue-500"
              >
                <span class="sr-only">{gettext("Open main menu")}</span>
                <.icon name="hero-bars-3" class="size-6" />
              </button>
            </div>
          </div>
        </div>

        <div
          id="mobile-menu"
          phx-click-away={JS.hide(to: "#mobile-menu")}
          class="hidden md:hidden border-t border-zinc-950/10 dark:border-white/10"
        >
          <div class="space-y-1 px-3 py-3">
            <%= if @current_scope do %>
              <.link
                navigate={~p"/positions"}
                class={mobile_nav_link_class(@current_path, "/positions")}
              >
                {gettext("Positions")}
              </.link>
              <.link
                navigate={~p"/signals"}
                class={mobile_nav_link_class(@current_path, "/signals")}
              >
                {gettext("Signals")}
              </.link>
              <.link
                navigate={~p"/market-status"}
                class={mobile_nav_link_class(@current_path, "/market-status")}
              >
                {gettext("Market Status")}
              </.link>
            <% end %>
            <.link
              navigate={~p"/historical"}
              class={mobile_nav_link_class(@current_path, "/historical")}
            >
              {gettext("Historical")}
            </.link>
            <%= if @current_scope do %>
              <.link
                navigate={~p"/tutorial"}
                class={mobile_nav_link_class(@current_path, "/tutorial")}
              >
                {gettext("Tutorial")}
              </.link>
              <.link
                navigate={~p"/users/settings"}
                class={mobile_nav_link_class(@current_path, "/users/settings")}
              >
                {gettext("Settings")}
              </.link>
              <%= if CoinTracker.Accounts.User.admin?(@current_scope.user) do %>
                <.link
                  navigate={~p"/admin"}
                  class={mobile_nav_link_class(@current_path, "/admin")}
                >
                  {gettext("Admin")}
                </.link>
              <% end %>
            <% end %>
          </div>
          <%= if @current_scope do %>
            <div class="border-t border-zinc-950/10 dark:border-white/10 px-3 py-3">
              <div class="flex items-center gap-3 mb-3">
                <div class="size-10 rounded-full bg-blue-600 dark:bg-blue-500 flex items-center justify-center text-white font-semibold">
                  {String.first(@current_scope.user.email) |> String.upcase()}
                </div>
                <div class="text-sm font-medium text-zinc-950 dark:text-white truncate">
                  {@current_scope.user.email}
                </div>
              </div>
              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="block rounded-lg px-3 py-2 text-base font-medium text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800 hover:text-zinc-950 dark:hover:text-white"
              >
                {gettext("Sign out")}
              </.link>
            </div>
          <% else %>
            <div class="border-t border-zinc-950/10 dark:border-white/10 px-3 py-3 space-y-1">
              <.link
                navigate={~p"/users/log-in"}
                class="block rounded-lg px-3 py-2 text-base font-medium text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800 hover:text-zinc-950 dark:hover:text-white"
              >
                {gettext("Log in")}
              </.link>
              <.link
                navigate={~p"/users/register"}
                class="block rounded-lg px-3 py-2 text-base font-medium text-blue-600 dark:text-blue-400 hover:bg-zinc-100 dark:hover:bg-zinc-800"
              >
                {gettext("Get Started")}
              </.link>
            </div>
          <% end %>
        </div>
      </nav>

      <header class="bg-white dark:bg-zinc-900 border-b border-zinc-950/10 dark:border-white/10">
        <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <h1 class="text-2xl font-semibold text-zinc-950 dark:text-white">
            {@page_title || app_name()}
          </h1>
        </div>
      </header>

      <main class="flex-1 bg-zinc-50 dark:bg-zinc-950">
        <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
          {render_slot(@inner_block)}
        </div>
      </main>

      <footer class="border-t border-zinc-950/10 dark:border-white/10 bg-white dark:bg-zinc-900">
        <div class="mx-auto max-w-7xl px-4 py-4 sm:px-6 lg:px-8">
          <p class="text-center text-xs text-zinc-500 dark:text-zinc-400">
            <a
              href="https://coinscanx.com/?ref=WMG2XT"
              target="_blank"
              rel="noopener noreferrer"
              class="hover:text-zinc-700 dark:hover:text-zinc-300"
            >
              {gettext("Get one month free on CoinScanX →")}
            </a>
          </p>
        </div>
      </footer>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  defp nav_link_class(current_path, link_path) do
    base = "rounded-lg px-3 py-2 text-sm font-medium transition-colors"

    active =
      case link_path do
        "/users/settings" -> current_path == link_path
        _ -> String.starts_with?(current_path || "", link_path)
      end

    if active do
      "#{base} bg-blue-50 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400"
    else
      "#{base} text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800 hover:text-zinc-950 dark:hover:text-white"
    end
  end

  defp mobile_nav_link_class(current_path, link_path) do
    base = "block rounded-lg px-3 py-2 text-base font-medium transition-colors"

    active =
      case link_path do
        "/users/settings" -> current_path == link_path
        _ -> String.starts_with?(current_path || "", link_path)
      end

    if active do
      "#{base} bg-blue-50 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400"
    else
      "#{base} text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800 hover:text-zinc-950 dark:hover:text-white"
    end
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex h-10 items-center rounded-lg border border-zinc-950/10 bg-white px-1 dark:border-white/10 dark:bg-zinc-900">
      <div class="absolute left-0 top-1 bottom-1 w-1/3 rounded-md bg-zinc-100 transition-[left] duration-150 ease-in-out dark:bg-zinc-800 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3" />

      <button
        class="relative z-10 flex h-full flex-1 cursor-pointer items-center justify-center gap-1.5 rounded-md text-sm font-medium text-zinc-500 transition-colors hover:text-zinc-950 dark:text-zinc-400 dark:hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        class="relative z-10 flex h-full flex-1 cursor-pointer items-center justify-center gap-1.5 rounded-md text-sm font-medium text-zinc-500 transition-colors hover:text-zinc-950 dark:text-zinc-400 dark:hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        class="relative z-10 flex h-full flex-1 cursor-pointer items-center justify-center gap-1.5 rounded-md text-sm font-medium text-zinc-500 transition-colors hover:text-zinc-950 dark:text-zinc-400 dark:hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end

  @doc """
  Renders the landing page layout for logged-out users.

  This is a minimal marketing layout with header navigation and footer,
  without the app's sidebar and user menu.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  slot :inner_block, required: true

  def landing(assigns) do
    ~H"""
    <div class="min-h-screen bg-white">
      <%!-- Header --%>
      <header>
        <nav>
          <div class="relative z-50 flex justify-between py-8 mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
            <div class="relative z-10 flex items-center gap-16">
              <a href="/" class="flex items-center gap-2">
                <span class="text-2xl" aria-label={app_name()}>🦉</span>
                <span class="text-lg font-semibold text-zinc-900">
                  {app_name()}
                </span>
              </a>
              <div class="hidden lg:flex lg:gap-10">
                <a href="#features" class="text-sm font-medium text-zinc-700 hover:text-zinc-900">
                  {gettext("Features")}
                </a>
                <a href="#faqs" class="text-sm font-medium text-zinc-700 hover:text-zinc-900">
                  {gettext("FAQs")}
                </a>
              </div>
            </div>
            <div class="flex items-center gap-4">
              <.link
                navigate={~p"/users/log-in"}
                class="hidden lg:inline-flex rounded-lg px-4 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-100"
              >
                {gettext("Log in")}
              </.link>
              <.link
                navigate={~p"/users/register"}
                class="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-medium text-white hover:bg-zinc-800"
              >
                {gettext("Get Started")}
              </.link>
            </div>
          </div>
        </nav>
      </header>

      <%!-- Main Content --%>
      <main>
        {render_slot(@inner_block)}
      </main>

      <%!-- Footer --%>
      <footer class="border-t border-zinc-200">
        <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div class="flex flex-col items-start justify-between gap-y-12 pt-16 pb-6 lg:flex-row lg:items-center lg:py-16">
            <div>
              <div class="flex items-center text-zinc-900">
                <span class="text-3xl">🦉</span>
                <div class="ml-4">
                  <p class="text-base font-semibold">{app_name()}</p>
                  <p class="mt-1 text-sm text-zinc-600">
                    {gettext("Know when to buy. Know when to sell.")}
                  </p>
                </div>
              </div>
              <nav class="mt-11 flex gap-8">
                <a href="#features" class="text-sm font-medium text-zinc-700 hover:text-zinc-900">
                  {gettext("Features")}
                </a>
                <a href="#faqs" class="text-sm font-medium text-zinc-700 hover:text-zinc-900">
                  {gettext("FAQs")}
                </a>
              </nav>
            </div>
          </div>
          <div class="flex flex-col items-center border-t border-zinc-200 pt-8 pb-12 md:flex-row md:justify-between md:pt-6">
            <p class="text-sm text-zinc-500">
              © {Date.utc_today().year} {app_name()}. {gettext("All rights reserved.")}
            </p>
            <a
              href="https://coinscanx.com/?ref=WMG2XT"
              target="_blank"
              rel="noopener noreferrer"
              class="mt-4 md:mt-0 text-sm font-medium text-zinc-700 hover:text-zinc-900"
            >
              {gettext("Get one month free on CoinScanX →")}
            </a>
          </div>
        </div>
      </footer>

      <.flash_group flash={@flash} />
    </div>
    """
  end
end
