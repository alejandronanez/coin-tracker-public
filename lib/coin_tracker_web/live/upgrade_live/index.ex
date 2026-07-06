defmodule CoinTrackerWeb.UpgradeLive.Index do
  @moduledoc """
  Pricing page placeholder.

  The paid payment on-ramp (TRC-20 USDT manual verification flow) has been
  removed from this public release. Fork operators are expected to wire
  their own payment system by re-implementing an upgrade flow here.
  """
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Pricing placeholder --%>
      <div class="py-16 sm:py-24 mx-auto max-w-3xl px-6 text-center">
        <div class="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-zinc-100 dark:bg-zinc-800 mb-8">
          <.icon name="hero-credit-card" class="h-8 w-8 text-zinc-400 dark:text-zinc-500" />
        </div>

        <h1 class="text-4xl font-bold tracking-tight text-zinc-950 dark:text-white">
          {gettext("Pricing")}
        </h1>

        <p class="mt-4 text-lg text-zinc-600 dark:text-zinc-400">
          {gettext(
            "Pricing is not configured in this build. Operators can integrate their own payment system here."
          )}
        </p>

        <%!-- Back link --%>
        <%= if @current_scope.user do %>
          <div class="mt-12">
            <a
              href={~p"/users/settings"}
              class="text-sm text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"
            >
              {gettext("Back to Settings")}
            </a>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    case socket.assigns.current_scope do
      %{user: %User{} = user} ->
        if User.active_subscription?(user) do
          {:ok,
           socket
           |> put_flash(:info, gettext("You already have an active Pro subscription."))
           |> push_navigate(to: ~p"/users/settings")}
        else
          {:ok, socket}
        end

      _ ->
        {:ok, socket}
    end
  end
end
