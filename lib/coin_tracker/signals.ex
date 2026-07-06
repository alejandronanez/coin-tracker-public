defmodule CoinTracker.Signals do
  @moduledoc """
  The Signals context for managing cryptocurrency signals from CoinScanX API.

  This context provides functions to:
  - Ingest signals from the CoinScanX API (both top 10 and grace period)
  - Query signals from the database
  - Track signal evolution over time

  ## Ingestion Strategy

  When signals are ingested from the API, the system uses an upsert strategy:
  - **Immutable fields**: `symbol`, `in_top_since`, `initial_volume_24h`, `initial_price_usd`
    These capture the initial state when a signal first enters the top 10
  - **Mutable fields**: `current_volume_24h`, `current_price_usd`, `max_price_usd`,
    `max_increase_percentage`, `in_top`, `active`, `exit_date`
    These are updated on each ingestion to track evolution

  ## Examples

      # Manually trigger data ingestion
      iex> CoinTracker.Signals.ingest_all()
      {:ok, %{top_10: 10, grace_period: 5}}

      # Query active signals
      iex> CoinTracker.Signals.list_signals(active: true, in_top: true)
      [%Signal{...}, ...]
  """

  import Ecto.Query, warn: false
  alias CoinTracker.Accounts
  alias CoinTracker.Log
  alias CoinTracker.Repo

  alias CoinTracker.Signals.{
    CoinGeckoPoller,
    CoingeckoSnapshot,
    CoinscanApiClient,
    MarketStatus,
    Signal,
    SignalSnapshot
  }

  alias CoinTracker.TelegramClient.TelegramService

  @doc """
  Fetches and ingests the top 10 signals from the CoinScanX API.

  Returns `{:ok, count}` with the number of signals processed, or `{:error, reason}`.

  ## Examples

      iex> ingest_top_10()
      {:ok, 10}

      iex> ingest_top_10()
      {:error, :network_error}
  """
  def ingest_top_10 do
    Log.info("Starting ingestion of top 10 signals",
      module: :signals,
      operation: :ingest_top_10
    )

    case CoinscanApiClient.fetch_top_10() do
      {:ok, signals} ->
        {:ok, ingest_prefetched_top_10(signals)}

      {:error, reason} = error ->
        Log.api_error("Failed to ingest top 10 signals",
          module: :signals,
          operation: :ingest_top_10,
          reason: inspect(reason)
        )

        error
    end
  end

  @doc """
  Upserts an already-fetched list of top 10 signals.

  Useful when the caller fetched the data itself (e.g. the Poller deduplicates
  identical responses before deciding whether to ingest) and wants to avoid a
  redundant HTTP call inside `ingest_top_10/0`.

  Returns the number of signals processed.
  """
  def ingest_prefetched_top_10(signals) when is_list(signals) do
    count = upsert_signals(signals)

    Log.info("Successfully ingested #{count} top 10 signals",
      module: :signals,
      operation: :ingest_prefetched_top_10
    )

    count
  end

  @doc """
  Fetches and ingests grace period signals from the CoinScanX API.

  Returns `{:ok, count}` with the number of signals processed, or `{:error, reason}`.

  ## Examples

      iex> ingest_grace_period()
      {:ok, 5}

      iex> ingest_grace_period()
      {:error, :network_error}
  """
  def ingest_grace_period do
    Log.info("Starting ingestion of grace period signals",
      module: :signals,
      operation: :ingest_grace_period
    )

    case CoinscanApiClient.fetch_grace_period() do
      {:ok, signals} ->
        count = upsert_signals(signals)

        Log.info("Successfully ingested #{count} grace period signals",
          module: :signals,
          operation: :ingest_grace_period
        )

        {:ok, count}

      {:error, reason} = error ->
        Log.api_error("Failed to ingest grace period signals",
          module: :signals,
          operation: :ingest_grace_period,
          reason: inspect(reason)
        )

        error
    end
  end

  @doc """
  Fetches and ingests both top 10 and grace period signals.

  Returns `{:ok, %{top_10: count, grace_period: count}}` or `{:error, reason}`.

  If one ingestion succeeds and the other fails, returns the partial success
  along with the error.

  ## Examples

      iex> ingest_all()
      {:ok, %{top_10: 10, grace_period: 5}}

      iex> ingest_all()
      {:error, %{top_10: {:error, :network_error}, grace_period: {:ok, 5}}}
  """
  def ingest_all do
    Log.info("Starting full ingestion of all signals",
      module: :signals,
      operation: :ingest_all
    )

    top_10_result = ingest_top_10()
    grace_period_result = ingest_grace_period()

    result =
      case {top_10_result, grace_period_result} do
        {{:ok, top_10_count}, {:ok, grace_period_count}} ->
          {:ok, %{top_10: top_10_count, grace_period: grace_period_count}}

        {{:error, _}, {:error, _}} = errors ->
          Log.api_error("Both ingestion attempts failed",
            module: :signals,
            operation: :ingest_all,
            reason: inspect(errors)
          )

          {:error, %{top_10: top_10_result, grace_period: grace_period_result}}

        _ ->
          Log.warn("Partial ingestion success", :api_error,
            module: :signals,
            operation: :ingest_all
          )

          {:error, %{top_10: top_10_result, grace_period: grace_period_result}}
      end

    # Broadcast update to all subscribed LiveViews with the actual signals
    case result do
      {:ok, _counts} -> broadcast_active_signals()
      _ -> :ok
    end

    result
  end

  @doc """
  Broadcasts the current set of active signals on the `signals:updated` topic.

  Public so orchestrators (like the Poller and CoinGeckoPoller) that bypass
  `ingest_all/0` can still notify subscribed LiveViews after a successful
  ingestion cycle.

  Uses `list_signals_with_prices/1` so the broadcast payload includes the
  CoinGecko enrichment (`cg_price_change_24h_pct`, `cg_volume_change_24h_pct`).
  The LiveView's `handle_info({:signals_updated, _})` consumes the payload
  directly, so without enrichment the 24h Market column would never refresh.
  """
  def broadcast_active_signals do
    list_signals_with_prices(active: true)
    |> broadcast_signals_updated()

    :ok
  end

  @doc """
  Lists signals with optional filters.

  ## Options

    * `:active` - Filter by active status (true/false)
    * `:in_top` - Filter by in_top status (true/false)
    * `:symbol` - Filter by symbol (string)
    * `:order_by` - Order results (default: `[desc: :in_top_since]`)
    * `:limit` - Limit number of results

  ## Examples

      iex> list_signals(active: true, in_top: true)
      [%Signal{...}, ...]

      iex> list_signals(symbol: "BTC")
      [%Signal{...}]

      iex> list_signals(active: true, order_by: [desc: :max_increase_percentage], limit: 10)
      [%Signal{...}, ...]
  """
  def list_signals(opts \\ []) do
    Signal
    |> apply_filters(opts)
    |> apply_order(opts)
    |> apply_limit(opts)
    |> Repo.all()
  end

  @doc """
  Gets a single signal by ID.

  Returns the signal or `nil` if not found.

  ## Examples

      iex> get_signal(123)
      %Signal{...}

      iex> get_signal(456)
      nil
  """
  def get_signal(id) do
    Repo.get(Signal, id)
  end

  @doc """
  Gets a signal by ID with `:symbol_price` preloaded. Used by the detail page
  to render live-price-driven performance metrics.
  """
  def get_signal_with_price(id) do
    Signal
    |> preload(:symbol_price)
    |> Repo.get(id)
  end

  @doc """
  Finds a signal that was active for the given symbol at a specific datetime.

  A signal is considered "active" at a given time if:
  - It entered the top 10 (`in_top_since`) before or at that time
  - It either hasn't exited (`exit_date` is nil) or exited after that time

  ## Parameters

  - `symbol` - Plain symbol format like "ETH" (not "ETH/USDT")
  - `datetime` - The point in time to check

  ## Returns

  - `%Signal{}` if a matching signal was active at that time
  - `nil` if no signal was active

  ## Examples

      iex> find_signal_at_time("ETH", ~U[2024-01-15 10:00:00Z])
      %Signal{symbol: "ETH", in_top_since: ~U[2024-01-10 08:00:00Z], ...}

      iex> find_signal_at_time("UNKNOWN", ~U[2024-01-15 10:00:00Z])
      nil
  """
  def find_signal_at_time(symbol, datetime) do
    from(s in Signal,
      where: s.symbol == ^symbol,
      where: s.in_top_since <= ^datetime,
      where: is_nil(s.exit_date) or s.exit_date >= ^datetime,
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Returns the most recent active signal for the given base symbol, or `nil`.

  An active signal is either currently in the top 10 (`in_top: true`) or in the
  24h grace period after dropping out (`in_top: false, active: true`). Symbols
  that have never appeared, or whose grace period has expired, return `nil`.

  Used by the watchlist to enrich active positions with current signal context.

  ## Parameters

  - `symbol` - Base symbol like "ETH" (not "ETH/USDT"). Case-insensitive.

  ## Examples

      iex> current_signal_for("ETH")
      %Signal{symbol: "ETH", in_top: true, position: 3, ...}

      iex> current_signal_for("UNKNOWN")
      nil
  """
  def current_signal_for(symbol) when is_binary(symbol) do
    base = String.upcase(symbol)

    from(s in Signal,
      where: s.symbol == ^base and s.active == true,
      order_by: [desc: s.in_top_since],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Returns the most recent active signal for each of the given base symbols, as a
  map of `symbol => %Signal{}`. Symbols with no current signal are omitted.

  Batched alternative to calling `current_signal_for/1` per symbol — preferred
  when enriching a list of positions.
  """
  def current_signals_for(symbols) when is_list(symbols) do
    upcased = Enum.map(symbols, &String.upcase/1)

    from(s in Signal,
      where: s.symbol in ^upcased and s.active == true,
      order_by: [desc: s.in_top_since]
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn signal, acc -> Map.put_new(acc, signal.symbol, signal) end)
  end

  @doc """
  Returns the most recent signal for each of the given base symbols regardless
  of `active`, as a map of `symbol => %Signal{}`. Symbols with no signal record
  at all are omitted.

  Use this when callers need to distinguish "never tracked" from "tracked, then
  grace period ended" — `current_signals_for/1` collapses both into a missing
  key because deactivated signals are filtered out.
  """
  def latest_signals_for(symbols) when is_list(symbols) do
    upcased = Enum.map(symbols, &String.upcase/1)

    from(s in Signal,
      where: s.symbol in ^upcased,
      order_by: [desc: s.in_top_since]
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn signal, acc -> Map.put_new(acc, signal.symbol, signal) end)
  end

  @doc """
  Deletes all signals from the database.

  This is primarily used for development/testing purposes.

  Returns `{:ok, count}` where count is the number of deleted records.

  ## Examples

      iex> delete_all_signals()
      {:ok, 15}
  """
  def delete_all_signals do
    {count, _} = Repo.delete_all(Signal)

    Log.info("Deleted #{count} signals from database",
      module: :signals,
      operation: :delete_all
    )

    {:ok, count}
  end

  @doc """
  Deactivates signals whose exit_date is older than 24 hours.

  This function marks signals as inactive when they have been out of the
  top 10 for more than 24 hours (grace period has expired).

  Returns `{:ok, count}` with the number of signals deactivated.

  ## Examples

      iex> deactivate_expired_signals()
      {:ok, 3}
  """
  def deactivate_expired_signals do
    cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)

    {count, _} =
      from(s in Signal,
        where: s.active == true and not is_nil(s.exit_date),
        where: s.exit_date < ^cutoff
      )
      |> Repo.update_all(set: [active: false])

    if count > 0 do
      Log.info("Deactivated #{count} expired signals",
        module: :signals,
        operation: :deactivate_expired
      )
    end

    {:ok, count}
  end

  # Private functions

  defp upsert_signals(signals) when is_list(signals) do
    Enum.reduce(signals, 0, fn signal_struct, count ->
      case upsert_signal(signal_struct) do
        {:ok, _signal} ->
          count + 1

        {:error, changeset} ->
          Log.db_error("Failed to upsert signal",
            module: :signals,
            operation: :upsert_signal,
            symbol: signal_struct.symbol,
            reason: inspect(changeset.errors)
          )

          count
      end
    end)
  end

  defp upsert_signal(%Signal{} = signal_struct) do
    # Convert struct to map for changeset
    attrs =
      signal_struct
      |> Map.from_struct()
      |> Map.put(:coingecko_id, CoinGeckoPoller.lookup_coingecko_id(signal_struct.symbol))

    changeset = Signal.changeset(%Signal{}, attrs)

    # Define which fields can be updated on conflict
    # Immutable: symbol, in_top_since, initial_volume_24h, initial_price_usd
    # Mutable: name, current_volume_24h, current_price_usd,
    #          max_price_usd, max_increase_percentage, in_top, active, exit_date, position
    #
    # `coingecko_id` is also conditionally mutable — we set it from EXCLUDED only
    # when EXCLUDED has a value, so a cold-cache tick (lookup returns nil) never
    # clobbers a previously-stamped id.

    # Build update query using from/update syntax
    # This allows us to reference EXCLUDED (the conflicting row)
    update_query =
      from(s in Signal,
        update: [
          set: [
            name: fragment("EXCLUDED.name"),
            # Refresh volume whenever the API gives us a value. The grace-period
            # endpoint now returns `volumen24h`, so we no longer need to gate
            # this on `in_top`. COALESCE preserves the existing value when the
            # parser produced `nil` (API omitted the field), so a transient
            # upstream regression can't clobber good data.
            current_volume_24h:
              fragment(
                "COALESCE(EXCLUDED.current_volume_24h, ?.current_volume_24h)",
                s
              ),
            current_price_usd: fragment("EXCLUDED.current_price_usd"),
            max_price_usd: fragment("EXCLUDED.max_price_usd"),
            max_increase_percentage: fragment("EXCLUDED.max_increase_percentage"),
            in_top: fragment("EXCLUDED.in_top"),
            active: fragment("EXCLUDED.active"),
            exit_date: fragment("EXCLUDED.exit_date"),
            position: fragment("EXCLUDED.position"),
            coingecko_id:
              fragment(
                "COALESCE(EXCLUDED.coingecko_id, ?.coingecko_id)",
                s
              ),
            updated_at: fragment("NOW()")
          ]
        ]
      )

    Repo.insert(changeset,
      on_conflict: update_query,
      conflict_target: [:symbol, :in_top_since]
    )
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:active, value}, q when is_boolean(value) ->
        where(q, [s], s.active == ^value)

      {:in_top, value}, q when is_boolean(value) ->
        where(q, [s], s.in_top == ^value)

      {:symbol, value}, q when is_binary(value) ->
        where(q, [s], s.symbol == ^value)

      _other, q ->
        q
    end)
  end

  defp apply_order(query, opts) do
    case Keyword.get(opts, :order_by) do
      nil -> order_by(query, [s], asc_nulls_last: s.position)
      order -> order_by(query, ^order)
    end
  end

  defp apply_limit(query, opts) do
    case Keyword.get(opts, :limit) do
      nil -> query
      limit -> limit(query, ^limit)
    end
  end

  @doc """
  Creates snapshots for all active signals.

  Returns `{:ok, count}` with the number of snapshots created.

  ## Examples

      iex> create_snapshots()
      {:ok, 5}
  """
  def create_snapshots do
    signals = list_signals_with_prices(active: true)

    results = Enum.map(signals, &create_snapshot_for_signal/1)
    created_count = Enum.count(results, fn result -> match?({:ok, _}, result) end)

    Log.info("Created #{created_count} snapshots for #{length(signals)} active signals",
      module: :signals,
      operation: :create_snapshots
    )

    {:ok, created_count}
  end

  @doc """
  Creates a snapshot for the given signal.

  Returns `{:ok, snapshot}` if a snapshot was created, or `{:error, changeset}` on failure.

  ## Examples

      iex> create_snapshot_for_signal(signal)
      {:ok, %SignalSnapshot{}}
  """
  def create_snapshot_for_signal(%Signal{} = signal) do
    snapshot_attrs = %{
      signal_id: signal.id,
      snapshot_at: DateTime.utc_now(),
      symbol: signal.symbol,
      current_volume_24h: signal.current_volume_24h,
      initial_volume_24h: signal.initial_volume_24h,
      max_price_usd: signal.max_price_usd,
      current_price_usd: get_live_price(signal) || signal.current_price_usd,
      in_top: signal.in_top,
      position: signal.position
    }

    case create_snapshot(snapshot_attrs) do
      {:ok, snapshot} ->
        Log.debug("Created snapshot for signal #{signal.symbol}",
          module: :signals,
          operation: :create_snapshot,
          symbol: signal.symbol
        )

        broadcast_snapshot_created(snapshot)
        {:ok, snapshot}

      {:error, changeset} ->
        Log.db_error("Failed to create snapshot for signal #{signal.symbol}",
          module: :signals,
          operation: :create_snapshot,
          symbol: signal.symbol,
          reason: inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  @doc """
  Gets the most recent snapshot for a given signal.

  Returns the snapshot or `nil` if no snapshots exist.

  ## Examples

      iex> get_last_snapshot(signal_id)
      %SignalSnapshot{}

      iex> get_last_snapshot(signal_id)
      nil
  """
  def get_last_snapshot(signal_id) do
    from(s in SignalSnapshot,
      where: s.signal_id == ^signal_id,
      order_by: [desc: s.snapshot_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Lists snapshots for a given signal with optional time range filtering.

  ## Options

    * `:signal_id` - Filter by signal ID (required)
    * `:from` - Start datetime (optional)
    * `:to` - End datetime (optional)

  ## Examples

      iex> list_snapshots(signal_id: 1)
      [%SignalSnapshot{}, ...]

      iex> list_snapshots(signal_id: 1, from: ~U[2025-01-01 00:00:00Z])
      [%SignalSnapshot{}, ...]
  """
  def list_snapshots(opts) do
    signal_id = Keyword.fetch!(opts, :signal_id)

    query =
      from(s in SignalSnapshot,
        where: s.signal_id == ^signal_id,
        order_by: [asc: s.snapshot_at]
      )

    query =
      case Keyword.get(opts, :from) do
        nil -> query
        from_datetime -> where(query, [s], s.snapshot_at >= ^from_datetime)
      end

    query =
      case Keyword.get(opts, :to) do
        nil -> query
        to_datetime -> where(query, [s], s.snapshot_at <= ^to_datetime)
      end

    Repo.all(query)
  end

  @doc """
  Gets the complete snapshot history for a signal.

  Returns all snapshots for the signal ordered by snapshot time.

  ## Examples

      iex> get_snapshot_history(signal_id)
      [%SignalSnapshot{}, ...]
  """
  def get_snapshot_history(signal_id) do
    list_snapshots(signal_id: signal_id)
  end

  @doc """
  Returns the most recent SignalSnapshot for `signal_id` whose `snapshot_at`
  is ≤ `at` and ≥ `at - max_age_minutes`. Returns `nil` if no snapshot exists
  in that window.

  Snapshots are created reactively (only when tracked fields change), so an
  exact-time lookup isn't reliable — callers needing "the snapshot from
  ~N minutes ago" should use this helper and pick a tolerance that covers
  typical gaps.
  """
  def snapshot_for_signal_at_or_before(signal_id, %DateTime{} = at, max_age_minutes)
      when is_integer(max_age_minutes) and max_age_minutes > 0 do
    earliest = DateTime.add(at, -max_age_minutes * 60, :second)

    from(s in SignalSnapshot,
      where:
        s.signal_id == ^signal_id and
          s.snapshot_at <= ^at and
          s.snapshot_at >= ^earliest,
      order_by: [desc: s.snapshot_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Returns position-rank snapshots for the given base symbols recorded at or
  after `cutoff`, grouped by symbol. Used by `Watchlist` to render sparklines
  without exposing the snapshot schema to orchestration code.

  Returns `%{}` when `symbols` is empty.
  """
  def snapshots_for_symbols_since([], _cutoff), do: %{}

  def snapshots_for_symbols_since(symbols, %DateTime{} = cutoff) when is_list(symbols) do
    from(s in SignalSnapshot,
      where: s.symbol in ^symbols and s.snapshot_at >= ^cutoff,
      order_by: [asc: s.snapshot_at],
      select: %{symbol: s.symbol, position: s.position, snapshot_at: s.snapshot_at}
    )
    |> Repo.all()
    |> Enum.group_by(& &1.symbol)
  end

  defp create_snapshot(attrs) do
    %SignalSnapshot{}
    |> SignalSnapshot.changeset(attrs)
    |> Repo.insert()
  end

  defp get_live_price(%{symbol_price: %{current_price: price}}), do: price
  defp get_live_price(_), do: nil

  defp broadcast_signals_updated(signals) when is_list(signals) do
    # Preload symbol_price for all signals so LiveView can display prices
    signals = Repo.preload(signals, :symbol_price)

    Phoenix.PubSub.broadcast(
      CoinTracker.PubSub,
      "signals:updated",
      {:signals_updated, signals}
    )

    Log.debug("Broadcasted #{length(signals)} signals to subscribers",
      module: :signals,
      operation: :broadcast
    )
  end

  defp broadcast_snapshot_created(snapshot) do
    Phoenix.PubSub.broadcast(
      CoinTracker.PubSub,
      "signal_snapshots:#{snapshot.signal_id}",
      {:snapshot_created, snapshot}
    )

    Log.debug("Broadcasted snapshot for signal_id #{snapshot.signal_id}",
      module: :signals,
      operation: :broadcast
    )
  end

  # Market Status functions

  @doc """
  Creates a market status record with the current count of active signals in top 10.

  Returns `{:ok, market_status}` or `{:error, changeset}`.

  ## Examples

      iex> create_market_status()
      {:ok, %MarketStatus{active_signals_count: 7, recorded_at: ~U[2025-11-24 12:00:00Z]}}
  """
  def create_market_status do
    count = count_active_signals()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      active_signals_count: count,
      recorded_at: now
    }

    case %MarketStatus{}
         |> MarketStatus.changeset(attrs)
         |> Repo.insert() do
      {:ok, market_status} = result ->
        broadcast_market_status_created(market_status)
        result

      error ->
        error
    end
  end

  @doc """
  Counts the number of signals currently in the top 10 (active and in_top).

  Returns an integer count.

  ## Examples

      iex> count_active_signals()
      7
  """
  def count_active_signals do
    from(s in Signal,
      where: s.active == true and s.in_top == true,
      select: count(s.id)
    )
    |> Repo.one()
  end

  @doc """
  Counts the total number of active signals regardless of top position.

  Returns an integer count.

  ## Examples

      iex> count_total_active_signals()
      15
  """
  def count_total_active_signals do
    from(s in Signal,
      where: s.active == true,
      select: count(s.id)
    )
    |> Repo.one()
  end

  @doc """
  Lists market status records with optional filtering.

  ## Options

    * `:from` - Start datetime (optional)
    * `:to` - End datetime (optional)
    * `:limit` - Limit number of results (optional)
    * `:order_by` - Order results (default: `[desc: :recorded_at]`)

  ## Examples

      iex> list_market_statuses()
      [%MarketStatus{}, ...]

      iex> list_market_statuses(from: ~U[2025-11-01 00:00:00Z], limit: 100)
      [%MarketStatus{}, ...]
  """
  def list_market_statuses(opts \\ []) do
    query = from(m in MarketStatus)

    query =
      case Keyword.get(opts, :from) do
        nil -> query
        from_datetime -> where(query, [m], m.recorded_at >= ^from_datetime)
      end

    query =
      case Keyword.get(opts, :to) do
        nil -> query
        to_datetime -> where(query, [m], m.recorded_at <= ^to_datetime)
      end

    query =
      case Keyword.get(opts, :order_by) do
        nil -> order_by(query, [m], desc: m.recorded_at)
        order -> order_by(query, ^order)
      end

    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        limit -> limit(query, ^limit)
      end

    Repo.all(query)
  end

  @doc """
  Gets the most recent market status record.

  Returns the market status or `nil` if no records exist.

  ## Examples

      iex> get_latest_market_status()
      %MarketStatus{active_signals_count: 8, recorded_at: ~U[2025-11-24 12:00:00Z]}
  """
  def get_latest_market_status do
    from(m in MarketStatus,
      order_by: [desc: m.recorded_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Lists market status records for a given time period with appropriate aggregation.

  - "today": Returns raw data (last 24 hours)
  - "week": Returns hourly averages (last 7 days), floored
  - "month": Returns 4-hour averages (last 30 days), floored

  ## Examples

      iex> list_market_statuses_aggregated("today")
      [%MarketStatus{}, ...]

      iex> list_market_statuses_aggregated("week")
      [%{recorded_at: ~U[...], active_signals_count: 7}, ...]
  """
  def list_market_statuses_aggregated(period) when period in ["today", "week", "month"] do
    from_datetime = get_period_start(period)
    statuses = list_market_statuses(from: from_datetime, order_by: [asc: :recorded_at])

    case period do
      "today" -> statuses
      "week" -> aggregate_by_hour(statuses)
      "month" -> aggregate_by_four_hours(statuses)
    end
  end

  defp get_period_start("today"), do: DateTime.add(DateTime.utc_now(), -24, :hour)
  defp get_period_start("week"), do: DateTime.add(DateTime.utc_now(), -7, :day)
  defp get_period_start("month"), do: DateTime.add(DateTime.utc_now(), -30, :day)

  defp aggregate_by_hour([]), do: []

  defp aggregate_by_hour(statuses) do
    statuses
    |> Enum.group_by(fn s ->
      # Truncate to hour by zeroing out minutes, seconds, and microseconds
      %{s.recorded_at | minute: 0, second: 0, microsecond: {0, 6}}
    end)
    |> Enum.map(fn {hour, items} ->
      avg = items |> Enum.map(& &1.active_signals_count) |> Enum.sum() |> div(length(items))
      %{recorded_at: hour, active_signals_count: avg}
    end)
    |> Enum.sort_by(& &1.recorded_at, DateTime)
  end

  defp aggregate_by_four_hours([]), do: []

  defp aggregate_by_four_hours(statuses) do
    statuses
    |> Enum.group_by(fn s ->
      hour = s.recorded_at.hour
      bucket_hour = div(hour, 4) * 4
      # Fix microsecond precision issue
      %{s.recorded_at | hour: bucket_hour, minute: 0, second: 0, microsecond: {0, 6}}
    end)
    |> Enum.map(fn {bucket, items} ->
      avg = items |> Enum.map(& &1.active_signals_count) |> Enum.sum() |> div(length(items))
      %{recorded_at: bucket, active_signals_count: avg}
    end)
    |> Enum.sort_by(& &1.recorded_at, DateTime)
  end

  defp broadcast_market_status_created(market_status) do
    Phoenix.PubSub.broadcast(
      CoinTracker.PubSub,
      "market_status:updated",
      {:market_status_created, market_status}
    )

    Log.debug("Broadcasted market status: #{market_status.active_signals_count} active signals",
      module: :signals,
      operation: :broadcast
    )
  end

  # CoinGecko Snapshot functions

  @doc """
  Inserts a CoinGecko snapshot row. Returns `{:ok, snapshot}` or `{:error, changeset}`.

  Used by `CoinGeckoPoller` on each successful poll. The `(coingecko_id, snapshot_at)`
  unique index guarantees idempotence if the same tick is replayed.
  """
  def create_coingecko_snapshot(attrs) do
    %CoingeckoSnapshot{}
    |> CoingeckoSnapshot.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the most recent snapshot for the given `coingecko_id`, or `nil`.
  """
  def get_latest_coingecko_snapshot(coingecko_id) when is_binary(coingecko_id) do
    from(s in CoingeckoSnapshot,
      where: s.coingecko_id == ^coingecko_id,
      order_by: [desc: s.snapshot_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Returns the snapshot for `coingecko_id` whose `snapshot_at` is the largest
  value `<=` the given cutoff, or `nil` if none exists.

  Used to find the "~24h ago" data point when computing volume deltas.
  """
  def get_coingecko_snapshot_at_or_before(coingecko_id, %DateTime{} = cutoff)
      when is_binary(coingecko_id) do
    from(s in CoingeckoSnapshot,
      where: s.coingecko_id == ^coingecko_id and s.snapshot_at <= ^cutoff,
      order_by: [desc: s.snapshot_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Deletes snapshot rows older than the given cutoff. Returns `{:ok, count}`.

  Intended to be called inline at the end of each `CoinGeckoPoller` cycle
  with a 48h cutoff — old enough to support 24h deltas with margin, young
  enough to keep the table from unbounded growth.
  """
  def prune_coingecko_snapshots(%DateTime{} = cutoff) do
    {count, _} =
      from(s in CoingeckoSnapshot, where: s.snapshot_at < ^cutoff)
      |> Repo.delete_all()

    {:ok, count}
  end

  # New Signal Notifications

  @doc """
  Notifies pro/admin users via Telegram about new signals that haven't been notified yet.

  Queries for signals where `telegram_notified_at` is NULL and `in_top` is true,
  sends a batched notification message, and marks them as notified.

  Returns `{:ok, count}` with the number of signals notified.

  ## Examples

      iex> notify_new_signals()
      {:ok, 2}

      iex> notify_new_signals()
      {:ok, 0}  # No new signals
  """
  def notify_new_signals do
    Repo.transaction(fn ->
      # Lock rows to prevent concurrent processing; skip if another process has them
      new_signals =
        from(s in Signal,
          where: is_nil(s.telegram_notified_at) and s.in_top == true,
          order_by: [asc: s.position],
          lock: "FOR UPDATE SKIP LOCKED"
        )
        |> Repo.all()

      if new_signals != [] do
        message = format_new_signals_message(new_signals)
        user_ids = Accounts.list_pro_users_with_telegram() |> Enum.map(& &1.id)

        if user_ids != [] do
          TelegramService.broadcast_message(user_ids, message, kind: :signals_new)
        end

        # Mark AFTER sending - if send fails/raises, transaction rolls back
        mark_signals_as_notified(new_signals)
      end

      length(new_signals)
    end)
  end

  defp mark_signals_as_notified(signals) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    ids = Enum.map(signals, & &1.id)

    from(s in Signal, where: s.id in ^ids)
    |> Repo.update_all(set: [telegram_notified_at: now])
  end

  defp format_new_signals_message(signals) do
    header =
      case length(signals) do
        1 -> "🆕 New Signal"
        n -> "🆕 #{n} New Signals"
      end

    signal_lines =
      signals
      |> Enum.with_index(1)
      |> Enum.map(fn {signal, idx} ->
        "#{idx}. #{signal.symbol} (##{signal.position})"
      end)
      |> Enum.join("\n")

    url = CoinTrackerWeb.Endpoint.url() <> "/signals"

    "#{header}\n\n#{signal_lines}\n\n#{url}"
  end

  # Signal Price functions

  @doc """
  Returns a list of unique symbols from all active signals.

  This is used by the SignalPricePoller to determine which symbols need price updates.

  ## Examples

      iex> get_unique_symbols_for_active_signals()
      ["ETH", "BTC", "SOL"]
  """
  def get_unique_symbols_for_active_signals do
    from(s in Signal,
      where: s.active == true,
      distinct: s.symbol,
      select: s.symbol
    )
    |> Repo.all()
  end

  @doc """
  Returns all unique symbols that have ever appeared as signals, with aggregate
  metadata: occurrence count, first/last seen timestamps, and whether the symbol
  currently has an active signal.

  Results are ordered alphabetically by symbol and intended to be cached by
  `CoinTracker.Signals.HistoricalCache`.

  ## Examples

      iex> list_unique_symbols()
      [
        %{
          symbol: "BTC",
          name: "Bitcoin",
          occurrence_count: 5,
          first_seen: ~U[2025-01-01 00:00:00Z],
          last_seen: ~U[2025-06-01 00:00:00Z],
          has_active: true
        },
        ...
      ]
  """
  def list_unique_symbols do
    cutoff = DateTime.utc_now() |> DateTime.add(-168, :hour)

    from(s in Signal,
      group_by: s.symbol,
      select: %{
        symbol: s.symbol,
        # max() satisfies GROUP BY for the display name. Safe because
        # coin names are stable per symbol in the upstream API; if a
        # name ever changed, we'd simply show the latest value.
        name: max(s.name),
        occurrence_count: count(s.id),
        first_seen: min(s.in_top_since),
        last_seen: max(s.in_top_since),
        has_active: fragment("bool_or(?)", s.active),
        has_recently_exited:
          fragment(
            "bool_or(? = false AND ? IS NOT NULL AND ? >= ?)",
            s.active,
            s.exit_date,
            s.exit_date,
            ^cutoff
          ),
        last_exit_date: max(s.exit_date)
      },
      order_by: [asc: s.symbol]
    )
    |> Repo.all()
  end

  @doc """
  Like `list_unique_symbols/0`, but filtered for public (non-pro) visitors.

  Excludes signals that are active or exited within the last 168 hours (7 days).
  Sets `has_active` and `has_recently_exited` to `false` for all rows since
  those are pro-only signals that aren't shown to public users. Symbols with
  only active/recent signals won't appear at all.
  """
  def list_unique_symbols_public do
    cutoff = DateTime.utc_now() |> DateTime.add(-168, :hour)

    from(s in Signal,
      where: s.active == false,
      where: s.exit_date <= ^cutoff,
      group_by: s.symbol,
      select: %{
        symbol: s.symbol,
        name: max(s.name),
        occurrence_count: count(s.id),
        first_seen: min(s.in_top_since),
        last_seen: max(s.in_top_since),
        has_active: false,
        has_recently_exited: false,
        last_exit_date: max(s.exit_date)
      },
      order_by: [asc: s.symbol]
    )
    |> Repo.all()
  end

  @doc """
  Returns all occurrences (enriched with snapshot analysis) for the given
  symbol, ordered by most recent first.

  Each returned map has the same shape as `get_previous_occurrences/3` but
  includes every occurrence — nothing is excluded.

  ## Examples

      iex> get_all_occurrences("BTC")
      [%{signal: %Signal{}, entry_price: ..., ...}, ...]
  """
  def get_all_occurrences(symbol) do
    from(s in Signal,
      where: s.symbol == ^symbol,
      order_by: [desc: s.in_top_since]
    )
    |> Repo.all()
    |> Enum.map(&analyze_occurrence/1)
  end

  @doc """
  Like `get_all_occurrences/1`, but filtered for public (non-pro) visitors.

  Excludes signals that are active or exited within the last 168 hours (7 days).
  """
  def get_all_occurrences_public(symbol) do
    cutoff = DateTime.utc_now() |> DateTime.add(-168, :hour)

    from(s in Signal,
      where: s.symbol == ^symbol,
      where: s.active == false,
      where: s.exit_date <= ^cutoff,
      order_by: [desc: s.in_top_since]
    )
    |> Repo.all()
    |> Enum.map(&analyze_occurrence/1)
  end

  @doc """
  Links all active signals with the given symbol to a symbol_price record.

  This is called by the SignalPricePoller after successfully fetching a price
  for a symbol, linking all matching signals to that symbol_price.

  ## Parameters

    - `symbol` - The base symbol (e.g., "ETH")
    - `symbol_price_id` - The ID of the symbol_price record to link

  ## Examples

      iex> link_signals_to_symbol_price("ETH", 123)
      {3, nil}
  """
  def link_signals_to_symbol_price(symbol, symbol_price_id) do
    from(s in Signal,
      where: s.active == true and s.symbol == ^symbol
    )
    |> Repo.update_all(set: [symbol_price_id: symbol_price_id])
  end

  @doc """
  Lists active signals with preloaded symbol_price association.

  This is the same as `list_signals/1` but includes the symbol_price preload
  for displaying live prices in the UI.

  ## Options

    Same as `list_signals/1`

  ## Examples

      iex> list_signals_with_prices(active: true)
      [%Signal{symbol_price: %SymbolPrice{...}}, ...]
  """
  def list_signals_with_prices(opts \\ []) do
    Signal
    |> apply_filters(opts)
    |> apply_order(opts)
    |> apply_limit(opts)
    |> preload(:symbol_price)
    |> Repo.all()
    |> enrich_with_coingecko_metrics()
  end

  defp enrich_with_coingecko_metrics([]), do: []

  defp enrich_with_coingecko_metrics(signals) do
    ids = signals |> Enum.map(& &1.coingecko_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    latest = latest_coingecko_metrics(ids)
    cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)
    prior = prior_coingecko_metrics(ids, cutoff)

    Enum.map(signals, fn signal ->
      latest_row = Map.get(latest, signal.coingecko_id)
      prior_row = Map.get(prior, signal.coingecko_id)

      signal
      |> put_price_change(latest_row)
      |> put_volume_change(latest_row, prior_row)
    end)
  end

  defp put_price_change(signal, nil), do: signal

  defp put_price_change(signal, %{price_change_percentage_24h: pct}) do
    %{signal | cg_price_change_24h_pct: pct}
  end

  defp put_volume_change(signal, latest_row, prior_row) do
    %{signal | cg_volume_change_24h_pct: compute_volume_delta(latest_row, prior_row)}
  end

  defp compute_volume_delta(nil, _), do: nil
  defp compute_volume_delta(_, nil), do: nil

  defp compute_volume_delta(%{snapshot_at: same_at}, %{snapshot_at: same_at}) do
    # v_now and v_then resolved to the same snapshot — history doesn't span 24h.
    nil
  end

  defp compute_volume_delta(%{total_volume_usd: v_now}, %{total_volume_usd: v_then}) do
    cond do
      is_nil(v_now) ->
        nil

      is_nil(v_then) ->
        nil

      Decimal.equal?(v_then, 0) ->
        nil

      true ->
        v_now
        |> Decimal.sub(v_then)
        |> Decimal.div(v_then)
        |> Decimal.mult(100)
    end
  end

  # Returns a map of coingecko_id => %{snapshot_at, price_change_percentage_24h,
  # total_volume_usd} for the most-recent snapshot per coingecko_id.
  defp latest_coingecko_metrics([]), do: %{}

  defp latest_coingecko_metrics(coingecko_ids) do
    from(s in CoingeckoSnapshot,
      where: s.coingecko_id in ^coingecko_ids,
      distinct: [asc: s.coingecko_id],
      order_by: [asc: s.coingecko_id, desc: s.snapshot_at],
      select: %{
        coingecko_id: s.coingecko_id,
        snapshot_at: s.snapshot_at,
        price_change_percentage_24h: s.price_change_percentage_24h,
        total_volume_usd: s.total_volume_usd
      }
    )
    |> Repo.all()
    |> Map.new(fn row -> {row.coingecko_id, row} end)
  end

  # Returns a map of coingecko_id => %{snapshot_at, total_volume_usd} for the
  # most-recent snapshot whose snapshot_at is at-or-before `cutoff`, per
  # coingecko_id. Used to compute the 24h volume delta.
  defp prior_coingecko_metrics([], _cutoff), do: %{}

  defp prior_coingecko_metrics(coingecko_ids, cutoff) do
    from(s in CoingeckoSnapshot,
      where: s.coingecko_id in ^coingecko_ids and s.snapshot_at <= ^cutoff,
      distinct: [asc: s.coingecko_id],
      order_by: [asc: s.coingecko_id, desc: s.snapshot_at],
      select: %{
        coingecko_id: s.coingecko_id,
        snapshot_at: s.snapshot_at,
        total_volume_usd: s.total_volume_usd
      }
    )
    |> Repo.all()
    |> Map.new(fn row -> {row.coingecko_id, row} end)
  end

  @doc """
  Returns the most recent previous occurrences of a given symbol in the top 10,
  excluding the supplied signal ID.

  Each returned map describes a past occurrence with its entry, top
  (highest observed), and exit prices, total duration in top, and a
  breakdown of time spent at each position (in seconds, keyed by
  position number).

  ## Options

    * `:limit` - max number of occurrences to return. Accepts a positive
      integer or the atom `:all` for no limit. Defaults to `5`.

  ## Examples

      iex> get_previous_occurrences("BTC", 42)
      [
        %{
          signal: %Signal{},
          entry_price: #Decimal<100>,
          top_price: #Decimal<150>,
          exit_price: #Decimal<120>,
          entry_at: ~U[2025-01-01 00:00:00Z],
          exit_at: ~U[2025-01-02 00:00:00Z],
          duration_seconds: 86_400,
          position_durations: %{1 => 10_800, 2 => 18_000},
          best_position: 1
        }
      ]
  """
  def get_previous_occurrences(symbol, exclude_signal_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    base_query =
      from(s in Signal,
        where: s.symbol == ^symbol and s.id != ^exclude_signal_id,
        order_by: [desc: s.in_top_since]
      )

    base_query
    |> maybe_limit(limit)
    |> Repo.all()
    |> Enum.map(&analyze_occurrence/1)
  end

  defp maybe_limit(query, :all), do: query
  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)

  @doc """
  Counts the total number of previous occurrences for a symbol,
  excluding the supplied signal ID. Used to decide whether to show
  a "show more" affordance when `get_previous_occurrences/3` is limited.
  """
  def count_previous_occurrences(symbol, exclude_signal_id) do
    from(s in Signal,
      where: s.symbol == ^symbol and s.id != ^exclude_signal_id,
      select: count(s.id)
    )
    |> Repo.one()
  end

  defp analyze_occurrence(%Signal{} = signal) do
    snapshots = get_snapshot_history(signal.id)

    %{
      signal: signal,
      entry_price: signal.initial_price_usd,
      top_price: resolve_top_price(signal, snapshots),
      exit_price: resolve_exit_price(signal, snapshots),
      entry_at: signal.in_top_since,
      exit_at: signal.exit_date,
      duration_seconds: compute_duration_seconds(signal),
      position_durations: compute_position_durations(snapshots),
      best_position: min_position(snapshots)
    }
  end

  defp resolve_exit_price(%Signal{} = signal, snapshots) do
    case List.last(snapshots) do
      %SignalSnapshot{current_price_usd: price} when not is_nil(price) -> price
      _ -> signal.current_price_usd
    end
  end

  # Prefer the tracked `max_price_usd` on the Signal (sourced from the
  # upstream API). Fall back to the highest `current_price_usd` observed
  # across recorded snapshots for signals that predate that field being
  # populated.
  defp resolve_top_price(%Signal{max_price_usd: %Decimal{} = max}, _snapshots), do: max

  defp resolve_top_price(_signal, snapshots) do
    snapshots
    |> Enum.map(& &1.current_price_usd)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      [first | rest] -> Enum.reduce(rest, first, &decimal_max/2)
    end
  end

  defp decimal_max(a, b) do
    if Decimal.compare(a, b) == :gt, do: a, else: b
  end

  defp compute_duration_seconds(%Signal{in_top_since: nil}), do: 0

  defp compute_duration_seconds(%Signal{in_top_since: entry, exit_date: nil}) do
    DateTime.diff(DateTime.utc_now(), entry, :second)
  end

  defp compute_duration_seconds(%Signal{in_top_since: entry, exit_date: exit_at}) do
    DateTime.diff(exit_at, entry, :second)
  end

  # Given a list of snapshots ordered by snapshot_at asc, returns a map of
  # %{position => seconds_spent_at_position}. Each snapshot is treated as a
  # point sample; the duration attributed to a position is the delta to the
  # next snapshot. The final snapshot contributes one interval using the
  # median interval of the series (or 5 minutes as a default) so that a
  # single-snapshot occurrence still contributes meaningful time.
  #
  # Snapshots with nil position or `in_top: false` are ignored — we only
  # count time actually spent inside the top 10.
  defp compute_position_durations([]), do: %{}

  defp compute_position_durations(snapshots) do
    sorted = Enum.sort_by(snapshots, & &1.snapshot_at, DateTime)
    default_interval = default_snapshot_interval(sorted)

    # Pair each snapshot with its successor (nil for the last one) in a single
    # O(n) pass, avoiding Enum.at/2 which would make this O(n²).
    nexts = tl(sorted) ++ [nil]

    sorted
    |> Enum.zip(nexts)
    |> Enum.reduce(%{}, fn {snapshot, next}, acc ->
      if counts_toward_top?(snapshot) do
        delta = interval_for(snapshot, next, default_interval)
        Map.update(acc, snapshot.position, delta, &(&1 + delta))
      else
        acc
      end
    end)
  end

  defp counts_toward_top?(%SignalSnapshot{in_top: true, position: p}) when is_integer(p), do: true
  defp counts_toward_top?(_), do: false

  defp interval_for(_snapshot, nil, default_interval), do: default_interval

  defp interval_for(snapshot, next_snapshot, _default_interval) do
    DateTime.diff(next_snapshot.snapshot_at, snapshot.snapshot_at, :second)
  end

  # Used to attribute a duration to the final snapshot in a series (which has
  # no successor) and to single-snapshot occurrences. We prefer the first
  # observed interval in the series; if unavailable, fall back to 300 seconds
  # — a coarse but reasonable estimate for a top-10 dwell increment.
  defp default_snapshot_interval([first, second | _]) do
    case DateTime.diff(second.snapshot_at, first.snapshot_at, :second) do
      diff when diff > 0 -> diff
      _ -> 300
    end
  end

  defp default_snapshot_interval(_), do: 300

  defp min_position([]), do: nil

  defp min_position(snapshots) do
    snapshots
    |> Enum.filter(&counts_toward_top?/1)
    |> Enum.map(& &1.position)
    |> Enum.min(fn -> nil end)
  end
end
