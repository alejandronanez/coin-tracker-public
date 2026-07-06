defmodule CoinTrackerWeb.UserLive.Login do
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md">
        <div class="text-center mb-8">
          <h1 class="text-2xl font-bold text-zinc-950 dark:text-white">Log in</h1>
          <p class="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
            <%= if @current_scope do %>
              You need to reauthenticate to perform sensitive actions on your account.
            <% else %>
              Don't have an account?
              <.link
                navigate={~p"/users/register"}
                class="font-semibold text-blue-600 hover:text-blue-500 dark:text-blue-400 dark:hover:text-blue-300"
              >
                Sign up
              </.link>
              for an account now.
            <% end %>
          </p>
        </div>

        <div
          :if={local_mail_adapter?()}
          class="mb-6 rounded-lg border border-blue-200 dark:border-blue-900 bg-blue-50 dark:bg-blue-950/20 p-4"
        >
          <div class="flex items-start gap-3">
            <.icon
              name="hero-information-circle"
              class="size-5 shrink-0 text-blue-600 dark:text-blue-400"
            />
            <div class="text-sm text-blue-900 dark:text-blue-100">
              <p class="font-medium">You are running the local mail adapter.</p>
              <p class="mt-1">
                To see sent emails, visit <.link
                  href="/dev/mailbox"
                  class="underline hover:text-blue-700 dark:hover:text-blue-200"
                >
                  the mailbox page
                </.link>.
              </p>
            </div>
          </div>
        </div>

        <.form for={@form} id="login_form_magic" action={~p"/users/log-in"} phx-submit="submit_magic">
          <.input
            readonly={!!@current_scope}
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            required
            phx-mounted={JS.focus()}
            id="login_form_magic_email"
          />
          <div class="mt-6">
            <.button variant="primary" class="w-full">
              Log in with email <span aria-hidden="true">→</span>
            </.button>
          </div>
        </.form>

        <div class="relative my-6">
          <div class="absolute inset-0 flex items-center">
            <div class="w-full border-t border-zinc-950/10 dark:border-white/10"></div>
          </div>
          <div class="relative flex justify-center text-sm">
            <span class="bg-zinc-50 dark:bg-zinc-950 px-2 text-zinc-500">or</span>
          </div>
        </div>

        <.form
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <div class="space-y-6">
            <.input
              readonly={!!@current_scope}
              field={@form[:email]}
              type="email"
              label="Email"
              autocomplete="username"
              required
              id="login_form_password_email"
            />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="current-password"
            />
          </div>
          <div class="mt-6 space-y-3">
            <.button variant="primary" class="w-full" name={@form[:remember_me].name} value="true">
              Log in and stay logged in <span aria-hidden="true">→</span>
            </.button>
            <.button class="w-full">
              Log in only this time
            </.button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:coin_tracker, CoinTracker.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
