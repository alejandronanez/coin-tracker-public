defmodule CoinTrackerWeb.MarketStatusLive.Index do
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Signals

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to PubSub topic for real-time updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "market_status:updated")
    end

    socket =
      socket
      |> assign(:page_title, "Market Status History")
      |> assign(:time_period, "today")
      |> load_market_statuses()

    {:ok, socket}
  end

  @impl true
  def handle_event("change_period", %{"time_period" => time_period}, socket) do
    socket =
      socket
      |> assign(:time_period, time_period)
      |> load_market_statuses()

    {:noreply, socket}
  end

  # Handle case where time_period is not in params (e.g., empty value)
  def handle_event("change_period", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:market_status_created, market_status}, socket) do
    # Always update latest_status for the status card
    socket = assign(socket, :latest_status, market_status)

    # Only update chart data if viewing "today" (raw data)
    socket =
      if socket.assigns.time_period == "today" do
        # Prepend new status and rebuild chart
        # Limit to 144 records (24 hours at 10-minute intervals) to prevent unbounded memory growth
        statuses = [market_status | socket.assigns.statuses] |> Enum.take(144)

        socket
        |> assign(:statuses, statuses)
        |> assign(:empty?, false)
        |> assign(:chart_data, build_chart_data(statuses))
      else
        socket
      end

    {:noreply, socket}
  end

  defp load_market_statuses(socket) do
    time_period = socket.assigns.time_period
    statuses = Signals.list_market_statuses_aggregated(time_period)
    latest = Signals.get_latest_market_status()

    socket
    |> assign(:statuses, statuses)
    |> assign(:latest_status, latest)
    |> assign(:empty?, statuses == [])
    |> assign(:chart_data, build_chart_data(statuses))
  end

  defp build_chart_data(statuses) do
    series_data =
      Enum.map(statuses, fn s ->
        # Convert to milliseconds for ApexCharts
        timestamp = DateTime.to_unix(s.recorded_at) * 1000
        %{x: timestamp, y: s.active_signals_count}
      end)

    %{
      series: [
        %{
          name: "Active Signals",
          data: series_data
        }
      ]
    }
  end
end
