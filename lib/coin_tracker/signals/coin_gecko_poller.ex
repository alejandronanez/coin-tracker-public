defmodule CoinTracker.Signals.CoinGeckoPoller do
  @moduledoc """
  GenServer that maintains the `coingecko_snapshots` table and an in-memory
  `symbol → coingecko_id` cache.

  On each tick (default: every 15 minutes), the poller:

    1. Calls `CoinGeckoApiClient.fetch_top_500/0` to get the current top-500
       coins by market cap, paged twice (per_page=250).
    2. Inserts a snapshot row per coin at `now` (truncated to seconds) using
       `Repo.insert_all/3` with `on_conflict: :nothing` against the
       `(coingecko_id, snapshot_at)` unique index — idempotent if the same
       tick somehow runs twice.
    3. Replaces the in-memory symbol cache with `%{upcased_symbol => coingecko_id}`,
       built by first-match-wins in the market-cap-ordered response.
    4. Prunes snapshot rows older than 48 hours inline.

  On HTTP / network failure (429, transport error, etc.) the poller:

    - Logs the failure.
    - **Retains** the previous symbol cache so ingestion stays stamped.
    - Does not crash. The next tick will try again.

  ## Configuration

      config :coin_tracker, CoinTracker.Signals.CoinGeckoPoller,
        enabled: true,
        interval: :timer.minutes(15)

  Test env disables it (`enabled: false`) and the suite drives polls
  manually with `poll_now/1`.

  ## Reading the cache

  `lookup_coingecko_id/1` (registered-name form) and `lookup_coingecko_id/2`
  (pid form, for tests) are case-insensitive and return `nil` for unknown
  symbols — including the case where the cache hasn't been populated yet
  (process not running, first poll hasn't finished, etc.).
  """

  use GenServer
  require Logger

  alias CoinTracker.Log
  alias CoinTracker.Repo
  alias CoinTracker.Signals
  alias CoinTracker.Signals.{CoinGeckoApiClient, CoingeckoSnapshot, HTTPClient}

  @default_interval :timer.minutes(15)
  @prune_after_hours 48

  # Client API

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Triggers a synchronous poll cycle. Returns `{:ok, inserted_count}` or
  `{:error, reason}` from `CoinGeckoApiClient.fetch_top_500/0`.
  """
  def poll_now(server \\ __MODULE__) do
    GenServer.call(server, :poll_now, :infinity)
  end

  @doc """
  Returns the `coingecko_id` for `symbol`, or `nil` if not in the cache.

  Case-insensitive on `symbol`. Returns `nil` if the poller process is not
  running (defensive — ingestion calls this and must not crash if the
  poller is disabled in tests).
  """
  def lookup_coingecko_id(server \\ __MODULE__, symbol) when is_binary(symbol) do
    case lookup_pid(server) do
      nil -> nil
      pid -> GenServer.call(pid, {:lookup, String.upcase(symbol)})
    end
  end

  # Server callbacks

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, config(:enabled, true))
    interval = Keyword.get(opts, :interval, config(:interval, @default_interval))
    http_client = Keyword.get(opts, :http_client, HTTPClient.ReqAdapter)
    now_fn = Keyword.get(opts, :now_fn, &default_now/0)

    state = %{
      enabled: enabled,
      interval: interval,
      http_client: http_client,
      now_fn: now_fn,
      symbol_map: %{}
    }

    if enabled do
      Log.info("CoinGeckoPoller starting (interval: #{interval}ms)",
        module: :coingecko_poller,
        operation: :init
      )

      Process.send_after(self(), :tick, interval)
    else
      Log.info("CoinGeckoPoller disabled via configuration",
        module: :coingecko_poller,
        operation: :init
      )
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:poll_now, _from, state) do
    {result, new_state} = perform_poll(state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:lookup, symbol}, _from, state) do
    {:reply, Map.get(state.symbol_map, symbol), state}
  end

  @impl true
  def handle_info(:tick, state) do
    {_result, new_state} = perform_poll(state)
    Process.send_after(self(), :tick, state.interval)
    {:noreply, new_state}
  end

  # Private

  defp perform_poll(state) do
    case CoinGeckoApiClient.fetch_top_500(http_client: state.http_client) do
      {:ok, rows} ->
        inserted = insert_snapshots(rows, state.now_fn.())
        symbol_map = build_symbol_map(rows)
        prune_old_snapshots(state.now_fn.())

        Log.info("CoinGeckoPoller cycle complete: #{inserted} new snapshots",
          module: :coingecko_poller,
          operation: :poll
        )

        # Push the freshly-enriched signal set out to subscribed LiveViews so
        # the "24h Market" column updates without a page refresh.
        Signals.broadcast_active_signals()

        {{:ok, inserted}, %{state | symbol_map: symbol_map}}

      {:error, reason} = error ->
        Log.api_error("CoinGeckoPoller cycle failed; retaining prior symbol cache",
          module: :coingecko_poller,
          operation: :poll,
          reason: inspect(reason)
        )

        {error, state}
    end
  end

  defp insert_snapshots([], _now), do: 0

  defp insert_snapshots(rows, now) do
    now = DateTime.truncate(now, :second)

    entries =
      Enum.map(rows, fn row ->
        %{
          coingecko_id: row.coingecko_id,
          symbol: row.symbol,
          snapshot_at: now,
          total_volume_usd: row.total_volume_usd,
          price_usd: row.price_usd,
          price_change_percentage_24h: row.price_change_percentage_24h,
          market_cap_usd: row.market_cap_usd,
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} =
      Repo.insert_all(CoingeckoSnapshot, entries,
        on_conflict: :nothing,
        conflict_target: [:coingecko_id, :snapshot_at]
      )

    count
  end

  defp build_symbol_map(rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      Map.put_new(acc, row.symbol, row.coingecko_id)
    end)
  end

  defp prune_old_snapshots(now) do
    cutoff = DateTime.add(now, -@prune_after_hours, :hour)
    Signals.prune_coingecko_snapshots(cutoff)
  end

  defp lookup_pid(name) when is_atom(name) do
    Process.whereis(name)
  end

  defp lookup_pid(pid) when is_pid(pid), do: pid

  defp default_now, do: DateTime.utc_now()

  defp config(key, default) do
    Application.get_env(:coin_tracker, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
