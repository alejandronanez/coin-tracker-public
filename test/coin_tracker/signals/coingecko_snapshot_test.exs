defmodule CoinTracker.Signals.CoingeckoSnapshotTest do
  use CoinTracker.DataCase, async: true

  alias CoinTracker.Signals
  alias CoinTracker.Signals.CoingeckoSnapshot

  describe "create_coingecko_snapshot/1 + get_latest_coingecko_snapshot/1" do
    test "inserts a row and returns it as the latest" do
      attrs = %{
        coingecko_id: "bitcoin",
        symbol: "BTC",
        snapshot_at: ~U[2026-05-17 12:00:00Z],
        total_volume_usd: Decimal.new("123456789"),
        price_usd: Decimal.new("50000.00"),
        price_change_percentage_24h: Decimal.new("2.5"),
        market_cap_usd: Decimal.new("1000000000")
      }

      assert {:ok, %CoingeckoSnapshot{} = snapshot} =
               Signals.create_coingecko_snapshot(attrs)

      assert snapshot.coingecko_id == "bitcoin"
      assert snapshot.symbol == "BTC"

      assert %CoingeckoSnapshot{coingecko_id: "bitcoin"} =
               Signals.get_latest_coingecko_snapshot("bitcoin")
    end

    test "get_latest returns the most recent row when multiple exist" do
      now = ~U[2026-05-17 12:00:00Z]

      {:ok, _old} = create_snapshot("ethereum", "ETH", DateTime.add(now, -3600, :second))
      {:ok, _middle} = create_snapshot("ethereum", "ETH", DateTime.add(now, -1800, :second))
      {:ok, _latest} = create_snapshot("ethereum", "ETH", now)

      assert %CoingeckoSnapshot{snapshot_at: ^now} =
               Signals.get_latest_coingecko_snapshot("ethereum")
    end

    test "get_latest returns nil for unknown coingecko_id" do
      assert Signals.get_latest_coingecko_snapshot("does-not-exist") == nil
    end
  end

  describe "get_coingecko_snapshot_at_or_before/2" do
    test "returns the row with the largest snapshot_at that is <= the cutoff" do
      now = ~U[2026-05-17 12:00:00Z]
      day_ago = DateTime.add(now, -24, :hour)

      # Three snapshots: one well before cutoff, one just before, one after.
      {:ok, _too_old} =
        create_snapshot("solana", "SOL", DateTime.add(day_ago, -3600, :second))

      {:ok, expected} =
        create_snapshot("solana", "SOL", DateTime.add(day_ago, -60, :second))

      {:ok, _after} =
        create_snapshot("solana", "SOL", DateTime.add(day_ago, 3600, :second))

      result = Signals.get_coingecko_snapshot_at_or_before("solana", day_ago)
      assert result.id == expected.id
    end

    test "returns the row exactly at the cutoff if one exists" do
      cutoff = ~U[2026-05-16 12:00:00Z]
      {:ok, expected} = create_snapshot("cardano", "ADA", cutoff)

      result = Signals.get_coingecko_snapshot_at_or_before("cardano", cutoff)
      assert result.id == expected.id
    end

    test "returns nil when no row exists at or before the cutoff" do
      now = ~U[2026-05-17 12:00:00Z]
      {:ok, _future} = create_snapshot("polkadot", "DOT", DateTime.add(now, 3600, :second))

      assert Signals.get_coingecko_snapshot_at_or_before("polkadot", now) == nil
    end

    test "scopes by coingecko_id (does not leak across coins)" do
      cutoff = ~U[2026-05-17 12:00:00Z]
      {:ok, _ada} = create_snapshot("cardano", "ADA", DateTime.add(cutoff, -60, :second))

      assert Signals.get_coingecko_snapshot_at_or_before("solana", cutoff) == nil
    end
  end

  describe "prune_coingecko_snapshots/1" do
    test "deletes rows older than the cutoff and leaves newer rows" do
      now = ~U[2026-05-17 12:00:00Z]
      cutoff = DateTime.add(now, -48, :hour)

      {:ok, _old1} =
        create_snapshot("matic", "MATIC", DateTime.add(cutoff, -3600, :second))

      {:ok, _old2} =
        create_snapshot("avalanche-2", "AVAX", DateTime.add(cutoff, -60, :second))

      {:ok, kept1} =
        create_snapshot("matic", "MATIC", DateTime.add(cutoff, 60, :second))

      {:ok, kept2} = create_snapshot("avalanche-2", "AVAX", now)

      assert {:ok, 2} = Signals.prune_coingecko_snapshots(cutoff)

      remaining_ids =
        from(s in CoingeckoSnapshot, select: s.id) |> Repo.all() |> Enum.sort()

      assert remaining_ids == Enum.sort([kept1.id, kept2.id])
    end

    test "returns 0 when nothing to prune" do
      now = ~U[2026-05-17 12:00:00Z]
      {:ok, _row} = create_snapshot("tether", "USDT", now)

      cutoff = DateTime.add(now, -1, :hour)
      assert {:ok, 0} = Signals.prune_coingecko_snapshots(cutoff)
    end
  end

  describe "changeset/2" do
    test "requires coingecko_id, symbol, and snapshot_at" do
      changeset = CoingeckoSnapshot.changeset(%CoingeckoSnapshot{}, %{})

      refute changeset.valid?
      assert %{coingecko_id: ["can't be blank"]} = errors_on(changeset)
      assert %{symbol: ["can't be blank"]} = errors_on(changeset)
      assert %{snapshot_at: ["can't be blank"]} = errors_on(changeset)
    end

    test "enforces unique (coingecko_id, snapshot_at)" do
      attrs = %{
        coingecko_id: "ripple",
        symbol: "XRP",
        snapshot_at: ~U[2026-05-17 12:00:00Z]
      }

      assert {:ok, _} = Signals.create_coingecko_snapshot(attrs)
      assert {:error, changeset} = Signals.create_coingecko_snapshot(attrs)
      assert %{coingecko_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "Signal.coingecko_id field" do
    test "can be set and read back via the Signal changeset" do
      import CoinTracker.SignalsFixtures

      signal = signal_fixture(%{coingecko_id: "bitcoin"})
      assert signal.coingecko_id == "bitcoin"

      reloaded = Signals.get_signal(signal.id)
      assert reloaded.coingecko_id == "bitcoin"
    end

    test "is nil by default for newly-created signals" do
      import CoinTracker.SignalsFixtures

      signal = signal_fixture()
      assert signal.coingecko_id == nil
    end
  end

  defp create_snapshot(coingecko_id, symbol, snapshot_at) do
    Signals.create_coingecko_snapshot(%{
      coingecko_id: coingecko_id,
      symbol: symbol,
      snapshot_at: snapshot_at
    })
  end
end
