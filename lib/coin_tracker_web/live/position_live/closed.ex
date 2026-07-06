defmodule CoinTrackerWeb.PositionLive.Closed do
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Signals
  alias CoinTracker.Trading

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, gettext("Closed Positions"))
     |> load_closed_positions(user)}
  end

  @impl true
  def handle_event("remove_position", %{"position-id" => position_id}, socket) do
    user = socket.assigns.current_scope.user

    case Trading.delete_closed_position_for_user(user.id, position_id) do
      {:ok, _position} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Position removed"))
         |> load_closed_positions(user)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Position not found"))}
    end
  end

  defp load_closed_positions(socket, user) do
    positions = Trading.list_closed_positions_for_user(user.id)

    socket
    |> assign(:positions, enrich_with_signals(positions))
    |> assign(:positions_empty?, positions == [])
    |> assign(:totals, calculate_totals(positions))
  end

  # Enriches each position with signal data at entry time
  defp enrich_with_signals(positions) do
    Enum.map(positions, fn position ->
      base_symbol = extract_base_symbol(position.symbol_price.symbol_pair)
      signal = Signals.find_signal_at_time(base_symbol, position.inserted_at)
      Map.put(position, :entry_signal, signal)
    end)
  end

  defp calculate_totals(positions) do
    # Only positions with exit_price AND amount_invested can have dollar PnL
    positions_with_pnl =
      Enum.filter(positions, &(&1.exit_price != nil && &1.amount_invested != nil))

    total_pnl_usd =
      positions_with_pnl
      |> Enum.map(&calculate_pnl_usd/1)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    # Only count wins/losses for positions with exit_price
    positions_with_exit_price = Enum.filter(positions, & &1.exit_price)
    win_count = Enum.count(positions_with_exit_price, &position_profitable?/1)
    loss_count = length(positions_with_exit_price) - win_count

    # Count positions without exit_price separately
    unknown_count = length(positions) - length(positions_with_exit_price)

    %{
      total_pnl_usd: total_pnl_usd,
      win_count: win_count,
      loss_count: loss_count,
      unknown_count: unknown_count,
      total_count: length(positions)
    }
  end

  # Helper functions

  defp extract_base_symbol(symbol_pair) do
    symbol_pair
    |> String.split("/")
    |> List.first()
    |> Kernel.||("N/A")
  end

  defp format_exchange(:binance_spot), do: "Binance"
  defp format_exchange(:bitget_spot), do: "Bitget"
  defp format_exchange(:mexc_spot), do: "MEXC"
  defp format_exchange(exchange), do: exchange |> to_string() |> String.capitalize()

  defp format_price(nil), do: "—"

  defp format_price(decimal) do
    decimal
    |> Decimal.round(8)
    |> Decimal.to_string(:normal)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp get_pnl_percent(%{exit_price: nil}), do: nil

  defp get_pnl_percent(position) do
    Trading.calculate_pnl_percent(position.entry_price, position.exit_price)
  end

  defp format_pnl_percent(%{exit_price: nil}), do: "N/A"

  defp format_pnl_percent(position) do
    pnl = get_pnl_percent(position)
    sign = if Decimal.negative?(pnl), do: "", else: "+"
    "#{sign}#{Decimal.round(pnl, 2) |> Decimal.to_string()}%"
  end

  defp pnl_color_class(%{exit_price: nil}), do: "text-zinc-400"

  defp pnl_color_class(position) do
    pnl = get_pnl_percent(position)

    cond do
      Decimal.positive?(pnl) -> "text-green-500"
      Decimal.negative?(pnl) -> "text-red-500"
      true -> "text-gray-500"
    end
  end

  defp position_profitable?(%{exit_price: nil}), do: nil

  defp position_profitable?(position) do
    pnl = get_pnl_percent(position)
    Decimal.positive?(pnl)
  end

  defp calculate_pnl_usd(%{exit_price: nil}), do: nil

  defp calculate_pnl_usd(position) do
    case position.amount_invested do
      nil ->
        nil

      amount_invested ->
        pnl_percent = get_pnl_percent(position)
        Decimal.mult(amount_invested, Decimal.div(pnl_percent, 100))
    end
  end

  defp format_pnl_usd(%{exit_price: nil}), do: nil

  defp format_pnl_usd(position) do
    case position.amount_invested do
      nil ->
        nil

      _amount_invested ->
        pnl_usd = calculate_pnl_usd(position)
        sign = if Decimal.negative?(pnl_usd), do: "-", else: "+"
        formatted = pnl_usd |> Decimal.abs() |> Decimal.round(2) |> Decimal.to_string()
        "#{sign}$#{formatted}"
    end
  end

  defp format_total_pnl_usd(total_pnl_usd) do
    sign = if Decimal.negative?(total_pnl_usd), do: "-", else: "+"
    formatted = total_pnl_usd |> Decimal.abs() |> Decimal.round(2) |> Decimal.to_string()
    "#{sign}$#{formatted}"
  end

  defp total_pnl_color_class(total_pnl_usd) do
    cond do
      Decimal.positive?(total_pnl_usd) -> "text-green-500"
      Decimal.negative?(total_pnl_usd) -> "text-red-500"
      true -> "text-gray-500"
    end
  end

  defp format_time_held(opened_at, closed_at) do
    diff_seconds = DateTime.diff(closed_at, opened_at, :second)

    days = div(diff_seconds, 86400)
    hours = div(rem(diff_seconds, 86400), 3600)
    minutes = div(rem(diff_seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h"
      hours > 0 -> "#{hours}h #{minutes}m"
      minutes > 0 -> "#{minutes}m"
      true -> "< 1m"
    end
  end

  defp format_closure_reason("take_profit"), do: gettext("Take Profit")
  defp format_closure_reason("stop_loss"), do: gettext("Stop Loss")
  defp format_closure_reason("manual"), do: gettext("Manual")
  defp format_closure_reason(_), do: gettext("Unknown")

  defp closure_reason_color("take_profit"),
    do: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400"

  defp closure_reason_color("stop_loss"),
    do: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400"

  defp closure_reason_color("manual"),
    do: "bg-zinc-100 text-zinc-800 dark:bg-zinc-800 dark:text-zinc-300"

  defp closure_reason_color(_),
    do: "bg-zinc-100 text-zinc-800 dark:bg-zinc-800 dark:text-zinc-300"
end
