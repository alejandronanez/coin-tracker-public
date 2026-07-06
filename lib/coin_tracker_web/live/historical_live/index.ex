defmodule CoinTrackerWeb.HistoricalLive.Index do
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Accounts.User
  alias CoinTracker.Signals

  @valid_statuses ~w(all active inactive recently_exited)
  @default_status "all"

  @impl true
  def mount(_params, _session, socket) do
    is_pro = pro_user?(socket.assigns.current_scope)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "signals:updated")
    end

    symbols = fetch_symbols(is_pro)
    active_signal_count = if is_pro, do: 0, else: Signals.count_total_active_signals()

    socket =
      socket
      |> assign(:page_title, gettext("Historical Signals"))
      |> assign(:all_symbols, symbols)
      |> assign(:is_pro, is_pro)
      |> assign(:active_signal_count, active_signal_count)
      |> stream_configure(:symbols, dom_id: &"symbol-#{&1.symbol}")

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search = params["search"] || ""
    status_filter = normalize_status(params["status"])
    filtered = apply_filters(socket.assigns.all_symbols, search, status_filter)

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:status_filter, status_filter)
     |> assign_counts(socket.assigns.all_symbols, filtered)
     |> stream(:symbols, filtered, reset: true)}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    {:noreply, push_patch(socket, to: filter_path(query, socket.assigns.status_filter))}
  end

  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply, push_patch(socket, to: filter_path(socket.assigns.search, status))}
  end

  @impl true
  def handle_info({:signals_updated, _signals}, socket) do
    symbols = fetch_symbols(socket.assigns.is_pro)
    filtered = apply_filters(symbols, socket.assigns.search, socket.assigns.status_filter)

    active_signal_count =
      if socket.assigns.is_pro, do: 0, else: Signals.count_total_active_signals()

    {:noreply,
     socket
     |> assign(:all_symbols, symbols)
     |> assign(:active_signal_count, active_signal_count)
     |> assign_counts(symbols, filtered)
     |> stream(:symbols, filtered, reset: true)}
  end

  defp filter_path(search, status) do
    params =
      %{}
      |> maybe_add_param("search", search, "")
      |> maybe_add_param("status", status, @default_status)

    if params == %{} do
      ~p"/historical"
    else
      ~p"/historical?#{params}"
    end
  end

  defp maybe_add_param(params, _key, value, value), do: params
  defp maybe_add_param(params, key, value, _default), do: Map.put(params, key, value)

  defp normalize_status(status) when status in @valid_statuses, do: status
  defp normalize_status(_), do: @default_status

  defp fetch_symbols(true), do: Signals.list_unique_symbols()
  defp fetch_symbols(false), do: Signals.list_unique_symbols_public()

  defp apply_filters(symbols, search, status) do
    symbols
    |> filter_by_search(search)
    |> filter_by_status(status)
  end

  defp filter_by_search(symbols, ""), do: symbols

  defp filter_by_search(symbols, query) do
    downcased = String.downcase(query)

    Enum.filter(symbols, fn s ->
      String.contains?(String.downcase(s.symbol), downcased) or
        String.contains?(String.downcase(s.name || ""), downcased)
    end)
  end

  defp filter_by_status(symbols, "active"), do: Enum.filter(symbols, & &1.has_active)
  defp filter_by_status(symbols, "inactive"), do: Enum.reject(symbols, & &1.has_active)

  defp filter_by_status(symbols, "recently_exited") do
    symbols
    |> Enum.filter(&recently_exited?/1)
    |> Enum.sort_by(& &1.last_exit_date, {:desc, DateTime})
  end

  defp filter_by_status(symbols, _all), do: symbols

  # A symbol belongs in "Recently Exited" only if it has no currently-active
  # signals and at least one of its signals exited within the cutoff window.
  # Otherwise `has_recently_exited` would leak still-Active symbols into the
  # Recently Exited bucket whenever one of their prior runs exited recently.
  defp recently_exited?(symbol), do: symbol.has_recently_exited and not symbol.has_active

  defp assign_counts(socket, all_symbols, filtered) do
    total_signals = Enum.reduce(filtered, 0, fn s, acc -> acc + s.occurrence_count end)
    active_count = Enum.count(all_symbols, & &1.has_active)
    inactive_count = length(all_symbols) - active_count
    recently_exited_count = Enum.count(all_symbols, &recently_exited?/1)

    socket
    |> assign(:symbol_count, length(filtered))
    |> assign(:total_signals, total_signals)
    |> assign(:active_count, active_count)
    |> assign(:inactive_count, inactive_count)
    |> assign(:recently_exited_count, recently_exited_count)
  end

  defp pro_user?(%{user: %User{} = user}), do: User.active_subscription?(user)
  defp pro_user?(_), do: false
end
