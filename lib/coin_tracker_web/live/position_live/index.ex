defmodule CoinTrackerWeb.PositionLive.Index do
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Trading
  alias CoinTracker.Watchlist

  import CoinTrackerWeb.PositionLive.Helpers, only: [format_pnl: 1]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    sort_by = "profit_desc"
    positions = Trading.list_active_positions_for_user(user.id)
    sorted_positions = sort_positions(positions, sort_by)
    entries_by_id = build_entries_by_id(sorted_positions)

    # Subscribe to real-time price updates and position closures when WebSocket is connected
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "price_updates")
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "signals:updated")
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "positions:#{user.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Positions"))
     |> assign(:positions, sorted_positions)
     |> assign(:entries_by_id, entries_by_id)
     |> assign(:positions_empty?, sorted_positions == [])
     |> assign(:sort_by, sort_by)}
  end

  @impl true
  def handle_info({:price_updated, symbol_price}, socket) do
    # Update positions that match this symbol_price
    updated_positions =
      Enum.map(socket.assigns.positions, fn position ->
        if position.symbol_price_id == symbol_price.id do
          # Update the nested symbol_price with new current_price
          %{position | symbol_price: symbol_price}
        else
          position
        end
      end)

    # Re-sort positions after price update
    sorted_positions = sort_positions(updated_positions, socket.assigns.sort_by)

    {:noreply, assign(socket, positions: sorted_positions)}
  end

  @impl true
  def handle_info({:signals_updated, _signals}, socket) do
    # Rank, status, and sparkline can change on each broadcast, but the underlying
    # positions list does not — re-enrich without disturbing sort or PnL state.
    {:noreply, assign(socket, :entries_by_id, build_entries_by_id(socket.assigns.positions))}
  end

  @impl true
  def handle_info({:position_closed, position_id, symbol_pair, reason}, socket) do
    updated_positions = Enum.reject(socket.assigns.positions, &(&1.id == position_id))

    reason_text = format_closure_reason(reason)

    flash_message =
      gettext("%{symbol_pair} position closed (%{reason})",
        symbol_pair: symbol_pair,
        reason: reason_text
      )

    {:noreply,
     socket
     |> assign(:positions, updated_positions)
     |> assign(:positions_empty?, updated_positions == [])
     |> put_flash(:info, flash_message)}
  end

  @impl true
  def handle_event("change_sort", %{"sort_by" => sort_by}, socket) do
    sorted_positions = sort_positions(socket.assigns.positions, sort_by)

    {:noreply,
     socket
     |> assign(:positions, sorted_positions)
     |> assign(:sort_by, sort_by)}
  end

  @impl true
  def handle_event("close_position", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    position_id = String.to_integer(id)

    case Trading.get_position_for_user(position_id, user_id) do
      {:ok, position} ->
        case Trading.close_position(position, :manual) do
          {:ok, _closed_position} ->
            # Remove the closed position from the active positions list
            updated_positions = Enum.reject(socket.assigns.positions, &(&1.id == position_id))

            {:noreply,
             socket
             |> assign(:positions, updated_positions)
             |> assign(:positions_empty?, updated_positions == [])
             |> put_flash(:info, gettext("Position closed successfully."))}

          {:error, :already_closed} ->
            {:noreply, put_flash(socket, :error, gettext("Position is already closed."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to close position."))}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Position not found."))}
    end
  end

  # Helper functions for sorting

  defp sort_positions(positions, "profit_desc") do
    Enum.sort_by(
      positions,
      fn position ->
        pnl =
          Trading.calculate_pnl_percent(position.entry_price, position.symbol_price.current_price)

        Decimal.to_float(pnl)
      end,
      :desc
    )
  end

  defp sort_positions(positions, "profit_asc") do
    Enum.sort_by(
      positions,
      fn position ->
        pnl =
          Trading.calculate_pnl_percent(position.entry_price, position.symbol_price.current_price)

        Decimal.to_float(pnl)
      end,
      :asc
    )
  end

  defp sort_positions(positions, "newest") do
    Enum.sort_by(positions, & &1.inserted_at, {:desc, DateTime})
  end

  defp sort_positions(positions, "oldest") do
    Enum.sort_by(positions, & &1.inserted_at, {:asc, DateTime})
  end

  defp sort_positions(positions, _), do: positions

  # Helper functions for template formatting

  defp format_exchange(:binance_spot), do: "Binance"
  defp format_exchange(:bitget_spot), do: "Bitget"
  defp format_exchange(:mexc_spot), do: "MEXC"
  defp format_exchange(exchange), do: exchange |> to_string() |> String.capitalize()

  defp format_price(decimal) do
    decimal
    |> Decimal.round(8)
    |> Decimal.to_string(:normal)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp get_pnl_percent(position) do
    Trading.calculate_pnl_percent(position.entry_price, position.symbol_price.current_price)
  end

  defp format_pnl_percent(position) do
    pnl = get_pnl_percent(position)
    sign = if Decimal.negative?(pnl), do: "", else: "+"
    "#{sign}#{Decimal.round(pnl, 2) |> Decimal.to_string()}%"
  end

  defp pnl_color_class(position) do
    pnl = get_pnl_percent(position)

    cond do
      Decimal.positive?(pnl) -> "text-green-500"
      Decimal.negative?(pnl) -> "text-red-500"
      true -> "text-gray-500"
    end
  end

  defp pnl_status_label(position) do
    pnl = get_pnl_percent(position)

    cond do
      Decimal.positive?(pnl) -> gettext("Profit")
      Decimal.negative?(pnl) -> gettext("Loss")
      true -> gettext("Neutral")
    end
  end

  defp calculate_pnl_usd(position) do
    case position.amount_invested do
      nil ->
        nil

      amount_invested ->
        pnl_percent = get_pnl_percent(position)
        Decimal.mult(amount_invested, Decimal.div(pnl_percent, 100))
    end
  end

  defp format_pnl_usd(position) do
    case calculate_pnl_usd(position) do
      nil ->
        nil

      pnl_usd ->
        sign = if Decimal.negative?(pnl_usd), do: "-", else: "+"
        formatted = pnl_usd |> Decimal.abs() |> Decimal.round(2) |> Decimal.to_string()
        "#{sign}$#{formatted}"
    end
  end

  defp format_time_held(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    days = div(diff_seconds, 86400)
    hours = div(rem(diff_seconds, 86400), 3600)

    cond do
      days > 0 -> "#{days}d #{hours}h"
      hours > 0 -> "#{hours}h"
      true -> "< 1h"
    end
  end

  defp extract_base_symbol(symbol_pair) do
    symbol_pair
    |> String.split("/")
    |> List.first()
    |> Kernel.||("N/A")
  end

  defp calculate_progress_percent(position) do
    pnl = get_pnl_percent(position)

    cond do
      Decimal.positive?(pnl) ->
        pnl
        |> Decimal.div(position.take_profit_percent)
        |> Decimal.mult(100)
        |> Decimal.min(100)
        |> Decimal.to_float()

      Decimal.negative?(pnl) ->
        pnl
        |> Decimal.abs()
        |> Decimal.div(Decimal.abs(position.stop_loss_percent))
        |> Decimal.mult(100)
        |> Decimal.min(100)
        |> Decimal.to_float()

      true ->
        0.0
    end
  end

  defp progress_bar_color(position) do
    pnl = get_pnl_percent(position)

    cond do
      Decimal.positive?(pnl) -> "bg-green-500"
      Decimal.negative?(pnl) -> "bg-red-500"
      true -> "bg-gray-500"
    end
  end

  defp format_progress_text(position) do
    pnl = get_pnl_percent(position)
    pnl_abs = Decimal.abs(pnl) |> Decimal.round(2) |> Decimal.to_string()

    target =
      if Decimal.positive?(pnl) do
        Decimal.to_string(position.take_profit_percent)
      else
        position.stop_loss_percent |> Decimal.abs() |> Decimal.to_string()
      end

    "#{pnl_abs}% / #{target}%"
  end

  defp projected_pnl_dollars(nil, _percent), do: nil

  defp projected_pnl_dollars(%Decimal{} = amount_invested, %Decimal{} = percent) do
    amount_invested
    |> Decimal.mult(percent)
    |> Decimal.div(100)
  end

  defp calculate_stop_loss_price(entry_price, stop_loss_percent) do
    multiplier =
      stop_loss_percent
      |> Decimal.div(100)
      |> Decimal.add(1)

    Decimal.mult(entry_price, multiplier)
  end

  defp calculate_take_profit_price(entry_price, take_profit_percent) do
    multiplier =
      take_profit_percent
      |> Decimal.div(100)
      |> Decimal.add(1)

    Decimal.mult(entry_price, multiplier)
  end

  defp format_closure_reason(:take_profit), do: gettext("take profit hit")
  defp format_closure_reason(:stop_loss), do: gettext("stop loss hit")

  defp build_entries_by_id(positions) do
    positions
    |> Watchlist.enrich()
    |> Map.new(fn entry -> {entry.position.id, entry} end)
  end

  defp watchlist_status_classes(:in_top),
    do:
      "bg-green-50 dark:bg-green-900/20 text-green-700 dark:text-green-300 border-green-200 dark:border-green-800/50"

  defp watchlist_status_classes(:dropped),
    do:
      "bg-amber-50 dark:bg-amber-900/20 text-amber-700 dark:text-amber-300 border-amber-200 dark:border-amber-800/50"

  defp watchlist_status_classes(:exited),
    do:
      "bg-zinc-100 dark:bg-zinc-800/60 text-zinc-600 dark:text-zinc-400 border-zinc-200 dark:border-zinc-700"

  defp watchlist_status_classes(:never_in_top),
    do:
      "bg-zinc-100 dark:bg-zinc-800/60 text-zinc-600 dark:text-zinc-400 border-zinc-200 dark:border-zinc-700"

  defp watchlist_status_label(%{status: :in_top, current_rank: rank}) when is_integer(rank),
    do: gettext("In top — #%{rank}", rank: rank)

  defp watchlist_status_label(%{status: :in_top}), do: gettext("In top 10")

  defp watchlist_status_label(%{status: :dropped, dropped_at: %DateTime{} = at}),
    do: gettext("Grace period — dropped %{ago}", ago: format_relative_time(at))

  defp watchlist_status_label(%{status: :dropped}), do: gettext("Grace period")

  defp watchlist_status_label(%{status: :exited, grace_ended_at: %DateTime{} = at}),
    do: gettext("Exited %{ago}", ago: format_relative_time(at))

  defp watchlist_status_label(%{status: :exited}), do: gettext("Exited")

  defp watchlist_status_label(%{status: :never_in_top}), do: gettext("Never in top 10")

  defp watchlist_status_icon(:in_top), do: "hero-arrow-trending-up"
  defp watchlist_status_icon(:dropped), do: "hero-arrow-trending-down"
  defp watchlist_status_icon(:exited), do: "hero-minus"
  defp watchlist_status_icon(:never_in_top), do: "hero-minus"

  defp rank_delta_classes(delta) when is_integer(delta) and delta > 0,
    do: "text-green-600 dark:text-green-400"

  defp rank_delta_classes(delta) when is_integer(delta) and delta < 0,
    do: "text-red-600 dark:text-red-400"

  defp rank_delta_classes(_), do: "text-zinc-500 dark:text-zinc-400"

  defp rank_delta_icon(delta) when is_integer(delta) and delta > 0, do: "hero-arrow-up"
  defp rank_delta_icon(delta) when is_integer(delta) and delta < 0, do: "hero-arrow-down"
  defp rank_delta_icon(_), do: "hero-minus"

  defp format_rank_delta(delta) when is_integer(delta) and delta > 0, do: "+#{delta}"
  defp format_rank_delta(delta) when is_integer(delta) and delta < 0, do: "#{delta}"
  defp format_rank_delta(_), do: "—"

  defp sparkline_color_classes(%{rank_delta: delta}) when is_integer(delta) and delta > 0,
    do: "text-green-500 dark:text-green-400"

  defp sparkline_color_classes(%{rank_delta: delta}) when is_integer(delta) and delta < 0,
    do: "text-red-500 dark:text-red-400"

  defp sparkline_color_classes(_), do: "text-zinc-400 dark:text-zinc-500"

  defp format_relative_time(%DateTime{} = at) do
    diff = DateTime.diff(DateTime.utc_now(), at, :second)

    cond do
      diff < 60 ->
        gettext("just now")

      diff < 3600 ->
        gettext("%{n}m ago", n: div(diff, 60))

      diff < 86_400 ->
        hours = div(diff, 3600)
        minutes = div(rem(diff, 3600), 60)

        if minutes > 0,
          do: gettext("%{h}h %{m}m ago", h: hours, m: minutes),
          else: gettext("%{h}h ago", h: hours)

      true ->
        days = div(diff, 86_400)
        hours = div(rem(diff, 86_400), 3600)

        if hours > 0,
          do: gettext("%{d}d %{h}h ago", d: days, h: hours),
          else: gettext("%{d}d ago", d: days)
    end
  end
end
