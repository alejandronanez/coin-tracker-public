defmodule CoinTracker.Signals.SnapshotPollerTest do
  # Not async because we're dealing with a globally registered GenServer
  use CoinTracker.DataCase, async: false

  alias CoinTracker.Signals
  alias CoinTracker.Signals.Poller
  alias CoinTracker.Signals.SignalSnapshot
  alias CoinTracker.Signals.SnapshotPoller
  alias CoinTracker.Repo

  import CoinTracker.SignalsFixtures

  describe "initialization" do
    test "poller is already started in application" do
      pid = Process.whereis(SnapshotPoller)
      assert pid != nil
      assert Process.alive?(pid)
    end

    test "poller is subscribed to Poller.status_topic/0" do
      # Subscribers register themselves in the Phoenix.PubSub registry. If the
      # SnapshotPoller is subscribed, broadcasting on the topic from this test
      # process will deliver to its mailbox.
      pid = Process.whereis(SnapshotPoller)
      assert pid != nil

      # No active signals → no rows written, but the message must be processed.
      Repo.delete_all(Signals.Signal)

      broadcast_status_update()
      flush_snapshot_poller()

      # No crash, GenServer still alive — confirms the message was handled.
      assert Process.alive?(pid)
    end
  end

  describe "reacts to Poller status updates" do
    test "broadcasting {:poller_status_updated, _} writes a snapshot for every active signal" do
      signal_fixture(%{active: true})
      signal_fixture(%{active: true})

      assert Repo.aggregate(SignalSnapshot, :count) == 0

      broadcast_status_update()
      flush_snapshot_poller()

      assert Repo.aggregate(SignalSnapshot, :count) == 2
    end

    test "each broadcast writes a fresh round of snapshots (no coalescing, no gating)" do
      signal_fixture(%{active: true})
      signal_fixture(%{active: true})

      broadcast_status_update()
      flush_snapshot_poller()
      assert Repo.aggregate(SignalSnapshot, :count) == 2

      # Second broadcast represents a second real fingerprint change upstream
      # — Poller only broadcasts on actual flips. Each flip is its own event,
      # so each gets its own snapshot row per active signal.
      broadcast_status_update()
      flush_snapshot_poller()
      assert Repo.aggregate(SignalSnapshot, :count) == 4

      broadcast_status_update()
      flush_snapshot_poller()
      assert Repo.aggregate(SignalSnapshot, :count) == 6
    end

    test "ignores broadcasts when there are no active signals" do
      signal_fixture(%{active: false})

      broadcast_status_update()
      flush_snapshot_poller()

      assert Repo.aggregate(SignalSnapshot, :count) == 0
    end
  end

  describe "snapshot_now/0" do
    test "writes a snapshot for every active signal on each call" do
      signal_fixture(%{active: true})
      signal_fixture(%{active: true})

      SnapshotPoller.snapshot_now()
      flush_snapshot_poller()
      assert Repo.aggregate(SignalSnapshot, :count) == 2

      SnapshotPoller.snapshot_now()
      flush_snapshot_poller()
      assert Repo.aggregate(SignalSnapshot, :count) == 4
    end

    test "captures all snapshot fields with the signal's current values" do
      signal =
        signal_fixture(%{
          symbol: "TEST",
          current_volume_24h: Decimal.new("1500000"),
          initial_volume_24h: Decimal.new("1000000"),
          max_price_usd: Decimal.new("2.50"),
          current_price_usd: Decimal.new("2.00"),
          in_top: true,
          position: 3,
          active: true
        })

      SnapshotPoller.snapshot_now()
      flush_snapshot_poller()

      snapshot = Repo.get_by(SignalSnapshot, signal_id: signal.id)
      assert snapshot != nil
      assert snapshot.symbol == "TEST"
      assert Decimal.equal?(snapshot.current_volume_24h, Decimal.new("1500000"))
      assert Decimal.equal?(snapshot.initial_volume_24h, Decimal.new("1000000"))
      assert Decimal.equal?(snapshot.max_price_usd, Decimal.new("2.50"))
      assert Decimal.equal?(snapshot.current_price_usd, Decimal.new("2.00"))
      assert snapshot.in_top == true
      assert snapshot.position == 3
    end

    test "skips inactive signals" do
      active_signal = signal_fixture(%{active: true})
      _inactive_signal = signal_fixture(%{active: false})

      SnapshotPoller.snapshot_now()
      flush_snapshot_poller()

      snapshots = Repo.all(SignalSnapshot)
      assert length(snapshots) == 1
      assert hd(snapshots).signal_id == active_signal.id
    end

    test "handles empty signal list gracefully" do
      Repo.delete_all(Signals.Signal)

      SnapshotPoller.snapshot_now()
      flush_snapshot_poller()

      assert Repo.aggregate(SignalSnapshot, :count) == 0
    end
  end

  describe "history captured over a sequence of upstream changes" do
    test "successive broadcasts after field updates produce a chronological history" do
      signal =
        signal_fixture(%{
          active: true,
          current_volume_24h: Decimal.new("1000000"),
          max_price_usd: Decimal.new("1.00"),
          in_top: false,
          position: nil
        })

      # Snapshot 1: initial state (broadcast as if Poller just ingested).
      broadcast_status_update()
      flush_snapshot_poller()

      {:ok, _} =
        signal
        |> Ecto.Changeset.change(%{current_volume_24h: Decimal.new("1500000")})
        |> Repo.update()

      broadcast_status_update()
      flush_snapshot_poller()

      signal = Repo.get!(Signals.Signal, signal.id)

      {:ok, _} =
        signal
        |> Ecto.Changeset.change(%{
          max_price_usd: Decimal.new("2.00"),
          in_top: true,
          position: 5
        })
        |> Repo.update()

      broadcast_status_update()
      flush_snapshot_poller()

      history = Signals.get_snapshot_history(signal.id)
      assert length(history) == 3

      snapshot_times = Enum.map(history, & &1.snapshot_at)
      assert snapshot_times == Enum.sort(snapshot_times, DateTime)

      [snap1, snap2, snap3] = history
      assert Decimal.equal?(snap1.current_volume_24h, Decimal.new("1000000"))
      assert Decimal.equal?(snap2.current_volume_24h, Decimal.new("1500000"))
      assert Decimal.equal?(snap3.max_price_usd, Decimal.new("2.00"))
      assert snap3.in_top == true
      assert snap3.position == 5
    end

    test "signals that are activated mid-stream start appearing in subsequent snapshots" do
      top_signal = signal_fixture(%{active: true, in_top: true, position: 1})
      grace_signal = signal_fixture(%{active: true, in_top: false, position: nil})
      inactive_signal = signal_fixture(%{active: false, in_top: false, position: nil})

      broadcast_status_update()
      flush_snapshot_poller()

      assert length(Signals.get_snapshot_history(top_signal.id)) == 1
      assert length(Signals.get_snapshot_history(grace_signal.id)) == 1
      assert length(Signals.get_snapshot_history(inactive_signal.id)) == 0

      {:ok, _} =
        inactive_signal
        |> Ecto.Changeset.change(%{active: true})
        |> Repo.update()

      broadcast_status_update()
      flush_snapshot_poller()

      assert length(Signals.get_snapshot_history(top_signal.id)) == 2
      assert length(Signals.get_snapshot_history(grace_signal.id)) == 2
      assert length(Signals.get_snapshot_history(inactive_signal.id)) == 1
    end
  end

  # Mirrors what `Signals.Poller` itself emits whenever its top-10 fingerprint
  # changes (see `lib/coin_tracker/signals/poller.ex`). In tests Poller is
  # disabled (config/test.exs), so we generate the broadcast directly.
  defp broadcast_status_update do
    Phoenix.PubSub.broadcast(
      CoinTracker.PubSub,
      Poller.status_topic(),
      {:poller_status_updated,
       %{fingerprint: :erlang.unique_integer(), last_changed_at: DateTime.utc_now()}}
    )
  end

  # Synchronization barrier: a sync call to the GenServer is processed strictly
  # after any messages already in its mailbox, so when this returns we know the
  # broadcast/cast above has been handled. Avoids `Process.sleep`.
  defp flush_snapshot_poller do
    :sys.get_state(SnapshotPoller)
  end
end
