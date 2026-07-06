defmodule CoinTracker.Signals.Poller do
  @moduledoc """
  GenServer that periodically polls the CoinScanX API to ingest signals.

  This poller automatically fetches the top 10 at a configurable interval. To
  avoid redundant work between the polling interval (~45s) and the upstream
  refresh cadence (~15 min), it fingerprints each top-10 response and skips
  the rest of the ingestion pipeline (grace period fetch, upserts, broadcast,
  notification scan) when the fingerprint matches the previous tick.

  The top 10 is treated as the source of truth for "did anything change?":
  if the top 10 didn't move, the grace period didn't either.

  ## Configuration

      config :coin_tracker, CoinTracker.Signals.Poller,
        enabled: true,
        interval: :timer.seconds(45)

  ## Options

    * `:enabled` - Whether polling is enabled (default: `true`)
    * `:interval` - Polling interval in milliseconds (default: 45 seconds)
  """

  use GenServer

  alias CoinTracker.Log
  alias CoinTracker.Signals
  alias CoinTracker.Signals.{CoinscanApiClient, Signal}

  @default_interval :timer.seconds(45)

  @poller_status_topic "poller:status"

  # Fields that constitute a meaningful change to the top 10. `current_price_usd`
  # is intentionally omitted — CoinScanX doesn't return it (SignalPricePoller
  # populates it separately), so including it would always look "unchanged" and
  # add nothing.
  @fingerprint_fields [
    :symbol,
    :position,
    :in_top,
    :in_top_since,
    :exit_date,
    :max_price_usd,
    :max_increase_percentage,
    :current_volume_24h
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers a poll immediately.

  Returns `:ok`; the poll happens asynchronously.
  """
  def poll_now do
    GenServer.cast(__MODULE__, :poll)
  end

  @doc """
  Returns the current Poller status snapshot.

  Used by admin UIs to display the latest fingerprint and when it last changed.
  Both fields are `nil` until the first real change is observed (e.g. on a
  fresh BEAM restart, or right after `reset_fingerprint/0` is called in tests).
  """
  @spec get_status() :: %{
          fingerprint: non_neg_integer() | nil,
          last_changed_at: DateTime.t() | nil
        }
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  PubSub topic on which `{:poller_status_updated, status}` messages are
  broadcast every time the top-10 fingerprint changes. Subscribe from a
  LiveView to render real-time poller status.
  """
  def status_topic, do: @poller_status_topic

  @doc false
  # Test seam: clears the cached fingerprint AND the last-changed timestamp so
  # the next poll always runs the full pipeline. Production callers shouldn't
  # need this — the Poller is the only writer and reader.
  def reset_fingerprint do
    GenServer.call(__MODULE__, :reset_fingerprint)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = get_config()

    state = %{
      enabled: Keyword.get(opts, :enabled, config[:enabled]),
      interval: Keyword.get(opts, :interval, config[:interval]),
      last_fingerprint: nil,
      last_changed_at: nil
    }

    if state.enabled do
      Log.info("Signals poller starting with interval: #{state.interval}ms",
        module: :signals_poller,
        operation: :init
      )

      send(self(), :poll)
      {:ok, state}
    else
      Log.info("Signals poller disabled via configuration",
        module: :signals_poller,
        operation: :init
      )

      {:ok, %{state | enabled: false}}
    end
  end

  @impl true
  def handle_info(:poll, %{enabled: false} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, %{enabled: true, interval: interval} = state) do
    new_state = perform_poll(state)
    Process.send_after(self(), :poll, interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:poll, state) do
    {:noreply, perform_poll(state)}
  end

  @impl true
  def handle_call(:reset_fingerprint, _from, state) do
    {:reply, :ok, %{state | last_fingerprint: nil, last_changed_at: nil}}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      fingerprint: state.last_fingerprint,
      last_changed_at: state.last_changed_at
    }

    {:reply, status, state}
  end

  # Private functions

  defp perform_poll(state) do
    Log.debug("Starting scheduled signal ingestion poll",
      module: :signals_poller,
      operation: :poll
    )

    case CoinscanApiClient.fetch_top_10() do
      {:ok, signals} ->
        new_fingerprint = fingerprint(signals)

        if new_fingerprint == state.last_fingerprint do
          Log.debug("Top 10 unchanged, skipping ingestion",
            module: :signals_poller,
            operation: :poll
          )

          state
        else
          run_full_ingestion(signals)
          changed_at = DateTime.utc_now() |> DateTime.truncate(:second)
          new_state = %{state | last_fingerprint: new_fingerprint, last_changed_at: changed_at}
          broadcast_status(new_state)
          new_state
        end

      {:error, reason} ->
        Log.api_error("Top 10 fetch failed; skipping ingestion cycle",
          module: :signals_poller,
          operation: :poll,
          reason: inspect(reason)
        )

        # Preserve the previous fingerprint: a transient fetch failure shouldn't
        # cause the next successful (identical) response to look like a change.
        state
    end
  end

  defp broadcast_status(%{last_fingerprint: fp, last_changed_at: at}) do
    Phoenix.PubSub.broadcast(
      CoinTracker.PubSub,
      @poller_status_topic,
      {:poller_status_updated, %{fingerprint: fp, last_changed_at: at}}
    )
  end

  defp run_full_ingestion(top_10_signals) do
    top_10_count = Signals.ingest_prefetched_top_10(top_10_signals)

    case Signals.ingest_grace_period() do
      {:ok, grace_period_count} ->
        Signals.broadcast_active_signals()

        Log.info(
          "Poll successful: #{inspect(%{top_10: top_10_count, grace_period: grace_period_count})}",
          module: :signals_poller,
          operation: :poll
        )

      {:error, _reason} ->
        # Grace period fetch already logged the failure. Skip the broadcast to
        # match the behavior of `Signals.ingest_all/0` (only broadcast when both
        # endpoints succeeded).
        :ok
    end

    deactivate_expired()
    notify_new_signals()
  end

  defp fingerprint(signals) when is_list(signals) do
    signals
    |> Enum.map(fn %Signal{} = s -> Map.take(s, @fingerprint_fields) end)
    |> Enum.sort_by(& &1.symbol)
    |> :erlang.phash2()
  end

  defp deactivate_expired do
    {:ok, _count} = Signals.deactivate_expired_signals()
    :ok
  end

  defp notify_new_signals do
    case Signals.notify_new_signals() do
      {:ok, 0} ->
        :ok

      {:ok, count} ->
        Log.info("Notified #{count} new signals to pro users",
          module: :signals_poller,
          operation: :notify
        )
    end
  end

  defp get_config do
    config = Application.get_env(:coin_tracker, __MODULE__, [])

    [
      enabled: Keyword.get(config, :enabled, true),
      interval: Keyword.get(config, :interval, @default_interval)
    ]
  end
end
