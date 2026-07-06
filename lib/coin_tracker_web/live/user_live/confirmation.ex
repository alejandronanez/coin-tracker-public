defmodule CoinTrackerWeb.UserLive.Confirmation do
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      page_title="Confirm"
      current_path={@current_path}
    >
      <div class="mx-auto max-w-md">
        <div class="text-center mb-8">
          <h1 class="text-2xl font-bold text-zinc-900 dark:text-white">Welcome {@user.email}</h1>
        </div>

        <.form
          :if={!@user.confirmed_at}
          for={@form}
          id="confirmation_form"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/users/log-in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <div class="space-y-3">
            <.button
              variant="primary"
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Confirming..."
              class="w-full"
            >
              Confirm and stay logged in
            </.button>
            <.button phx-disable-with="Confirming..." class="w-full">
              Confirm and log in only this time
            </.button>
          </div>
        </.form>

        <.form
          :if={@user.confirmed_at}
          for={@form}
          id="login_form"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <%= if @current_scope do %>
            <.button variant="primary" phx-disable-with="Logging in..." class="w-full">
              Log in
            </.button>
          <% else %>
            <div class="space-y-3">
              <.button
                variant="primary"
                name={@form[:remember_me].name}
                value="true"
                phx-disable-with="Logging in..."
                class="w-full"
              >
                Keep me logged in on this device
              </.button>
              <.button phx-disable-with="Logging in..." class="w-full">
                Log me in only this time
              </.button>
            </div>
          <% end %>
        </.form>

        <div
          :if={!@user.confirmed_at}
          class="mt-8 rounded-lg border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 px-4 py-3"
        >
          <p class="text-sm text-zinc-600 dark:text-zinc-400">
            <span class="font-medium">Tip:</span>
            If you prefer passwords, you can enable them in the user settings.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Magic link is invalid or it has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
