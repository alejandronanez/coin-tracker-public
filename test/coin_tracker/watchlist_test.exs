defmodule CoinTracker.WatchlistTest do
  use CoinTracker.DataCase, async: true

  alias CoinTracker.Watchlist
  alias CoinTracker.Watchlist.Entry

  import CoinTracker.AccountsFixtures
  import CoinTracker.SignalsFixtures
  import CoinTracker.TradingFixtures

  describe "base_symbol/1" do
    test "extracts uppercased base from a symbol pair" do
      assert Watchlist.base_symbol("ETH/USDT") == "ETH"
      assert Watchlist.base_symbol("eth/usdt") == "ETH"
    end

    test "returns nil for invalid input" do
      assert Watchlist.base_symbol(nil) == nil
      assert Watchlist.base_symbol("") == nil
      assert Watchlist.base_symbol("/USDT") == nil
    end
  end

  describe "enrich/1" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "marks position as :in_top when symbol has an active in-top signal", %{user: user} do
      _signal =
        signal_fixture(%{symbol: "ETH", in_top: true, active: true, position: 3})

      position = position_fixture(user_id: user.id, symbol: "ETH", entry_rank: 5)

      [entry] = Watchlist.enrich([position])

      assert %Entry{
               base_symbol: "ETH",
               status: :in_top,
               current_rank: 3,
               entry_rank: 5,
               rank_delta: 2
             } = entry
    end

    test "marks position as :dropped when signal is in grace period", %{user: user} do
      exit_at = DateTime.add(DateTime.utc_now(), -10, :minute) |> DateTime.truncate(:second)

      _signal =
        signal_fixture(%{
          symbol: "DOGE",
          in_top: false,
          active: true,
          position: nil,
          exit_date: exit_at
        })

      position = position_fixture(user_id: user.id, symbol: "DOGE", entry_rank: 8)

      [entry] = Watchlist.enrich([position])

      assert entry.status == :dropped
      assert entry.dropped_at == exit_at
      assert entry.current_rank == nil
      assert entry.rank_delta == nil
    end

    test "marks position as :never_in_top when no signal record exists", %{user: user} do
      position = position_fixture(user_id: user.id, symbol: "RANDOM")

      [entry] = Watchlist.enrich([position])

      assert entry.status == :never_in_top
      assert entry.current_signal == nil
      assert entry.current_rank == nil
      assert entry.rank_delta == nil
      assert entry.grace_ended_at == nil
    end

    test "marks position as :exited when signal's grace period has ended", %{user: user} do
      exit_at = DateTime.add(DateTime.utc_now(), -25, :hour) |> DateTime.truncate(:second)

      _signal =
        signal_fixture(%{
          symbol: "OLD",
          in_top: false,
          active: false,
          position: nil,
          exit_date: exit_at
        })

      position = position_fixture(user_id: user.id, symbol: "OLD", entry_rank: 4)

      [entry] = Watchlist.enrich([position])

      assert entry.status == :exited
      assert entry.dropped_at == exit_at
      assert entry.grace_ended_at == DateTime.add(exit_at, 24, :hour)
      assert entry.current_rank == nil
      assert entry.rank_delta == nil
    end

    test "still uses :exited when the deactivation cron hasn't run yet", %{user: user} do
      # exit_date is past 24h but signal is still flagged active — status should
      # come from the timestamp, not the active flag, so the UI doesn't lag
      # behind the cron.
      exit_at = DateTime.add(DateTime.utc_now(), -30, :hour) |> DateTime.truncate(:second)

      _signal =
        signal_fixture(%{
          symbol: "LAG",
          in_top: false,
          active: true,
          position: nil,
          exit_date: exit_at
        })

      position = position_fixture(user_id: user.id, symbol: "LAG", entry_rank: 5)

      [entry] = Watchlist.enrich([position])

      assert entry.status == :exited
    end

    test "computes positive rank_delta when current rank is better than entry", %{user: user} do
      signal_fixture(%{symbol: "BTC", in_top: true, active: true, position: 2})
      position = position_fixture(user_id: user.id, symbol: "BTC", entry_rank: 7)

      [entry] = Watchlist.enrich([position])

      # entry_rank 7 -> current 2 means improved by 5
      assert entry.rank_delta == 5
    end

    test "computes negative rank_delta when current rank is worse than entry", %{user: user} do
      signal_fixture(%{symbol: "SOL", in_top: true, active: true, position: 9})
      position = position_fixture(user_id: user.id, symbol: "SOL", entry_rank: 3)

      [entry] = Watchlist.enrich([position])

      assert entry.rank_delta == -6
    end

    test "rank_delta is nil when entry_rank is nil", %{user: user} do
      signal_fixture(%{symbol: "AVAX", in_top: true, active: true, position: 4})
      position = position_fixture(user_id: user.id, symbol: "AVAX", entry_rank: nil)

      [entry] = Watchlist.enrich([position])

      assert entry.entry_rank == nil
      assert entry.rank_delta == nil
      assert entry.status == :in_top
    end

    test "includes 24h sparkline points for symbols with snapshots", %{user: user} do
      signal = signal_fixture(%{symbol: "ETH", in_top: true, active: true, position: 5})

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for {minutes_ago, position} <- [{60, 7}, {30, 6}, {0, 5}] do
        snapshot_at = DateTime.add(now, -minutes_ago, :minute) |> DateTime.truncate(:second)

        snapshot_fixture(signal, %{
          snapshot_at: snapshot_at,
          position: position,
          in_top: true
        })
      end

      position = position_fixture(user_id: user.id, symbol: "ETH", entry_rank: 7)

      [entry] = Watchlist.enrich([position])

      assert entry.sparkline_points == [7, 6, 5]
    end

    test "excludes snapshots older than 24 hours", %{user: user} do
      signal = signal_fixture(%{symbol: "ADA", in_top: true, active: true, position: 4})

      old = DateTime.add(DateTime.utc_now(), -25, :hour) |> DateTime.truncate(:second)
      recent = DateTime.add(DateTime.utc_now(), -1, :hour) |> DateTime.truncate(:second)

      snapshot_fixture(signal, %{snapshot_at: old, position: 9, in_top: true})
      snapshot_fixture(signal, %{snapshot_at: recent, position: 4, in_top: true})

      position = position_fixture(user_id: user.id, symbol: "ADA", entry_rank: 9)

      [entry] = Watchlist.enrich([position])

      assert entry.sparkline_points == [4]
    end

    test "batches queries for many positions", %{user: user} do
      for sym <- ["AAA", "BBB", "CCC"] do
        signal_fixture(%{symbol: sym, in_top: true, active: true, position: 1})
      end

      positions =
        for sym <- ["AAA", "BBB", "CCC"] do
          position_fixture(user_id: user.id, symbol: sym, entry_rank: 5)
        end

      entries = Watchlist.enrich(positions)

      assert length(entries) == 3
      assert Enum.all?(entries, &(&1.status == :in_top))
      assert Enum.map(entries, & &1.base_symbol) |> Enum.sort() == ["AAA", "BBB", "CCC"]
    end

    test "handles empty list" do
      assert Watchlist.enrich([]) == []
    end
  end

  describe "coverage_ratio/0" do
    test "returns 1.0 when there are no active positions" do
      assert Watchlist.coverage_ratio() == 1.0
    end

    test "returns 1.0 when all positions match a current signal" do
      user = user_fixture()
      signal_fixture(%{symbol: "ETH", in_top: true, active: true, position: 1})
      signal_fixture(%{symbol: "BTC", in_top: true, active: true, position: 2})

      position_fixture(user_id: user.id, symbol: "ETH")
      position_fixture(user_id: user.id, symbol: "BTC")

      assert Watchlist.coverage_ratio() == 1.0
    end

    test "returns 0.5 when half of positions match a current signal" do
      user = user_fixture()
      signal_fixture(%{symbol: "ETH", in_top: true, active: true, position: 1})

      position_fixture(user_id: user.id, symbol: "ETH")
      position_fixture(user_id: user.id, symbol: "RANDOM")

      assert Watchlist.coverage_ratio() == 0.5
    end

    test "ignores closed positions" do
      user = user_fixture()
      signal_fixture(%{symbol: "ETH", in_top: true, active: true, position: 1})

      position_fixture(user_id: user.id, symbol: "ETH")
      position_fixture(user_id: user.id, symbol: "RANDOM", status: :closed)

      assert Watchlist.coverage_ratio() == 1.0
    end
  end
end
