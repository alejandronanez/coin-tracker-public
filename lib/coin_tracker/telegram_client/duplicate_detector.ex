defmodule CoinTracker.TelegramClient.DuplicateDetector do
  @moduledoc """
  In-memory duplicate-notification detector for Telegram sends.

  This is a debugging aid. It does **not** suppress duplicates — it only
  surfaces them by emitting a `Log.warn` when the same `(user_id, fingerprint)`
  pair is observed within a configurable window. Pair this with the
  `fingerprint` and `dispatch_id` metadata logged by
  `CoinTracker.TelegramClient.TelegramService` to disambiguate:

    * Same fingerprint, **same** dispatch_id appearing twice → wire-level /
      retry duplicate (case A — we sent once, it landed twice).
    * Same fingerprint, **different** dispatch_id → two independent source
      generations (case B — two code paths each produced and sent the alert).

  ## Storage

  Backed by a public ETS table keyed by `{user_id, fingerprint}` with value
  `{last_seen_at_unix, last_dispatch_id}`. A periodic sweep evicts entries
  older than `window_seconds * 2`.

  ## Configuration

      config :coin_tracker, CoinTracker.TelegramClient.DuplicateDetector,
        window_seconds: 60,
        sweep_interval: :timer.minutes(1)
  """
  use GenServer

  alias CoinTracker.Log

  @table :coin_tracker_telegram_dedup
  @default_window_seconds 60
  @default_sweep_interval :timer.minutes(1)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Records an observation of a Telegram send and emits a warning if the same
  `(user_id, fingerprint)` pair was seen within the configured window.

  Always returns `:ok`. Never blocks the send.
  """
  def observe(user_id, fingerprint, dispatch_id, kind, table \\ @table)
      when is_integer(user_id) and is_binary(fingerprint) and is_binary(dispatch_id) do
    now = System.system_time(:second)
    key = {user_id, fingerprint}
    window = window_seconds()

    case safe_lookup(table, key) do
      [{^key, prev_seen_at, prev_dispatch_id}] when now - prev_seen_at <= window ->
        Log.warn(
          "duplicate telegram fingerprint within #{window}s " <>
            "(prev_dispatch_id=#{prev_dispatch_id})",
          :telegram_error,
          user_id: user_id,
          fingerprint: fingerprint,
          dispatch_id: dispatch_id,
          notification_kind: kind
        )

      _ ->
        :ok
    end

    safe_insert(table, {key, now, dispatch_id})
    :ok
  end

  # Server callbacks

  @impl true
  def init(opts) do
    table_name = Keyword.get(opts, :table, @table)

    table =
      :ets.new(table_name, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    sweep_interval = Keyword.get(opts, :sweep_interval, sweep_interval())
    schedule_sweep(sweep_interval)

    {:ok, %{table: table, sweep_interval: sweep_interval}}
  end

  @impl true
  def handle_info(:sweep, %{table: table, sweep_interval: interval} = state) do
    sweep(table)
    schedule_sweep(interval)
    {:noreply, state}
  end

  defp sweep(table) do
    cutoff = System.system_time(:second) - window_seconds() * 2

    # Delete entries where last_seen_at is older than cutoff.
    # Match spec: {key, seen_at, dispatch_id} where seen_at < cutoff.
    match_spec = [{{:"$1", :"$2", :"$3"}, [{:<, :"$2", cutoff}], [true]}]
    :ets.select_delete(table, match_spec)
  end

  defp schedule_sweep(interval) do
    Process.send_after(self(), :sweep, interval)
  end

  defp safe_lookup(table, key) do
    :ets.lookup(table, key)
  rescue
    ArgumentError -> []
  end

  defp safe_insert(table, tuple) do
    :ets.insert(table, tuple)
  rescue
    ArgumentError -> false
  end

  defp window_seconds do
    Application.get_env(:coin_tracker, __MODULE__, [])
    |> Keyword.get(:window_seconds, @default_window_seconds)
  end

  defp sweep_interval do
    Application.get_env(:coin_tracker, __MODULE__, [])
    |> Keyword.get(:sweep_interval, @default_sweep_interval)
  end
end
