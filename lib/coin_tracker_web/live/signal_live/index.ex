defmodule CoinTrackerWeb.SignalLive.Index do
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Accounts.User
  alias CoinTracker.Signals
  alias CoinTracker.Trading
  alias CoinTracker.Watchlist

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to PubSub topics for real-time updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "signals:updated")
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "price_updates")
    end

    socket =
      socket
      |> assign(:page_title, gettext("Signals"))
      |> assign(:dev_mode?, Application.get_env(:coin_tracker, :dev_routes, false))
      |> assign(:watchlist_enabled?, watchlist_enabled?(socket))
      |> load_watched_state()

    {:ok, socket}
  end

  defp watchlist_enabled?(socket) do
    case socket.assigns[:current_scope] do
      %{user: %User{}} -> true
      _ -> false
    end
  end

  defp load_watched_state(socket) do
    user = socket.assigns[:current_scope] && socket.assigns.current_scope.user

    if socket.assigns.watchlist_enabled? && user do
      symbols = Trading.watched_base_symbols_for_user(user.id)

      socket
      |> assign(:watched_symbols, symbols)
      |> assign(:watched_count, MapSet.size(symbols))
      |> assign(:watched_entries, list_watched_entries(user))
    else
      socket
      |> assign(:watched_symbols, MapSet.new())
      |> assign(:watched_count, 0)
      |> assign(:watched_entries, [])
    end
  end

  defp list_watched_entries(user) do
    user.id
    |> Trading.list_watched_positions_for_user()
    |> Watchlist.enrich()
  end

  @impl true
  def handle_params(params, _uri, socket) do
    sort_by = params["top"] || "position_asc"
    grace_sort_by = params["gp"] || "time_remaining"
    tab = if params["tab"] == "watched", do: "watched", else: "top"

    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:grace_sort_by, grace_sort_by)
     |> assign(:tab, tab)
     |> load_signals()}
  end

  @impl true
  def handle_event("manual_poll", _params, socket) do
    # Delete all existing signals before manual poll
    Signals.delete_all_signals()

    # Trigger manual poll via the poller
    CoinTracker.Signals.Poller.poll_now()

    {:noreply,
     socket
     |> load_signals()
     |> put_flash(
       :info,
       gettext("Cleared signals and triggered manual poll! Data will update shortly.")
     )}
  end

  @impl true
  def handle_event("change_sort", %{"sort_by" => sort_by}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/signals?#{build_query_params(sort_by, socket.assigns.grace_sort_by, socket.assigns.tab)}"
     )}
  end

  @impl true
  def handle_event("change_grace_sort", %{"grace_sort_by" => grace_sort_by}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/signals?#{build_query_params(socket.assigns.sort_by, grace_sort_by, socket.assigns.tab)}"
     )}
  end

  @impl true
  def handle_event("toggle_watch", %{"signal-id" => signal_id}, socket) do
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    cond do
      not socket.assigns.watchlist_enabled? ->
        {:noreply, socket}

      is_nil(user) ->
        {:noreply, socket}

      true ->
        toggle_watch(socket, user, signal_id)
    end
  end

  @impl true
  def handle_event("unwatch_position", %{"position-id" => position_id}, socket) do
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    cond do
      not socket.assigns.watchlist_enabled? ->
        {:noreply, socket}

      is_nil(user) ->
        {:noreply, socket}

      true ->
        case Trading.unwatch_position_for_user(user.id, position_id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> load_watched_state()
             |> put_flash(:info, gettext("Watch removed"))}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, gettext("Watch not found"))}
        end
    end
  end

  defp toggle_watch(socket, user, signal_id) do
    case Signals.get_signal_with_price(signal_id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Signal not found"))}

      signal ->
        base_symbol = base_symbol_for_signal(signal)

        if base_symbol && MapSet.member?(socket.assigns.watched_symbols, base_symbol) do
          unwatch_signal(socket, user, signal, base_symbol)
        else
          watch_signal(socket, user, signal)
        end
    end
  end

  defp watch_signal(socket, user, signal) do
    case Trading.watch_signal(user.id, signal) do
      {:ok, _position} ->
        {:noreply,
         socket
         |> load_watched_state()
         |> put_flash(
           :info,
           gettext("Watching %{symbol}", symbol: String.upcase(signal.symbol))
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not start watching this signal"))}
    end
  end

  defp unwatch_signal(socket, user, signal, _base_symbol) do
    case Trading.unwatch_signal(user.id, signal) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_watched_state()
         |> put_flash(
           :info,
           gettext("Stopped watching %{symbol}", symbol: String.upcase(signal.symbol))
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not stop watching this signal"))}
    end
  end

  defp base_symbol_for_signal(%{symbol_price: %{symbol_pair: pair}}),
    do: Watchlist.base_symbol(pair)

  defp base_symbol_for_signal(_), do: nil

  @impl true
  def handle_info({:signals_updated, signals}, socket) do
    sort_by = socket.assigns.sort_by
    grace_sort_by = socket.assigns.grace_sort_by

    top_performers =
      signals
      |> Enum.filter(& &1.in_top)
      |> sort_top_performers(sort_by)

    grace_period =
      signals
      |> Enum.filter(&(!&1.in_top))
      |> sort_grace_period(grace_sort_by)

    {:noreply,
     socket
     |> assign(:signals, signals)
     |> assign(:top_performers, top_performers)
     |> assign(:grace_period, grace_period)
     |> assign(:empty?, signals == [])
     |> assign(:sort_by, sort_by)
     |> assign(:grace_sort_by, grace_sort_by)
     |> load_watched_state()}
  end

  @impl true
  def handle_info({:price_updated, symbol_price}, socket) do
    # Update signals that match this symbol_price
    updated_signals =
      Enum.map(socket.assigns.signals, fn signal ->
        if signal.symbol_price_id == symbol_price.id do
          %{signal | symbol_price: symbol_price}
        else
          signal
        end
      end)

    # Re-sort and re-assign
    sort_by = socket.assigns.sort_by
    grace_sort_by = socket.assigns.grace_sort_by

    top_performers =
      updated_signals
      |> Enum.filter(& &1.in_top)
      |> sort_top_performers(sort_by)

    grace_period =
      updated_signals
      |> Enum.filter(&(!&1.in_top))
      |> sort_grace_period(grace_sort_by)

    {:noreply,
     socket
     |> assign(:signals, updated_signals)
     |> assign(:top_performers, top_performers)
     |> assign(:grace_period, grace_period)}
  end

  defp load_signals(socket) do
    signals = Signals.list_signals_with_prices(active: true)

    sort_by = Map.get(socket.assigns, :sort_by, "position_asc")
    grace_sort_by = Map.get(socket.assigns, :grace_sort_by, "time_remaining")

    top_performers =
      signals
      |> Enum.filter(& &1.in_top)
      |> sort_top_performers(sort_by)

    grace_period =
      signals
      |> Enum.filter(&(!&1.in_top))
      |> sort_grace_period(grace_sort_by)

    socket
    |> assign(:signals, signals)
    |> assign(:top_performers, top_performers)
    |> assign(:grace_period, grace_period)
    |> assign(:empty?, signals == [])
  end

  defp sort_top_performers(list, "position_asc") do
    Enum.sort_by(list, & &1.position, :asc)
  end

  defp sort_top_performers(list, "newest_first") do
    Enum.sort_by(list, & &1.in_top_since, {:desc, DateTime})
  end

  defp sort_top_performers(list, "volume_change") do
    alias CoinTracker.Signals.Signal

    Enum.sort_by(
      list,
      fn signal ->
        signal
        |> Signal.volume_increase_percentage()
        |> Decimal.to_float()
      end,
      :desc
    )
  end

  defp sort_top_performers(list, "volume_change_24h_desc") do
    # Sort by the CoinGecko-sourced 24h volume change. Nil values sort to the
    # bottom by treating them as -infinity.
    Enum.sort_by(
      list,
      fn
        %{cg_volume_change_24h_pct: nil} -> :nil_sentinel
        %{cg_volume_change_24h_pct: %Decimal{} = d} -> Decimal.to_float(d)
        _ -> :nil_sentinel
      end,
      &compare_volume_24h_desc/2
    )
  end

  # Sort values come from URL params, so fall back to the default rather than
  # crashing the LiveView on an unknown value.
  defp sort_top_performers(list, _unknown), do: sort_top_performers(list, "position_asc")

  defp compare_volume_24h_desc(:nil_sentinel, :nil_sentinel), do: true
  defp compare_volume_24h_desc(:nil_sentinel, _), do: false
  defp compare_volume_24h_desc(_, :nil_sentinel), do: true
  defp compare_volume_24h_desc(a, b), do: a >= b

  defp sort_grace_period(list, "time_remaining") do
    Enum.sort_by(
      list,
      fn signal ->
        exit_date = signal.exit_date || DateTime.utc_now()
        removal_date = DateTime.add(exit_date, 24, :hour)
        DateTime.diff(removal_date, DateTime.utc_now())
      end,
      :desc
    )
  end

  defp sort_grace_period(list, "listed_since") do
    Enum.sort_by(list, & &1.in_top_since, {:desc, DateTime})
  end

  defp sort_grace_period(list, "coin_name") do
    Enum.sort_by(list, & &1.name, :asc)
  end

  defp sort_grace_period(list, _unknown), do: sort_grace_period(list, "time_remaining")

  defp build_query_params(sort_by, grace_sort_by, tab) do
    %{}
    |> maybe_add_param("top", sort_by, "position_asc")
    |> maybe_add_param("gp", grace_sort_by, "time_remaining")
    |> maybe_add_param("tab", tab, "top")
  end

  defp maybe_add_param(params, _key, value, value), do: params
  defp maybe_add_param(params, key, value, _default), do: Map.put(params, key, value)

  # Compact one-line variant for mobile cards: "24h: vol +X% · px +Y%".
  attr :volume_change_pct, :any, default: nil
  attr :price_change_pct, :any, default: nil

  def cg_market_24h_inline(assigns) do
    assigns =
      assigns
      |> assign(:volume_float, to_float_or_nil(assigns.volume_change_pct))
      |> assign(:price_float, to_float_or_nil(assigns.price_change_pct))

    ~H"""
    <span class="inline-flex items-center gap-1 font-mono">
      <span class="text-zinc-400 dark:text-zinc-500">{gettext("24h:")}</span>
      <span class={line_color_class(@volume_float)}>vol {format_pct(@volume_float)}</span>
      <span class="text-zinc-300 dark:text-zinc-600">·</span>
      <span class={line_color_class(@price_float)}>px {format_pct(@price_float)}</span>
    </span>
    """
  end

  # 24h Market cell: two stacked lines, one for CoinGecko-sourced 24h volume
  # change and one for 24h price change. Each line is independently colored —
  # the user reads the pair as a Wyckoff matrix (vol up + price down →
  # distribution, etc).
  attr :volume_change_pct, :any, default: nil
  attr :price_change_pct, :any, default: nil

  def cg_market_24h_cell(assigns) do
    assigns =
      assigns
      |> assign(:volume_float, to_float_or_nil(assigns.volume_change_pct))
      |> assign(:price_float, to_float_or_nil(assigns.price_change_pct))

    ~H"""
    <div class="flex flex-col items-end gap-0.5">
      <span class={[
        "font-mono tabular-nums",
        line_color_class(@volume_float)
      ]}>
        {gettext("Vol")} {format_pct(@volume_float)}
      </span>
      <span class={[
        "font-mono tabular-nums",
        line_color_class(@price_float)
      ]}>
        {gettext("Price")} {format_pct(@price_float)}
      </span>
    </div>
    """
  end

  defp to_float_or_nil(nil), do: nil
  defp to_float_or_nil(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float_or_nil(n) when is_number(n), do: n * 1.0

  defp line_color_class(nil), do: "text-zinc-400 dark:text-zinc-500"
  defp line_color_class(value) when value >= 0, do: "text-green-600 dark:text-green-400"
  defp line_color_class(_), do: "text-red-600 dark:text-red-400"

  # 4-tier scale so a +143% surge does not render identically to a flat +1%.
  defp vol_since_signal_tier_class(nil), do: "text-zinc-400 dark:text-zinc-500"
  defp vol_since_signal_tier_class(v) when v < 0, do: "text-amber-600 dark:text-amber-400"
  defp vol_since_signal_tier_class(v) when v < 20, do: "text-zinc-600 dark:text-zinc-300"

  defp vol_since_signal_tier_class(v) when v < 100,
    do: "text-green-600 dark:text-green-400 font-medium"

  defp vol_since_signal_tier_class(_), do: "text-emerald-600 dark:text-emerald-400 font-semibold"

  # Color-independent direction cue for colorblind users.
  defp vol_since_signal_trend_icon(v) when is_number(v) and v < 0, do: "hero-arrow-trending-down"
  defp vol_since_signal_trend_icon(_), do: "hero-arrow-trending-up"

  defp format_pct(nil), do: "—"

  defp format_pct(value) when is_float(value) do
    sign = if value >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(value, decimals: 1)}%"
  end
end
