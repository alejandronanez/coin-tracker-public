defmodule CoinTrackerWeb.UserLive.Settings do
  use CoinTrackerWeb, :live_view

  on_mount {CoinTrackerWeb.UserAuth, :require_sudo_mode}

  alias CoinTracker.Accounts
  alias CoinTracker.Accounts.User
  alias CoinTracker.TelegramClient.TelegramService

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      page_title={@page_title}
      current_path={@current_path}
    >
      <div class="space-y-6">
        <%!-- Subscription Status Section --%>
        <div class="border-b border-zinc-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-zinc-900 dark:text-white">
            {gettext("Subscription Status")}
          </h2>
          <p class="mt-1 text-sm/6 text-zinc-600 dark:text-zinc-400">
            {gettext("View and manage your subscription")}
          </p>

          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <div class="rounded-lg border border-zinc-300 dark:border-white/10 px-6 py-4">
                <div class="space-y-4">
                  <div class="flex items-center gap-3">
                    <span class="text-sm/6 font-medium text-zinc-900 dark:text-white">
                      {gettext("Current Plan:")}
                    </span>
                    <%= cond do %>
                      <% @current_scope.user.subscription_tier == :admin -> %>
                        <span class="inline-flex items-center rounded-full bg-purple-100 dark:bg-purple-900/30 px-3 py-1 text-sm font-medium text-purple-800 dark:text-purple-200">
                          {gettext("Admin")}
                        </span>
                      <% @current_scope.user.subscription_tier == :pro -> %>
                        <span class="inline-flex items-center rounded-full bg-blue-100 dark:bg-blue-900/30 px-3 py-1 text-sm font-medium text-blue-800 dark:text-blue-200">
                          {gettext("Pro")}
                        </span>
                      <% true -> %>
                        <span class="inline-flex items-center rounded-full bg-zinc-100 dark:bg-zinc-700 px-3 py-1 text-sm font-medium text-zinc-800 dark:text-zinc-200">
                          {gettext("Free")}
                        </span>
                    <% end %>
                  </div>

                  <%= cond do %>
                    <% @current_scope.user.subscription_tier == :admin -> %>
                      <p class="text-sm/6 text-zinc-600 dark:text-zinc-400">
                        {gettext("Full access to all features")}
                      </p>
                    <% @current_scope.user.subscription_tier == :pro && @current_scope.user.subscription_expires_at -> %>
                      <p class="text-sm/6 text-zinc-600 dark:text-zinc-400">
                        {gettext("Expires on %{date}",
                          date:
                            Calendar.strftime(
                              @current_scope.user.subscription_expires_at,
                              "%B %d, %Y"
                            )
                        )}
                      </p>
                      <%= if DateTime.diff(@current_scope.user.subscription_expires_at, DateTime.utc_now(), :day) < 7 do %>
                        <p class="flex items-center gap-2 text-sm/6 text-blue-600 dark:text-blue-400">
                          <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
                          {gettext("Your subscription will expire soon!")}
                        </p>
                      <% end %>
                    <% @current_scope.user.subscription_tier == :pro -> %>
                      <p class="text-sm/6 text-zinc-600 dark:text-zinc-400">
                        {gettext("Lifetime Pro access")}
                      </p>
                    <% true -> %>
                      <div class="space-y-3">
                        <p class="text-sm/6 text-zinc-600 dark:text-zinc-400">
                          {gettext("Upgrade to Pro for premium features:")}
                        </p>
                        <ul class="text-sm/6 text-zinc-600 dark:text-zinc-400 space-y-1 list-disc list-inside">
                          <li>{gettext("Access to signals")}</li>
                          <li>{gettext("Telegram notifications")}</li>
                          <li>{gettext("API access")}</li>
                        </ul>
                        <a
                          href={~p"/upgrade"}
                          class="inline-flex items-center gap-2 rounded-md bg-orange-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-orange-500 dark:bg-orange-500 dark:hover:bg-orange-400"
                        >
                          {gettext("Upgrade to Pro")}
                        </a>
                      </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Email Section --%>
        <div class="border-b border-zinc-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-zinc-900 dark:text-white">
            {gettext("Email Address")}
          </h2>
          <p class="mt-1 text-sm/6 text-zinc-600 dark:text-zinc-400">
            {gettext("Update your email address for account access")}
          </p>

          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <.form
                for={@email_form}
                id="email_form"
                phx-submit="update_email"
                phx-change="validate_email"
              >
                <.input
                  field={@email_form[:email]}
                  type="email"
                  label={gettext("Email")}
                  autocomplete="username"
                  description={gettext("We'll send a confirmation link to your new email address")}
                  required
                />
                <div class="mt-6">
                  <.button variant="primary" phx-disable-with={gettext("Changing...")}>
                    {gettext("Change Email")}
                  </.button>
                </div>
              </.form>
            </div>
          </div>
        </div>

        <%!-- Password Section --%>
        <div class="border-b border-zinc-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-zinc-900 dark:text-white">
            {gettext("Password")}
          </h2>
          <p class="mt-1 text-sm/6 text-zinc-600 dark:text-zinc-400">
            {gettext("Update your password to keep your account secure")}
          </p>

          <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <div class="sm:col-span-4">
              <.form
                for={@password_form}
                id="password_form"
                action={~p"/users/update-password"}
                method="post"
                phx-change="validate_password"
                phx-submit="update_password"
                phx-trigger-action={@trigger_submit}
              >
                <input
                  name={@password_form[:email].name}
                  type="hidden"
                  id="hidden_user_email"
                  autocomplete="username"
                  value={@current_email}
                />

                <div class="space-y-8">
                  <.input
                    field={@password_form[:password]}
                    type="password"
                    label={gettext("New password")}
                    autocomplete="new-password"
                    description={gettext("Choose a strong password with at least 12 characters")}
                    required
                  />
                  <.input
                    field={@password_form[:password_confirmation]}
                    type="password"
                    label={gettext("Confirm new password")}
                    autocomplete="new-password"
                    description={gettext("Re-enter your new password to confirm")}
                    required
                  />
                </div>

                <div class="mt-6">
                  <.button variant="primary" phx-disable-with={gettext("Saving...")}>
                    {gettext("Save Password")}
                  </.button>
                </div>
              </.form>
            </div>
          </div>
        </div>

        <%!-- Theme Section --%>
        <div class="border-b border-zinc-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-zinc-900 dark:text-white">
            {gettext("Theme Preference")}
          </h2>
          <p class="mt-1 text-sm/6 text-zinc-600 dark:text-zinc-400">
            {gettext("Choose your preferred color theme")}
          </p>

          <div class="mt-6">
            <Layouts.theme_toggle />
          </div>
        </div>

        <%!-- Language Section --%>
        <div class="border-b border-zinc-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-zinc-900 dark:text-white">
            {gettext("Language")}
          </h2>
          <p class="mt-1 text-sm/6 text-zinc-600 dark:text-zinc-400">
            {gettext("Choose your preferred language")}
          </p>

          <div class="mt-6">
            <.form for={@locale_form} id="locale-form" phx-change="update_locale">
              <.input
                field={@locale_form[:locale]}
                type="select"
                options={[
                  {gettext("English"), "en"},
                  {gettext("Spanish"), "es"}
                ]}
              />
            </.form>
          </div>
        </div>

        <%!-- Telegram Integration Section (Pro and Admin only) --%>
        <%= if @has_pro_subscription do %>
          <div class="border-b border-zinc-900/10 pb-12 dark:border-white/10">
            <h2 class="text-base/7 font-semibold text-zinc-900 dark:text-white">
              {gettext("Telegram Integration")}
            </h2>
            <p class="mt-1 text-sm/6 text-zinc-600 dark:text-zinc-400">
              {gettext("Connect your Telegram account to receive real-time position alerts")}
            </p>

            <div class="mt-6">
              <%!-- Connection Status --%>
              <div class="rounded-lg border border-zinc-300 dark:border-white/10 px-4 py-3">
                <div class="flex items-center gap-2">
                  <span class="text-sm/6 font-medium text-zinc-900 dark:text-white">
                    {gettext("Status:")}
                  </span>
                  <%= if @telegram_connected do %>
                    <span class="flex items-center gap-1 text-sm/6 text-green-600 dark:text-green-400">
                      <.icon name="hero-check-circle" class="w-5 h-5" /> {gettext("Connected")}
                    </span>
                  <% else %>
                    <span class="text-sm/6 text-zinc-500 dark:text-zinc-400">
                      {gettext("Not connected")}
                    </span>
                  <% end %>
                </div>
              </div>

              <%!-- Connect Button / Deeplink Display --%>
              <div class="mt-6">
                <%= if @telegram_connected do %>
                  <p class="text-sm/6 text-zinc-600 dark:text-zinc-400">
                    {gettext(
                      "Your Telegram account is connected. You'll receive alerts about your positions."
                    )}
                  </p>
                <% else %>
                  <%= if @telegram_deeplink do %>
                    <%!-- Deeplink Display --%>
                    <div class="rounded-lg border border-blue-200 dark:border-blue-900 bg-blue-50 dark:bg-blue-950/20 p-4">
                      <div class="flex items-start gap-3">
                        <.icon
                          name="hero-information-circle"
                          class="w-5 h-5 shrink-0 text-blue-600 dark:text-blue-400"
                        />
                        <div class="space-y-3">
                          <p class="text-sm/6 font-medium text-blue-900 dark:text-blue-100">
                            {gettext("Click the button below to open Telegram:")}
                          </p>
                          <a
                            href={@telegram_deeplink}
                            target="_blank"
                            class="inline-flex items-center gap-2 rounded-md bg-orange-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-orange-500 dark:bg-orange-500 dark:hover:bg-orange-400"
                          >
                            <.icon name="hero-paper-airplane" class="w-4 h-4" /> {gettext(
                              "Open Telegram Bot"
                            )}
                          </a>
                          <details class="mt-2">
                            <summary class="cursor-pointer text-sm/6 text-blue-700 dark:text-blue-300 hover:text-blue-900 dark:hover:text-blue-100">
                              {gettext("Or copy the link manually")}
                            </summary>
                            <input
                              type="text"
                              readonly
                              value={@telegram_deeplink}
                              class="mt-2 block w-full rounded-md border border-blue-300 dark:border-blue-700 bg-white dark:bg-blue-950/30 px-3 py-2 font-mono text-xs text-zinc-900 dark:text-zinc-100"
                              onclick="this.select()"
                            />
                          </details>
                        </div>
                      </div>
                    </div>
                  <% else %>
                    <%!-- Connect Button --%>
                    <button
                      type="button"
                      phx-click="connect_telegram"
                      disabled={@telegram_loading}
                      class="inline-flex items-center gap-2 rounded-md bg-orange-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-orange-500 disabled:opacity-50 dark:bg-orange-500 dark:hover:bg-orange-400"
                      id="connect-telegram-btn"
                    >
                      <%= if @telegram_loading do %>
                        <span class="inline-block size-4 animate-spin rounded-full border-2 border-white border-r-transparent" />
                        {gettext("Generating link...")}
                      <% else %>
                        <.icon name="hero-link" class="w-5 h-5" /> {gettext("Connect to Telegram")}
                      <% end %>
                    </button>
                    <p class="mt-3 text-sm/6 text-zinc-600 dark:text-zinc-400">
                      {gettext(
                        "Connect your Telegram to receive instant notifications about your trading positions."
                      )}
                    </p>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Exchange API Keys Section --%>
        <div class="border-b border-zinc-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-zinc-900 dark:text-white">
            {gettext("Exchange API Keys")}
          </h2>
          <p class="mt-1 text-sm/6 text-zinc-600 dark:text-zinc-400">
            {gettext("Manage your exchange API credentials for automatic trading")}
          </p>

          <div class="mt-6">
            <.link
              navigate={~p"/settings/exchange-keys"}
              class="inline-flex items-center gap-2 rounded-md bg-orange-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-orange-500 dark:bg-orange-500 dark:hover:bg-orange-400"
              id="exchange-keys-link"
            >
              <.icon name="hero-key" class="w-5 h-5" />
              {gettext("Manage Exchange Keys")}
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, gettext("Email changed successfully."))

        {:error, _} ->
          put_flash(socket, :error, gettext("Email change link is invalid or it has expired."))
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    # Check subscription status
    has_pro_subscription = User.active_subscription?(user)

    # Check Telegram connection status
    telegram_user = Accounts.get_telegram_user(user.id)
    telegram_connected = not is_nil(telegram_user)

    # Get or create user settings for locale
    {:ok, user_settings} = Accounts.get_or_create_user_settings(user.id)
    locale_form = to_form(%{"locale" => user_settings.locale})

    socket =
      socket
      |> assign(:page_title, gettext("Settings"))
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:has_pro_subscription, has_pro_subscription)
      |> assign(:telegram_connected, telegram_connected)
      |> assign(:telegram_deeplink, nil)
      |> assign(:telegram_loading, false)
      |> assign(:user_settings, user_settings)
      |> assign(:locale_form, locale_form)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = gettext("A link to confirm your email change has been sent to the new address.")
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("connect_telegram", _params, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:telegram_loading, true)

    case TelegramService.generate_deeplink(user) do
      {:ok, deeplink} ->
        # Schedule periodic check to detect when user connects
        Process.send_after(self(), :check_telegram_connection, 3_000)

        {:noreply,
         socket
         |> assign(:telegram_deeplink, deeplink)
         |> assign(:telegram_loading, false)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:telegram_loading, false)
         |> put_flash(:error, gettext("Failed to generate Telegram link. Please try again."))}
    end
  end

  def handle_event("update_locale", %{"locale" => locale}, socket) do
    user_settings = socket.assigns.user_settings

    case Accounts.update_user_settings(user_settings, %{locale: locale}) do
      {:ok, updated_settings} ->
        # Set the new locale immediately
        Gettext.put_locale(CoinTrackerWeb.Gettext, locale)

        {:noreply,
         socket
         |> assign(:user_settings, updated_settings)
         |> assign(:locale_form, to_form(%{"locale" => locale}))
         |> put_flash(:info, gettext("Language preference updated."))
         |> push_navigate(to: ~p"/users/settings")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to update language preference."))}
    end
  end

  @impl true
  def handle_info(:check_telegram_connection, socket) do
    user = socket.assigns.current_scope.user
    telegram_user = Accounts.get_telegram_user(user.id)
    telegram_connected = not is_nil(telegram_user)

    socket =
      if telegram_connected and not socket.assigns.telegram_connected do
        # User just connected - show success and clear deeplink
        socket
        |> assign(:telegram_connected, true)
        |> assign(:telegram_deeplink, nil)
      else
        # Still waiting, schedule another check in 3 seconds
        if socket.assigns.telegram_deeplink && !telegram_connected do
          Process.send_after(self(), :check_telegram_connection, 3_000)
        end

        socket
      end

    {:noreply, socket}
  end

  # Ignore other system messages (e.g., email delivery notifications from Swoosh)
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end
end
