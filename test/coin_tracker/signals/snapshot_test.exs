defmodule CoinTracker.Signals.SnapshotTest do
  use CoinTracker.DataCase, async: true

  alias CoinTracker.Signals
  alias CoinTracker.Signals.SignalSnapshot
  alias CoinTracker.Repo

  import CoinTracker.SignalsFixtures

  describe "create_snapshots/0" do
    test "creates snapshots for all active signals" do
      # Create 3 active signals
      signal1 = signal_fixture(%{active: true})
      signal2 = signal_fixture(%{active: true})
      signal3 = signal_fixture(%{active: true})

      assert {:ok, 3} = Signals.create_snapshots()

      # Verify all signals have snapshots in DB
      assert Repo.get_by(SignalSnapshot, signal_id: signal1.id) != nil
      assert Repo.get_by(SignalSnapshot, signal_id: signal2.id) != nil
      assert Repo.get_by(SignalSnapshot, signal_id: signal3.id) != nil
    end

    test "skips inactive signals" do
      # Create 2 active and 2 inactive signals
      signal1 = signal_fixture(%{active: true})
      signal2 = signal_fixture(%{active: true})
      _signal3 = signal_fixture(%{active: false})
      _signal4 = signal_fixture(%{active: false})

      assert {:ok, 2} = Signals.create_snapshots()

      # Verify only active signals have snapshots
      assert Repo.get_by(SignalSnapshot, signal_id: signal1.id) != nil
      assert Repo.get_by(SignalSnapshot, signal_id: signal2.id) != nil
      assert Repo.aggregate(SignalSnapshot, :count) == 2
    end

    test "handles empty signal list gracefully" do
      # No signals in DB
      assert {:ok, 0} = Signals.create_snapshots()
      assert Repo.aggregate(SignalSnapshot, :count) == 0
    end

    test "creates snapshot for all signals on each call" do
      # Create 3 active signals
      signal1 = signal_fixture(%{active: true})
      signal2 = signal_fixture(%{active: true})
      signal3 = signal_fixture(%{active: true})

      # Create initial snapshots for all
      assert {:ok, 3} = Signals.create_snapshots()

      # Call create_snapshots again - should create 3 more snapshots
      assert {:ok, 3} = Signals.create_snapshots()

      # Verify total snapshot count (3 initial + 3 new)
      assert Repo.aggregate(SignalSnapshot, :count) == 6

      # Verify each signal has 2 snapshots
      assert length(Signals.list_snapshots(signal_id: signal1.id)) == 2
      assert length(Signals.list_snapshots(signal_id: signal2.id)) == 2
      assert length(Signals.list_snapshots(signal_id: signal3.id)) == 2
    end
  end

  describe "create_snapshot_for_signal/1" do
    test "creates snapshot with signal data" do
      signal = signal_fixture()

      assert {:ok, snapshot} = Signals.create_snapshot_for_signal(signal)

      assert snapshot.signal_id == signal.id
      assert snapshot.symbol == signal.symbol
      assert Decimal.equal?(snapshot.current_volume_24h, signal.current_volume_24h)
      assert Decimal.equal?(snapshot.max_price_usd, signal.max_price_usd)
      assert snapshot.in_top == signal.in_top
      assert snapshot.position == signal.position
    end

    test "captures current_volume_24h correctly" do
      signal = signal_fixture(%{current_volume_24h: Decimal.new("1000000")})

      assert {:ok, snapshot} = Signals.create_snapshot_for_signal(signal)
      assert Decimal.equal?(snapshot.current_volume_24h, Decimal.new("1000000"))
    end

    test "captures max_price_usd correctly" do
      signal = signal_fixture(%{max_price_usd: Decimal.new("1.50")})

      assert {:ok, snapshot} = Signals.create_snapshot_for_signal(signal)
      assert Decimal.equal?(snapshot.max_price_usd, Decimal.new("1.50"))
    end

    test "captures in_top correctly" do
      signal = signal_fixture(%{in_top: true})

      assert {:ok, snapshot} = Signals.create_snapshot_for_signal(signal)
      assert snapshot.in_top == true
    end

    test "captures position correctly" do
      signal = signal_fixture(%{position: 5})

      assert {:ok, snapshot} = Signals.create_snapshot_for_signal(signal)
      assert snapshot.position == 5
    end

    test "always creates a new snapshot" do
      signal = signal_fixture()

      # Create first snapshot
      assert {:ok, snapshot1} = Signals.create_snapshot_for_signal(signal)

      # Create second snapshot for same signal
      assert {:ok, snapshot2} = Signals.create_snapshot_for_signal(signal)

      # Both should exist and be different
      assert snapshot1.id != snapshot2.id
      assert Repo.aggregate(SignalSnapshot, :count) == 2
    end

    test "broadcasts snapshot_created event when snapshot is created" do
      signal = signal_fixture()

      # Subscribe to PubSub topic
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "signal_snapshots:#{signal.id}")

      assert {:ok, snapshot} = Signals.create_snapshot_for_signal(signal)

      # Assert we received the broadcast
      assert_receive {:snapshot_created, ^snapshot}
    end

    test "creates snapshot for signal with nil position" do
      # Test that signals with nil position (common case) work correctly
      signal = signal_fixture(%{position: nil})

      assert {:ok, snapshot} = Signals.create_snapshot_for_signal(signal)

      assert snapshot.position == nil
      assert snapshot.symbol == signal.symbol
    end
  end

  describe "get_last_snapshot/1" do
    test "returns most recent snapshot for a signal" do
      signal = signal_fixture()

      # Create snapshots at different times
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      _old_snapshot = snapshot_fixture(signal, %{snapshot_at: DateTime.add(now, -120, :second)})
      _mid_snapshot = snapshot_fixture(signal, %{snapshot_at: DateTime.add(now, -60, :second)})
      recent_snapshot = snapshot_fixture(signal, %{snapshot_at: now})

      last = Signals.get_last_snapshot(signal.id)

      assert last.id == recent_snapshot.id
      assert DateTime.compare(last.snapshot_at, recent_snapshot.snapshot_at) == :eq
    end

    test "returns nil when no snapshots exist" do
      signal = signal_fixture()

      assert Signals.get_last_snapshot(signal.id) == nil
    end
  end

  describe "list_snapshots/1" do
    test "lists all snapshots for a signal ordered by time" do
      signal = signal_fixture()

      # Create 5 snapshots at different times
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for i <- 1..5 do
        snapshot_fixture(signal, %{snapshot_at: DateTime.add(now, -i * 60, :second)})
      end

      snapshots = Signals.list_snapshots(signal_id: signal.id)

      assert length(snapshots) == 5

      # Verify they're in ascending time order
      snapshot_times = Enum.map(snapshots, & &1.snapshot_at)
      assert snapshot_times == Enum.sort(snapshot_times, DateTime)
    end

    test "filters snapshots by from datetime" do
      signal = signal_fixture()

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      cutoff = DateTime.add(now, -120, :second)

      # Create snapshots before and after cutoff
      _old1 = snapshot_fixture(signal, %{snapshot_at: DateTime.add(now, -180, :second)})
      _old2 = snapshot_fixture(signal, %{snapshot_at: DateTime.add(now, -150, :second)})
      recent1 = snapshot_fixture(signal, %{snapshot_at: DateTime.add(now, -60, :second)})
      recent2 = snapshot_fixture(signal, %{snapshot_at: now})

      snapshots = Signals.list_snapshots(signal_id: signal.id, from: cutoff)

      assert length(snapshots) == 2
      assert Enum.map(snapshots, & &1.id) == [recent1.id, recent2.id]
    end

    test "filters snapshots by to datetime" do
      signal = signal_fixture()

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      cutoff = DateTime.add(now, -120, :second)

      # Create snapshots before and after cutoff
      old1 = snapshot_fixture(signal, %{snapshot_at: DateTime.add(now, -180, :second)})
      old2 = snapshot_fixture(signal, %{snapshot_at: DateTime.add(now, -150, :second)})
      _recent1 = snapshot_fixture(signal, %{snapshot_at: DateTime.add(now, -60, :second)})
      _recent2 = snapshot_fixture(signal, %{snapshot_at: now})

      snapshots = Signals.list_snapshots(signal_id: signal.id, to: cutoff)

      assert length(snapshots) == 2
      assert Enum.map(snapshots, & &1.id) == [old1.id, old2.id]
    end

    test "filters by both from and to datetime" do
      signal = signal_fixture()

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      from_cutoff = DateTime.add(now, -180, :second)
      to_cutoff = DateTime.add(now, -60, :second)

      # Create snapshots across a range
      _too_old = snapshot_fixture(signal, %{snapshot_at: DateTime.add(now, -200, :second)})
      in_range1 = snapshot_fixture(signal, %{snapshot_at: DateTime.add(now, -150, :second)})
      in_range2 = snapshot_fixture(signal, %{snapshot_at: DateTime.add(now, -90, :second)})
      _too_recent = snapshot_fixture(signal, %{snapshot_at: now})

      snapshots = Signals.list_snapshots(signal_id: signal.id, from: from_cutoff, to: to_cutoff)

      assert length(snapshots) == 2
      assert Enum.map(snapshots, & &1.id) == [in_range1.id, in_range2.id]
    end

    test "requires signal_id parameter" do
      now = DateTime.utc_now()

      assert_raise KeyError, fn ->
        Signals.list_snapshots(from: now)
      end
    end
  end

  describe "get_snapshot_history/1" do
    test "returns complete history for a signal" do
      signal = signal_fixture()

      # Create multiple snapshots
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for i <- 1..4 do
        snapshot_fixture(signal, %{snapshot_at: DateTime.add(now, -i * 60, :second)})
      end

      history = Signals.get_snapshot_history(signal.id)

      assert length(history) == 4

      # Verify they're ordered by time
      snapshot_times = Enum.map(history, & &1.snapshot_at)
      assert snapshot_times == Enum.sort(snapshot_times, DateTime)
    end

    test "returns empty list when no snapshots exist" do
      signal = signal_fixture()

      assert Signals.get_snapshot_history(signal.id) == []
    end
  end
end
