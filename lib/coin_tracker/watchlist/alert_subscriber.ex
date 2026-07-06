defmodule CoinTracker.Watchlist.AlertSubscriber do
  @moduledoc """
  Subscribes to `"signals:updated"` and fires Telegram alerts to users whose
  active positions are affected by top-10 transitions:

    * `false -> true` (a coin (re-)enters the top 10)
    * `true -> false` (a coin drops out)

  Alerts are one-shot per transition: state is held in memory as
  `%{symbol => in_top_boolean}` and updated after each broadcast, so the same
  transition isn't re-alerted on subsequent broadcasts that don't actually
  change the in_top status.

  Initial state is seeded from the database on `init/1` so the subscriber does
  not fire false alerts on app boot.
  """
  use GenServer
  require Logger

  alias CoinTracker.Log
  alias CoinTracker.Signals
  alias CoinTracker.TelegramClient.TelegramService
  alias CoinTracker.Trading
  alias CoinTracker.Watchlist

  @topic "signals:updated"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :subscribe?, true) do
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, @topic)
    end

    {:ok, %{state: seed_state(), telegram: Keyword.get(opts, :telegram, TelegramService)}}
  end

  @impl true
  def handle_info({:signals_updated, signals}, %{state: prev, telegram: telegram} = s) do
    new_state = build_state(signals)
    transitions = diff_transitions(prev, new_state, signals)

    Enum.each(transitions, fn transition -> dispatch_alert(transition, telegram) end)

    Log.info("watchlist.coverage ratio=#{Float.round(Watchlist.coverage_ratio(), 4)}",
      module: :watchlist,
      operation: :coverage
    )

    {:noreply, %{s | state: new_state}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp seed_state do
    Signals.list_signals(active: true)
    |> build_state()
  end

  defp build_state(signals) do
    Enum.reduce(signals, %{}, fn signal, acc ->
      Map.put(acc, signal.symbol, %{in_top: signal.in_top, position: signal.position})
    end)
  end

  defp diff_transitions(prev, new_state, signals) do
    signals
    |> Enum.flat_map(fn signal ->
      prev_entry = Map.get(prev, signal.symbol)
      new_entry = Map.get(new_state, signal.symbol)

      case classify(prev_entry, new_entry) do
        nil -> []
        kind -> [{kind, signal, prev_entry}]
      end
    end)
  end

  defp classify(nil, %{in_top: true} = _new), do: :entered
  defp classify(%{in_top: false}, %{in_top: true}), do: :entered
  defp classify(%{in_top: true}, %{in_top: false}), do: :dropped
  defp classify(_, _), do: nil

  defp dispatch_alert({:entered, signal, _prev}, telegram) do
    user_ids = Trading.list_user_ids_with_active_position_for_symbol(signal.symbol)

    if user_ids != [] do
      message = "🚀 #{signal.symbol} is in the top 10 — rank ##{signal.position}"
      telegram.broadcast_message(user_ids, message, kind: :watchlist_entered)
    end
  end

  defp dispatch_alert({:dropped, signal, prev}, telegram) do
    user_ids = Trading.list_user_ids_with_active_position_for_symbol(signal.symbol)

    if user_ids != [] do
      prev_rank = (prev && prev.position) || "?"
      message = "📉 #{signal.symbol} dropped out of the top 10 (was rank ##{prev_rank})"
      telegram.broadcast_message(user_ids, message, kind: :watchlist_dropped)
    end
  end
end
