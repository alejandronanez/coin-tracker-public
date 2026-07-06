defmodule CoinTracker.Signals.SnapshotPoller do
  @moduledoc """
  GenServer that captures snapshots of all active signals reactively, the moment
  `CoinTracker.Signals.Poller` reports a new top-10 fingerprint.

  PR #206 made `Poller` broadcast `{:poller_status_updated, status}` on
  `Poller.status_topic/0` whenever its top-10 fingerprint actually changes —
  i.e. whenever upstream ingestion has moved the data. This GenServer
  subscribes to that topic and writes a fresh round of `SignalSnapshot` rows
  on every broadcast. There is no internal timer: snapshots happen exactly
  when the upstream data changed, and never otherwise.

  ## Configuration

      config :coin_tracker, CoinTracker.Signals.SnapshotPoller, enabled: true

  The `:enabled` flag is kept for config compatibility but is effectively a
  no-op — there is no timer to disable. To stop snapshots in tests, configure
  `Signals.Poller, enabled: false` so no broadcasts fire.

  Errors during snapshotting are logged but do not crash the GenServer.
  """

  use GenServer

  alias CoinTracker.Log
  alias CoinTracker.Signals
  alias CoinTracker.Signals.Poller

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers a snapshot of all active signals immediately.

  Bypasses the reactive subscription path. Useful for manual ops and tests.
  Returns `:ok`; the snapshot happens asynchronously.
  """
  def snapshot_now do
    GenServer.cast(__MODULE__, :snapshot)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(CoinTracker.PubSub, Poller.status_topic())

    Log.info("Snapshot poller subscribed to #{Poller.status_topic()}",
      module: :snapshot_poller,
      operation: :init
    )

    {:ok, %{}}
  end

  @impl true
  def handle_info({:poller_status_updated, _status}, state) do
    take_snapshots(:poller_status_updated)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:snapshot, state) do
    take_snapshots(:manual)
    {:noreply, state}
  end

  # Private functions

  defp take_snapshots(reason) do
    Log.debug("Taking signal snapshots (#{reason})",
      module: :snapshot_poller,
      operation: :snapshot
    )

    {:ok, count} = Signals.create_snapshots()

    Log.info("Snapshot successful: created #{count} snapshots (#{reason})",
      module: :snapshot_poller,
      operation: :snapshot
    )
  end
end
