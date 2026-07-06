defmodule CoinTrackerWeb.SignalLive.Show do
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Accounts
  alias CoinTracker.Accounts.User
  alias CoinTracker.Signals
  alias CoinTracker.Signals.Signal
  alias CoinTracker.Trading
  alias CoinTracker.Watchlist

  @max_snapshots 1000
  @out_of_top_position 11
  @default_occurrences_limit 5

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Signals.get_signal_with_price(id) do
      %Signal{} = signal ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(CoinTracker.PubSub, "signal_snapshots:#{signal.id}")
          Phoenix.PubSub.subscribe(CoinTracker.PubSub, "price_updates")
        end

        snapshots = Signals.get_snapshot_history(signal.id)
        {price_data, volume_data, position_data} = build_chart_data(snapshots)

        previous_occurrences =
          Signals.get_previous_occurrences(signal.symbol, signal.id,
            limit: @default_occurrences_limit
          )

        total_previous_count = Signals.count_previous_occurrences(signal.symbol, signal.id)

        socket =
          socket
          |> assign(:page_title, gettext("Signal: %{symbol}", symbol: signal.symbol))
          |> assign(:signal, signal)
          |> assign(:empty?, snapshots == [])
          |> assign(:snapshots, snapshots)
          |> assign(:price_chart_data, price_data)
          |> assign(:volume_chart_data, volume_data)
          |> assign(:position_chart_data, position_data)
          |> assign(:best_position, calculate_best_position(snapshots))
          |> assign(:is_pro_user, pro_user?(socket.assigns.current_scope))
          |> assign_signal_metrics(signal)
          |> assign(:previous_occurrences, previous_occurrences)
          |> assign(:total_previous_count, total_previous_count)
          |> assign(:show_all_occurrences?, false)
          |> assign_watch_state()
          |> assign_credentials()

        {:ok, socket}

      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Signal not found"))
         |> push_navigate(to: ~p"/signals")}
    end
  end

  # --- Watchlist helpers ---

  defp assign_watch_state(socket) do
    user = socket.assigns[:current_scope] && socket.assigns.current_scope.user
    enabled? = not is_nil(user)

    watched? =
      enabled? && watched_for_signal?(user.id, socket.assigns.signal)

    socket
    |> assign(:watchlist_enabled?, enabled?)
    |> assign(:watched?, watched? || false)
  end

  defp watched_for_signal?(user_id, signal) do
    base = base_symbol_for_signal(signal)
    base && Trading.watching?(user_id, base)
  end

  defp base_symbol_for_signal(%Signal{symbol_price: %{symbol_pair: pair}}),
    do: Watchlist.base_symbol(pair)

  defp base_symbol_for_signal(_), do: nil

  defp assign_credentials(socket) do
    user = socket.assigns.current_scope.user
    assign(socket, :has_credentials, Accounts.has_exchange_credential?(user.id, :binance_spot))
  end

  # --- Event handlers ---

  @impl true
  def handle_event("toggle_occurrences", _params, socket) do
    signal = socket.assigns.signal
    show_all? = not socket.assigns.show_all_occurrences?

    limit = if show_all?, do: :all, else: @default_occurrences_limit
    occurrences = Signals.get_previous_occurrences(signal.symbol, signal.id, limit: limit)

    {:noreply,
     socket
     |> assign(:previous_occurrences, occurrences)
     |> assign(:show_all_occurrences?, show_all?)}
  end

  @impl true
  def handle_event("toggle_watch", _params, socket) do
    user = socket.assigns[:current_scope] && socket.assigns.current_scope.user

    cond do
      not socket.assigns.watchlist_enabled? ->
        {:noreply, socket}

      is_nil(user) ->
        {:noreply, socket}

      socket.assigns.watched? ->
        do_unwatch(socket, user)

      true ->
        do_watch(socket, user)
    end
  end

  defp do_watch(socket, user) do
    case Trading.watch_signal(user.id, socket.assigns.signal) do
      {:ok, _position} ->
        {:noreply,
         socket
         |> assign(:watched?, true)
         |> put_flash(
           :info,
           gettext("Watching %{symbol}", symbol: String.upcase(socket.assigns.signal.symbol))
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not start watching this signal"))}
    end
  end

  defp do_unwatch(socket, user) do
    case Trading.unwatch_signal(user.id, socket.assigns.signal) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:watched?, false)
         |> put_flash(
           :info,
           gettext("Stopped watching %{symbol}",
             symbol: String.upcase(socket.assigns.signal.symbol)
           )
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not stop watching this signal"))}
    end
  end

  # --- PubSub handlers ---

  @impl true
  def handle_info({:snapshot_created, snapshot}, socket) do
    snapshots = [snapshot | socket.assigns.snapshots] |> Enum.take(@max_snapshots)
    {price_data, volume_data, position_data} = build_chart_data(snapshots)

    socket =
      socket
      |> assign(:empty?, false)
      |> assign(:snapshots, snapshots)
      |> assign(:price_chart_data, price_data)
      |> assign(:volume_chart_data, volume_data)
      |> assign(:position_chart_data, position_data)
      |> assign(:best_position, calculate_best_position(snapshots))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:price_updated, symbol_price}, socket) do
    signal = socket.assigns.signal

    if signal.symbol_price_id == symbol_price.id do
      updated_signal = %{signal | symbol_price: symbol_price}

      {:noreply,
       socket
       |> assign(:signal, updated_signal)
       |> assign(:current_price, get_current_price(updated_signal))
       |> assign(:price_performance, calculate_price_performance(updated_signal))}
    else
      {:noreply, socket}
    end
  end

  # --- Signal metrics ---

  defp assign_signal_metrics(socket, signal) do
    socket
    |> assign(:volume_change_percentage, calculate_volume_change(signal))
    |> assign(:time_in_top, calculate_time_in_top(signal))
    |> assign(:price_performance, calculate_price_performance(signal))
    |> assign(:current_price, get_current_price(signal))
    |> assign(:max_increase, format_max_increase(signal.max_increase_percentage))
  end

  # --- Chart data ---

  defp build_chart_data(snapshots) do
    sorted_snapshots = Enum.sort_by(snapshots, & &1.snapshot_at, DateTime)

    price_data =
      Enum.map(sorted_snapshots, fn s ->
        timestamp = DateTime.to_unix(s.snapshot_at) * 1000
        price = decimal_to_float(s.current_price_usd)
        %{x: timestamp, y: price}
      end)

    volume_data =
      Enum.map(sorted_snapshots, fn s ->
        timestamp = DateTime.to_unix(s.snapshot_at) * 1000
        volume = decimal_to_float(s.current_volume_24h)
        %{x: timestamp, y: volume}
      end)

    position_data =
      Enum.map(sorted_snapshots, fn s ->
        timestamp = DateTime.to_unix(s.snapshot_at) * 1000
        position = if s.in_top && s.position, do: s.position, else: @out_of_top_position
        %{x: timestamp, y: position}
      end)

    {%{data: price_data}, %{data: volume_data}, %{data: position_data}}
  end

  defp decimal_to_float(nil), do: nil
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp decimal_to_float(value) when is_float(value), do: value
  defp decimal_to_float(value) when is_integer(value), do: value / 1

  # --- Formatting helpers ---

  defdelegate format_price(price), to: CoinTrackerWeb.SignalHelpers
  defdelegate format_seconds(diff_seconds), to: CoinTrackerWeb.SignalHelpers
  defdelegate occurrence_top_delta_text(occurrence), to: CoinTrackerWeb.SignalHelpers
  defdelegate occurrence_top_delta_class(occurrence), to: CoinTrackerWeb.SignalHelpers
  defdelegate sorted_position_durations(durations), to: CoinTrackerWeb.SignalHelpers

  # --- Private helpers ---

  defp calculate_volume_change(%Signal{initial_volume_24h: nil}), do: nil

  defp calculate_volume_change(%Signal{initial_volume_24h: initial} = signal) do
    if Decimal.equal?(initial, 0) do
      nil
    else
      signal |> Signal.volume_increase_percentage() |> Decimal.to_float()
    end
  end

  defp calculate_time_in_top(%Signal{in_top_since: nil}), do: nil

  defp calculate_time_in_top(%Signal{in_top_since: in_top_since, exit_date: exit_date}) do
    end_time = exit_date || DateTime.utc_now()
    diff_seconds = DateTime.diff(end_time, in_top_since, :second)
    format_seconds(diff_seconds)
  end

  defp calculate_best_position([]), do: nil

  defp calculate_best_position(snapshots) do
    snapshots
    |> Enum.filter(&(&1.in_top && &1.position))
    |> Enum.map(& &1.position)
    |> Enum.min(fn -> nil end)
  end

  defp calculate_price_performance(%Signal{initial_price_usd: nil}), do: nil

  defp calculate_price_performance(%Signal{initial_price_usd: initial} = signal) do
    if Decimal.equal?(initial, 0) do
      nil
    else
      current = get_current_price(signal)

      if current do
        current
        |> Decimal.sub(initial)
        |> Decimal.div(initial)
        |> Decimal.mult(100)
        |> Decimal.to_float()
      else
        nil
      end
    end
  end

  defp get_current_price(%Signal{symbol_price: %{current_price: price}}) when not is_nil(price),
    do: price

  defp get_current_price(%Signal{current_price_usd: price}), do: price

  defp format_max_increase(nil), do: nil
  defp format_max_increase(%Decimal{} = value), do: Decimal.to_float(value)
  defp format_max_increase(value) when is_float(value), do: value
  defp format_max_increase(value) when is_integer(value), do: value / 1

  defp pro_user?(current_scope) do
    current_scope && current_scope.user && User.active_subscription?(current_scope.user)
  end
end
