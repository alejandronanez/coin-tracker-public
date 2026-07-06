defmodule CoinTracker.Signals.HistoricalTest do
  use CoinTracker.DataCase, async: true

  import CoinTracker.SignalsFixtures

  alias CoinTracker.Signals

  describe "list_unique_symbols/0" do
    test "returns an empty list when no signals exist" do
      assert Signals.list_unique_symbols() == []
    end

    test "returns one entry per unique symbol" do
      base = ~U[2025-01-01 00:00:00Z]

      # Three occurrences of BTC, one of ETH
      signal_fixture(%{symbol: "BTC", in_top_since: DateTime.add(base, 0, :day)})
      signal_fixture(%{symbol: "BTC", in_top_since: DateTime.add(base, 1, :day)})
      signal_fixture(%{symbol: "BTC", in_top_since: DateTime.add(base, 2, :day)})
      signal_fixture(%{symbol: "ETH", in_top_since: base})

      symbols = Signals.list_unique_symbols()
      symbol_names = Enum.map(symbols, & &1.symbol)

      assert "BTC" in symbol_names
      assert "ETH" in symbol_names
      # Each symbol appears exactly once, even though BTC has 3 rows
      assert length(Enum.filter(symbols, &(&1.symbol == "BTC"))) == 1
    end

    test "reports the correct occurrence_count for each symbol" do
      base = ~U[2025-01-01 00:00:00Z]

      signal_fixture(%{symbol: "REPEAT", in_top_since: DateTime.add(base, 0, :day)})
      signal_fixture(%{symbol: "REPEAT", in_top_since: DateTime.add(base, 1, :day)})
      signal_fixture(%{symbol: "REPEAT", in_top_since: DateTime.add(base, 2, :day)})
      signal_fixture(%{symbol: "ONCE", in_top_since: base})

      symbols = Signals.list_unique_symbols()

      repeat_entry = Enum.find(symbols, &(&1.symbol == "REPEAT"))
      once_entry = Enum.find(symbols, &(&1.symbol == "ONCE"))

      assert repeat_entry.occurrence_count == 3
      assert once_entry.occurrence_count == 1
    end

    test "sets has_active to true when any signal for the symbol is active" do
      base = ~U[2025-01-01 00:00:00Z]

      # One active signal and one inactive signal for the same symbol
      signal_fixture(%{symbol: "MIXED", in_top_since: base, active: true})
      signal_fixture(%{symbol: "MIXED", in_top_since: DateTime.add(base, 1, :day), active: false})
      signal_fixture(%{symbol: "NOPE", in_top_since: base, active: false})

      symbols = Signals.list_unique_symbols()

      mixed_entry = Enum.find(symbols, &(&1.symbol == "MIXED"))
      nope_entry = Enum.find(symbols, &(&1.symbol == "NOPE"))

      assert mixed_entry.has_active == true
      assert nope_entry.has_active == false
    end

    test "sets has_active to false when all signals for the symbol are inactive" do
      base = ~U[2025-01-01 00:00:00Z]

      signal_fixture(%{symbol: "GONE", in_top_since: base, active: false})
      signal_fixture(%{symbol: "GONE", in_top_since: DateTime.add(base, 1, :day), active: false})

      [entry] = Signals.list_unique_symbols() |> Enum.filter(&(&1.symbol == "GONE"))

      assert entry.has_active == false
    end

    test "sets has_recently_exited to true when an inactive signal exited within the last 7 days" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      recent_exit = DateTime.add(now, -3, :day)

      signal_fixture(%{
        symbol: "JUSTEXITED",
        in_top_since: DateTime.add(recent_exit, -2, :day),
        active: false,
        exit_date: recent_exit
      })

      [entry] = Signals.list_unique_symbols() |> Enum.filter(&(&1.symbol == "JUSTEXITED"))

      assert entry.has_recently_exited == true
    end

    test "sets has_recently_exited to false when the only inactive signal exited over 7 days ago" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      old_exit = DateTime.add(now, -10, :day)

      signal_fixture(%{
        symbol: "LONGGONE",
        in_top_since: DateTime.add(old_exit, -2, :day),
        active: false,
        exit_date: old_exit
      })

      [entry] = Signals.list_unique_symbols() |> Enum.filter(&(&1.symbol == "LONGGONE"))

      assert entry.has_recently_exited == false
    end

    test "sets has_recently_exited to false when all signals are still active" do
      base = ~U[2025-01-01 00:00:00Z]

      signal_fixture(%{symbol: "STILLLIVE", in_top_since: base, active: true, exit_date: nil})

      [entry] = Signals.list_unique_symbols() |> Enum.filter(&(&1.symbol == "STILLLIVE"))

      assert entry.has_recently_exited == false
    end

    test "sets has_recently_exited to true when any one inactive signal exited within the last 7 days" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      old_exit = DateTime.add(now, -30, :day)
      recent_exit = DateTime.add(now, -1, :day)

      # Same symbol: one stale inactive exit, one recent inactive exit
      signal_fixture(%{
        symbol: "MIXEDEXITS",
        in_top_since: DateTime.add(old_exit, -2, :day),
        active: false,
        exit_date: old_exit
      })

      signal_fixture(%{
        symbol: "MIXEDEXITS",
        in_top_since: DateTime.add(recent_exit, -2, :day),
        active: false,
        exit_date: recent_exit
      })

      [entry] = Signals.list_unique_symbols() |> Enum.filter(&(&1.symbol == "MIXEDEXITS"))

      assert entry.has_recently_exited == true
    end

    test "records first_seen as the earliest in_top_since across occurrences" do
      base = ~U[2025-01-01 00:00:00Z]
      earlier = DateTime.add(base, -10, :day)
      later = DateTime.add(base, 5, :day)

      signal_fixture(%{symbol: "DATES", in_top_since: base})
      signal_fixture(%{symbol: "DATES", in_top_since: earlier})
      signal_fixture(%{symbol: "DATES", in_top_since: later})

      [entry] = Signals.list_unique_symbols() |> Enum.filter(&(&1.symbol == "DATES"))

      assert DateTime.compare(entry.first_seen, earlier) == :eq
    end

    test "records last_seen as the most recent in_top_since across occurrences" do
      base = ~U[2025-01-01 00:00:00Z]
      earlier = DateTime.add(base, -10, :day)
      later = DateTime.add(base, 5, :day)

      signal_fixture(%{symbol: "LATEST", in_top_since: base})
      signal_fixture(%{symbol: "LATEST", in_top_since: earlier})
      signal_fixture(%{symbol: "LATEST", in_top_since: later})

      [entry] = Signals.list_unique_symbols() |> Enum.filter(&(&1.symbol == "LATEST"))

      assert DateTime.compare(entry.last_seen, later) == :eq
    end

    test "exposes last_exit_date as the most recent exit_date across occurrences" do
      base = ~U[2025-01-01 00:00:00Z]
      older_exit = DateTime.add(base, 2, :day)
      newer_exit = DateTime.add(base, 5, :day)

      signal_fixture(%{
        symbol: "EXITS",
        in_top_since: base,
        active: false,
        exit_date: older_exit
      })

      signal_fixture(%{
        symbol: "EXITS",
        in_top_since: DateTime.add(base, 3, :day),
        active: false,
        exit_date: newer_exit
      })

      [entry] = Signals.list_unique_symbols() |> Enum.filter(&(&1.symbol == "EXITS"))

      assert DateTime.compare(entry.last_exit_date, newer_exit) == :eq
    end

    test "last_exit_date is nil when no signal for the symbol has exited" do
      base = ~U[2025-01-01 00:00:00Z]

      signal_fixture(%{symbol: "NEVEREXITED", in_top_since: base, active: true, exit_date: nil})

      [entry] = Signals.list_unique_symbols() |> Enum.filter(&(&1.symbol == "NEVEREXITED"))

      assert entry.last_exit_date == nil
    end

    test "results are ordered alphabetically by symbol" do
      base = ~U[2025-01-01 00:00:00Z]

      # Insert in reverse order to confirm sorting is applied by the query
      signal_fixture(%{symbol: "ZZZ", in_top_since: base})
      signal_fixture(%{symbol: "AAA", in_top_since: base})
      signal_fixture(%{symbol: "MMM", in_top_since: base})

      symbols = Signals.list_unique_symbols()
      symbol_names = Enum.map(symbols, & &1.symbol)

      # Find the relative positions; other test symbols may also exist but
      # AAA, MMM, ZZZ must appear in that order relative to each other
      aaa_pos = Enum.find_index(symbol_names, &(&1 == "AAA"))
      mmm_pos = Enum.find_index(symbol_names, &(&1 == "MMM"))
      zzz_pos = Enum.find_index(symbol_names, &(&1 == "ZZZ"))

      assert aaa_pos < mmm_pos
      assert mmm_pos < zzz_pos
    end
  end

  describe "get_all_occurrences/1" do
    test "returns an empty list when the symbol has no signals" do
      assert Signals.get_all_occurrences("UNKNOWN") == []
    end

    test "returns one enriched map per signal for the given symbol" do
      base = ~U[2025-01-01 00:00:00Z]

      signal_fixture(%{symbol: "HIST", in_top_since: base})
      signal_fixture(%{symbol: "HIST", in_top_since: DateTime.add(base, 1, :day)})
      # A different symbol — must not be included
      signal_fixture(%{symbol: "OTHER", in_top_since: base})

      occurrences = Signals.get_all_occurrences("HIST")

      assert length(occurrences) == 2

      for occ <- occurrences do
        assert occ.signal.symbol == "HIST"
      end
    end

    test "orders results by most recent in_top_since first" do
      base = ~U[2025-01-01 00:00:00Z]

      _older = signal_fixture(%{symbol: "ORDER", in_top_since: DateTime.add(base, -5, :day)})
      _middle = signal_fixture(%{symbol: "ORDER", in_top_since: DateTime.add(base, -2, :day)})
      _newest = signal_fixture(%{symbol: "ORDER", in_top_since: base})

      occurrences = Signals.get_all_occurrences("ORDER")
      dates = Enum.map(occurrences, & &1.entry_at)

      # Verify descending order
      assert dates == Enum.sort(dates, {:desc, DateTime})
    end

    test "each returned map contains the expected keys" do
      base = ~U[2025-01-01 00:00:00Z]
      signal_fixture(%{symbol: "KEYS", in_top_since: base})

      [occ] = Signals.get_all_occurrences("KEYS")

      assert Map.has_key?(occ, :signal)
      assert Map.has_key?(occ, :entry_price)
      assert Map.has_key?(occ, :top_price)
      assert Map.has_key?(occ, :exit_price)
      assert Map.has_key?(occ, :entry_at)
      assert Map.has_key?(occ, :exit_at)
      assert Map.has_key?(occ, :duration_seconds)
      assert Map.has_key?(occ, :position_durations)
      assert Map.has_key?(occ, :best_position)
    end

    test "entry_price matches the signal's initial_price_usd" do
      base = ~U[2025-01-01 00:00:00Z]
      price = Decimal.new("2.50")
      signal_fixture(%{symbol: "PRICE", in_top_since: base, initial_price_usd: price})

      [occ] = Signals.get_all_occurrences("PRICE")

      assert Decimal.equal?(occ.entry_price, price)
    end

    test "exit_at is nil for a signal that is still active" do
      base = ~U[2025-01-01 00:00:00Z]
      signal_fixture(%{symbol: "ACTIVE", in_top_since: base, active: true, exit_date: nil})

      [occ] = Signals.get_all_occurrences("ACTIVE")

      assert is_nil(occ.exit_at)
    end

    test "exit_at matches exit_date for a signal that has exited" do
      base = ~U[2025-01-01 00:00:00Z]
      exit_time = DateTime.add(base, 3, :day)

      signal_fixture(%{
        symbol: "EXITED",
        in_top_since: base,
        active: false,
        exit_date: exit_time
      })

      [occ] = Signals.get_all_occurrences("EXITED")

      assert DateTime.compare(occ.exit_at, exit_time) == :eq
    end

    test "duration_seconds is positive for a signal with an exit_date" do
      base = ~U[2025-01-01 00:00:00Z]

      signal_fixture(%{
        symbol: "DUR",
        in_top_since: base,
        exit_date: DateTime.add(base, 2, :day),
        active: false
      })

      [occ] = Signals.get_all_occurrences("DUR")

      # 2 days in seconds
      assert occ.duration_seconds == 2 * 24 * 3600
    end
  end
end
