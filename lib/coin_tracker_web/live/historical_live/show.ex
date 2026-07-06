defmodule CoinTrackerWeb.HistoricalLive.Show do
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Accounts.User
  alias CoinTracker.Signals

  import CoinTrackerWeb.SignalHelpers,
    only: [
      format_price: 1,
      format_seconds: 1,
      occurrence_top_delta_text: 1,
      occurrence_top_delta_class: 1,
      sorted_position_durations: 1
    ]

  @impl true
  def mount(%{"symbol" => symbol}, _session, socket) do
    is_pro = pro_user?(socket.assigns.current_scope)

    occurrences =
      if is_pro,
        do: Signals.get_all_occurrences(symbol),
        else: Signals.get_all_occurrences_public(symbol)

    if occurrences == [] do
      {:ok,
       socket
       |> put_flash(:error, gettext("No history found for this symbol."))
       |> push_navigate(to: ~p"/historical")}
    else
      active_signal =
        if is_pro do
          Signals.list_signals(symbol: symbol, active: true) |> List.first()
        else
          nil
        end

      active_signal_count = if is_pro, do: 0, else: Signals.count_total_active_signals()

      socket =
        socket
        |> assign(:page_title, gettext("History: %{symbol}", symbol: String.upcase(symbol)))
        |> assign(:symbol, symbol)
        |> assign(:occurrence_count, length(occurrences))
        |> assign(:has_active, is_pro and not is_nil(active_signal))
        |> assign(:active_signal, active_signal)
        |> assign(:is_pro, is_pro)
        |> assign(:active_signal_count, active_signal_count)
        |> stream(:occurrences, occurrences, dom_id: &"occurrence-#{&1.signal.id}")

      {:ok, socket}
    end
  end

  defp pro_user?(%{user: %User{} = user}), do: User.active_subscription?(user)
  defp pro_user?(_), do: false
end
