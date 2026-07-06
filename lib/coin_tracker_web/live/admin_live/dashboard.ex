defmodule CoinTrackerWeb.AdminLive.Dashboard do
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Repo

  @impl true
  def mount(_params, _session, socket) do
    stats = %{
      total_users: count_total_users(),
      active_subscriptions: count_active_subscriptions(),
      total_positions: count_total_positions(),
      total_signals: count_total_signals()
    }

    {:ok,
     socket
     |> assign(stats: stats)
     |> assign(page_title: "Admin Dashboard")}
  end

  defp count_total_users do
    Repo.aggregate(CoinTracker.Accounts.User, :count, :id)
  end

  defp count_active_subscriptions do
    import Ecto.Query

    from(u in CoinTracker.Accounts.User,
      where: u.subscription_tier in [:pro, :admin]
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_total_positions do
    Repo.aggregate(CoinTracker.Trading.Position, :count, :id)
  end

  defp count_total_signals do
    Repo.aggregate(CoinTracker.Signals.Signal, :count, :id)
  end
end
