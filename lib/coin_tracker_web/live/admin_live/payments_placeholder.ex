defmodule CoinTrackerWeb.AdminLive.PaymentsPlaceholder do
  @moduledoc """
  Placeholder LiveView for the admin Payments panel.

  The TRC-20 USDT manual-payments system has been removed from this public
  release. The admin sidebar and dashboard card still link to `/admin/payments`,
  but with no Payments context backing it, this stub renders an empty
  "not configured" state. Fork operators can replace it with their own
  admin surface.
  """
  use CoinTrackerWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_url={@current_url} fluid?={@fluid?}>
      <div class="px-6 py-12">
        <div class="mx-auto max-w-2xl text-center">
          <div class="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-amber-100 dark:bg-amber-900/30 mb-6">
            <.icon name="hero-credit-card" class="h-7 w-7 text-amber-600 dark:text-amber-400" />
          </div>

          <h1 class="text-2xl font-semibold text-gray-900 dark:text-white">
            {gettext("Payments Not Configured")}
          </h1>

          <p class="mt-3 text-sm text-gray-600 dark:text-gray-400">
            {gettext(
              "The payment system is not included in this build. Fork operators can integrate their own payment solution here."
            )}
          </p>

          <div class="mt-8">
            <.link
              navigate={~p"/admin"}
              class="inline-flex items-center gap-2 rounded-md bg-zinc-600 px-4 py-2 text-sm font-semibold text-white shadow-xs hover:bg-zinc-500"
            >
              <.icon name="hero-arrow-left" class="size-4" /> {gettext("Back to Dashboard")}
            </.link>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Payments"))
     |> assign_new(:current_url, fn -> ~p"/admin/payments" end)
     |> assign_new(:fluid?, fn -> false end)}
  end
end
