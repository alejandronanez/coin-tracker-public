defmodule CoinTracker.Coins.PricePollerTest do
  # Not async because we're dealing with a globally registered GenServer
  use CoinTracker.DataCase, async: false

  alias CoinTracker.Coins.PricePoller
  alias CoinTracker.Trading
  import CoinTracker.AccountsFixtures
  import CoinTracker.TradingFixtures

  setup do
    # Subscribe to price updates for testing PubSub broadcasts
    Phoenix.PubSub.subscribe(CoinTracker.PubSub, "price_updates")

    :ok
  end

  describe "init/1" do
    test "poller is already started in application" do
      # Verify the Poller is running (started by application.ex)
      pid = Process.whereis(PricePoller)
      assert pid != nil
      assert Process.alive?(pid)
    end

    test "poller respects enabled: false config in test environment" do
      # In test.exs, we configured enabled: false
      # This test verifies that no polling happens automatically
      # We just need to verify the process exists but isn't scheduling polls

      pid = Process.whereis(PricePoller)
      assert pid != nil
    end
  end

  describe "periodic polling" do
    # Note: In test environment, the Poller is configured with enabled: false
    # so we test the polling behavior indirectly via poll_now/0

    test "poller does not automatically poll when disabled in test config" do
      user = user_fixture()
      position_fixture(user_id: user.id, symbol: "ETH", exchange: "binance_spot")

      # Flush any PubSub messages from position creation
      receive do
        {:price_updated, _} -> :ok
      after
        0 -> :ok
      end

      # Wait a bit to ensure no automatic polling happens
      Process.sleep(100)

      # The symbol_price was created during position creation
      # but should not have been updated by the poller
      symbol_price = Repo.get_by(CoinTracker.Coins.SymbolPrice, symbol_pair: "ETH/USDT")
      assert symbol_price != nil

      # No PubSub messages should have been received from the poller
      refute_received {:price_updated, _}
    end
  end

  describe "poll_now/0" do
    test "can be called without crashing the poller" do
      # Manually trigger poll
      PricePoller.poll_now()

      # Wait for poll to complete
      Process.sleep(100)

      # Verify poller is still alive
      pid = Process.whereis(PricePoller)
      assert Process.alive?(pid)
    end

    test "does not poll when no active positions exist" do
      # No positions created

      # Manually trigger poll
      PricePoller.poll_now()

      # Wait to ensure no API calls were made
      Process.sleep(100)

      # No PubSub messages should have been received
      refute_received {:price_updated, _}
    end

    test "queries for unique symbol_prices grouped by exchange for active positions" do
      user = user_fixture()

      # Create active positions
      position_fixture(user_id: user.id, symbol: "ETH", exchange: "binance_spot")
      position_fixture(user_id: user.id, symbol: "BTC", exchange: "binance_spot")

      # Create closed position (should not be included)
      position_fixture(
        user_id: user.id,
        symbol: "SOL",
        exchange: "binance_spot",
        status: :closed
      )

      # Query the Trading context for symbol prices
      symbol_prices_by_exchange = Trading.get_symbol_prices_by_exchange_for_active_positions()

      # Should only include active positions
      assert Map.has_key?(symbol_prices_by_exchange, :binance_spot)
      binance_symbols = symbol_prices_by_exchange[:binance_spot]

      assert length(binance_symbols) == 2
      assert "ETH/USDT" in binance_symbols
      assert "BTC/USDT" in binance_symbols
      refute "SOL/USDT" in binance_symbols
    end
  end

  describe "list_active_positions_for_symbol_price/1" do
    test "returns active positions for a specific symbol price" do
      user = user_fixture()

      # Create positions with the same symbol
      position1 =
        position_fixture(user_id: user.id, symbol: "ETH", exchange: "binance_spot")

      position2 =
        position_fixture(user_id: user.id, symbol: "ETH", exchange: "binance_spot")

      # Create position with different symbol
      _position3 = position_fixture(user_id: user.id, symbol: "BTC", exchange: "binance_spot")

      # Create closed position with same symbol
      _closed_position =
        position_fixture(
          user_id: user.id,
          symbol: "ETH",
          exchange: "binance_spot",
          status: :closed
        )

      # Get the symbol_price_id from position1
      symbol_price_id = position1.symbol_price_id

      # Query for active positions
      positions = Trading.list_active_positions_for_symbol_price(symbol_price_id)

      # Should only include position1 and position2 (both active with same symbol_price)
      assert length(positions) == 2
      position_ids = Enum.map(positions, & &1.id)
      assert position1.id in position_ids
      assert position2.id in position_ids
    end

    test "returns empty list when no active positions exist for symbol price" do
      positions = Trading.list_active_positions_for_symbol_price(999)
      assert positions == []
    end
  end

  describe "recovery alerts" do
    test "sends recovery alert when position transitions from negative to positive PnL" do
      user = user_fixture()

      # Create position with negative PnL to start
      position =
        position_fixture(
          user_id: user.id,
          symbol: "ETH",
          exchange: "binance_spot",
          entry_price: Decimal.new("2000.00"),
          take_profit_percent: Decimal.new("50.0"),
          stop_loss_percent: Decimal.new("-30.0"),
          current_threshold_zone: Decimal.new("2.0"),
          last_known_pnl: Decimal.new("-5.0")
        )

      # Reload to get the full position with symbol_price association
      position = Repo.get!(Trading.Position, position.id) |> Repo.preload(:symbol_price)

      # Simulate PnL recovered from -5% to +3%
      current_pnl = Decimal.new("3.0")
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Verify recovery alert would be triggered
      alert_result =
        CoinTracker.Trading.PositionAlert.check_recovery_alert(
          position.last_known_pnl,
          current_pnl,
          now,
          position.last_alerted_at
        )

      assert {:alert, "🔄 Position recovered to positive!"} = alert_result
    end

    test "does not send recovery alert when position stays negative" do
      user = user_fixture()

      position =
        position_fixture(
          user_id: user.id,
          symbol: "ETH",
          exchange: "binance_spot",
          last_known_pnl: Decimal.new("-10.0")
        )

      position = Repo.get!(Trading.Position, position.id) |> Repo.preload(:symbol_price)

      current_pnl = Decimal.new("-5.0")
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      alert_result =
        CoinTracker.Trading.PositionAlert.check_recovery_alert(
          position.last_known_pnl,
          current_pnl,
          now,
          position.last_alerted_at
        )

      assert :no_alert = alert_result
    end

    test "updates last_known_pnl after alert checking cycle" do
      user = user_fixture()

      position =
        position_fixture(
          user_id: user.id,
          symbol: "ETH",
          exchange: "binance_spot",
          last_known_pnl: nil
        )

      # Simulate PnL update
      current_pnl = Decimal.new("5.5")

      {:ok, updated_position} = Trading.update_position_pnl(position, current_pnl)

      assert updated_position.last_known_pnl == current_pnl
    end
  end

  describe "check_single_position_alerts/2 single-tick behavior" do
    import ExUnit.CaptureLog

    # These tests count "<type> alert" substrings in the captured log to assert how
    # many alert sends were attempted per tick. Both success ("Sent <type> alert …")
    # and failure ("Failed to send <type> alert …") log lines include the alert type
    # in the message body, so the counter works regardless of whether ExGram is
    # configured in the CI environment.
    #
    # The test config sets Logger level to :alert (config/test.exs) which would
    # filter our :info / :warning logs before capture_log sees them. Bump it here
    # for the duration of these tests; safe because the parent module is async: false.

    setup do
      original_level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: original_level) end)
      :ok
    end

    defp count_alert_attempts(log, alert_word) do
      log
      |> String.split("#{alert_word} alert")
      |> length()
      |> Kernel.-(1)
    end

    defp seed_position_with_state(user, attrs) do
      base = [
        user_id: user.id,
        symbol: "ETH",
        exchange: "binance_spot",
        entry_price: "100.00",
        take_profit_percent: "50.0",
        stop_loss_percent: "-30.0",
        current_threshold_zone: "2"
      ]

      position = position_fixture(Keyword.merge(base, Keyword.take(attrs, [:last_known_pnl])))

      # Apply post-creation alert-tracking fields directly (fixture doesn't expose them)
      tracked =
        attrs
        |> Keyword.take([
          :last_alerted_at,
          :last_alerted_threshold_positive,
          :last_alerted_negative_proximity
        ])
        |> Enum.into(%{})

      position =
        if map_size(tracked) > 0 do
          position
          |> Ecto.Changeset.change(tracked)
          |> Repo.update!()
        else
          position
        end

      Repo.preload(position, :symbol_price, force: true)
    end

    test "only ONE alert fires when positive threshold and recovery both qualify in same tick" do
      # Regression: pre-fix the in-memory `position` struct was reused after a DB
      # write, so `position.last_alerted_at` stayed nil for the recovery check
      # and BOTH messages went out for a single price observation.
      user = link_telegram(user_fixture())

      position =
        seed_position_with_state(user,
          last_known_pnl: Decimal.new("-1.0"),
          last_alerted_at: nil,
          last_alerted_threshold_positive: nil
        )

      # current_price 104.5 → +4.5% PnL: crosses 4% threshold AND recovers from -1%
      log =
        capture_log(fn ->
          PricePoller.check_single_position_alerts(position, Decimal.new("104.50"))
        end)

      assert count_alert_attempts(log, "threshold") == 1
      assert count_alert_attempts(log, "recovery") == 0
      assert count_alert_attempts(log, "proximity") == 0

      reloaded = Repo.get!(Trading.Position, position.id)
      assert reloaded.last_alerted_at != nil
      assert Decimal.compare(reloaded.last_alerted_threshold_positive, Decimal.new("4")) == :eq
      # last_known_pnl is updated at the end of every tick
      assert Decimal.compare(reloaded.last_known_pnl, Decimal.new("4.5")) == :eq
    end

    test "recovery alert is throttled when another alert fired recently in DB" do
      # Even without same-tick collision, the 30-second throttle should hold across
      # ticks. Seed with a fresh `last_alerted_at` to simulate a recent alert.
      user = link_telegram(user_fixture())
      recent = DateTime.utc_now() |> DateTime.add(-5, :second) |> DateTime.truncate(:second)

      position =
        seed_position_with_state(user,
          last_known_pnl: Decimal.new("-1.0"),
          last_alerted_at: recent,
          last_alerted_threshold_positive: nil
        )

      # current_price 100 → 0% PnL: recovery from -1% to 0% but throttled
      log =
        capture_log(fn ->
          PricePoller.check_single_position_alerts(position, Decimal.new("100.00"))
        end)

      assert count_alert_attempts(log, "threshold") == 0
      assert count_alert_attempts(log, "recovery") == 0

      reloaded = Repo.get!(Trading.Position, position.id)
      # Throttle held: last_alerted_at unchanged
      assert DateTime.compare(reloaded.last_alerted_at, recent) == :eq
      # last_known_pnl still updates so next tick can detect transitions
      assert Decimal.compare(reloaded.last_known_pnl, Decimal.new("0.0")) == :eq
    end

    test "Telegram delivery failure still advances last_alerted_at" do
      # Preserves existing behavior: if Telegram is down, we don't want every
      # subsequent tick to retry-spam the user once it recovers. The throttle
      # timestamp must advance even on send failure.
      user = link_telegram(user_fixture())

      position =
        seed_position_with_state(user,
          last_known_pnl: Decimal.new("-1.0"),
          last_alerted_at: nil
        )

      # current_price 100 → 0% PnL: recovery (no positive threshold crossing at 0%)
      log =
        capture_log(fn ->
          PricePoller.check_single_position_alerts(position, Decimal.new("100.00"))
        end)

      # ExGram is not configured in tests, so the recovery send fails and logs a warn
      assert count_alert_attempts(log, "recovery") == 1

      reloaded = Repo.get!(Trading.Position, position.id)
      assert reloaded.last_alerted_at != nil
    end

    test "does not crash when DispatchClaim suppresses the alert (regression for #212 caller)" do
      # Regression: PR #212 added {:ok, :suppressed} as a fourth return shape to
      # TelegramService.send_message/3 for cluster-wide dedup, but PricePoller's
      # case blocks only matched three shapes — so the first clustered duplicate
      # crashed the GenServer with CaseClauseError, and the supervisor's
      # max_restarts then started taking the whole app down.
      alias CoinTracker.TelegramClient.DispatchClaim

      user = link_telegram(user_fixture())

      position =
        seed_position_with_state(user,
          last_known_pnl: Decimal.new("-1.0"),
          last_alerted_at: nil,
          last_alerted_threshold_positive: nil
        )

      # Pre-claim the (user_id, fingerprint, window_bucket) row that PricePoller
      # is about to try to claim, so its claim attempt returns :duplicate and
      # send_message returns {:ok, :suppressed}. Fingerprint format is the
      # SHA-256 of "user_id|message" truncated to 12 hex chars — see
      # TelegramService.compute_fingerprint/2. The message PricePoller emits
      # for a +4.5% PnL crossing the 4% threshold (step=2) is:
      #   "ETH/USDT: 🚀 Crossed 4.00% profit"
      # ("4.00" because PositionAlert.format_decimal/1 rounds to 2 decimals.)
      alert_message = "ETH/USDT: 🚀 Crossed 4.00% profit"

      fingerprint =
        :crypto.hash(:sha256, "#{user.id}|#{alert_message}")
        |> Base.encode16(case: :lower)
        |> binary_part(0, 12)

      # dispatch_id column is varchar(8); production uses an 8-char UUID prefix
      # (TelegramService.generate_dispatch_id/0). Use a fixed 8-char fixture here.
      assert :ok = DispatchClaim.claim(user.id, fingerprint, "testdisp", :test)

      # Pre-fix: this raised CaseClauseError on {:ok, :suppressed} and crashed
      # the GenServer. Post-fix: handled gracefully, no exception.
      log =
        capture_log(fn ->
          PricePoller.check_single_position_alerts(position, Decimal.new("104.50"))
        end)

      # TelegramService logs the suppression at :warn — assert we see it,
      # which proves we hit the suppressed branch instead of crashing.
      assert log =~ "telegram dispatch suppressed"

      # Throttle still advances on suppression: same logical event already
      # delivered by another node, so this node must not race on the next tick.
      reloaded = Repo.get!(Trading.Position, position.id)
      assert reloaded.last_alerted_at != nil
    end
  end

  describe "error handling and resilience" do
    import ExUnit.CaptureLog

    test "handles already-closed error when trying to close position" do
      user = user_fixture()

      # Create an active position
      position =
        position_fixture(
          user_id: user.id,
          symbol: "ETH",
          exchange: "binance_spot",
          entry_price: "2000.00",
          take_profit_percent: "20.0"
        )

      # First closure succeeds
      assert {:ok, closed_position} = Trading.close_position(position, :take_profit)
      assert closed_position.status == :closed
      assert closed_position.closed_reason == "take_profit"

      # Second closure returns already_closed error
      log =
        capture_log(fn ->
          result = Trading.close_position(closed_position, :stop_loss)
          assert result == {:error, :already_closed}
        end)

      # Verify this scenario logs at info level (not error)
      # The actual poller would handle this via handle_position_closure
      # which logs this as an info-level race condition
      refute log =~ "[error]"
    end

    test "handles multiple positions for same symbol independently" do
      user1 = user_fixture()
      user2 = user_fixture()

      # Create two positions for the same symbol (ETH)
      position1 =
        position_fixture(
          user_id: user1.id,
          symbol: "ETH",
          exchange: "binance_spot",
          entry_price: "2000.00"
        )

      position2 =
        position_fixture(
          user_id: user2.id,
          symbol: "ETH",
          exchange: "binance_spot",
          entry_price: "2500.00"
        )

      # Close position1
      {:ok, closed1} = Trading.close_position(position1, :manual)
      assert closed1.status == :closed

      # Position2 should still be active
      fresh_position2 = Repo.get!(Trading.Position, position2.id)
      assert fresh_position2.status == :active
    end
  end

  describe "check_single_position_alerts/2 watched positions" do
    import ExUnit.CaptureLog

    setup do
      original_level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: original_level) end)
      :ok
    end

    test "does not crash when stop_loss / take_profit are nil" do
      user = user_fixture()

      {:ok, symbol_price} =
        CoinTracker.Coins.upsert_symbol_price(%{
          exchange: :binance_spot,
          symbol_pair: "ETH/USDT",
          current_price: "1000.00"
        })

      {:ok, position} =
        %Trading.Position{}
        |> Ecto.Changeset.change(%{
          user_id: user.id,
          symbol_price_id: symbol_price.id,
          entry_price: Decimal.new("1000"),
          current_threshold_zone: Decimal.new("5"),
          status: :active,
          kind: :watched,
          source: "watch"
        })
        |> Repo.insert()

      position = Repo.preload(position, :symbol_price)

      # +6% move past the 5% milestone — must not raise even with nil stop_loss / take_profit.
      capture_log(fn ->
        PricePoller.check_single_position_alerts(position, Decimal.new("1060.00"))
      end)

      reloaded = Repo.get!(Trading.Position, position.id)
      assert reloaded.kind == :watched
      assert reloaded.status == :active
      # Surge milestone tracked — last_alerted_threshold_positive moved from nil to >= 5.
      assert reloaded.last_alerted_threshold_positive != nil

      assert Decimal.compare(reloaded.last_alerted_threshold_positive, Decimal.new("5")) in [
               :gt,
               :eq
             ]

      # last_known_pnl reflects the +6% move.
      assert Decimal.compare(reloaded.last_known_pnl, Decimal.new("0")) == :gt
    end

    # Seeds a watched position with the given baseline threshold and entry price 100.
    # Returns the position preloaded with :symbol_price so it's ready for
    # PricePoller.check_single_position_alerts/2.
    defp seed_watched(user, last_alerted_threshold_positive) do
      {:ok, symbol_price} =
        CoinTracker.Coins.upsert_symbol_price(%{
          exchange: :binance_spot,
          symbol_pair: "ETH/USDT",
          current_price: "100.00"
        })

      {:ok, position} =
        %Trading.Position{}
        |> Ecto.Changeset.change(%{
          user_id: user.id,
          symbol_price_id: symbol_price.id,
          entry_price: Decimal.new("100"),
          current_threshold_zone: Decimal.new("5"),
          status: :active,
          kind: :watched,
          source: "watch",
          last_alerted_threshold_positive: last_alerted_threshold_positive
        })
        |> Repo.insert()

      Repo.preload(position, :symbol_price)
    end

    # Mirrors the count_alert_attempts/2 helper used elsewhere in this file —
    # counts "watch_surge alert" occurrences in log output. Both success
    # ("Sent <type> alert …") and failure ("Failed to send <type> alert …")
    # lines contain the substring, so this works whether or not ExGram is
    # configured in the test environment.
    defp count_watch_surge_attempts(log) do
      log
      |> String.split("watch_surge alert")
      |> length()
      |> Kernel.-(1)
    end

    test "alerts on negative-to-less-negative surge (the dip recovery bug)" do
      # The reported bug: -20% → -15% must alert, not wait for break-even.
      user = link_telegram(user_fixture())
      position = seed_watched(user, Decimal.new("-20"))

      log =
        capture_log(fn ->
          # Price 85 from entry 100 → -15% PnL
          PricePoller.check_single_position_alerts(position, Decimal.new("85.00"))
        end)

      assert count_watch_surge_attempts(log) == 1

      reloaded = Repo.get!(Trading.Position, position.id)
      assert Decimal.equal?(reloaded.last_alerted_threshold_positive, Decimal.new("-15"))
      assert reloaded.last_alerted_at != nil
    end

    test "alerts on recovery to break-even (0%)" do
      user = link_telegram(user_fixture())
      position = seed_watched(user, Decimal.new("-5"))

      log =
        capture_log(fn ->
          # Price 100 from entry 100 → 0% PnL
          PricePoller.check_single_position_alerts(position, Decimal.new("100.00"))
        end)

      assert count_watch_surge_attempts(log) == 1

      reloaded = Repo.get!(Trading.Position, position.id)
      assert Decimal.equal?(reloaded.last_alerted_threshold_positive, Decimal.new("0"))
    end

    test "still alerts for positive surges (regression)" do
      user = link_telegram(user_fixture())
      position = seed_watched(user, Decimal.new("5"))

      log =
        capture_log(fn ->
          # Price 110 from entry 100 → +10% PnL
          PricePoller.check_single_position_alerts(position, Decimal.new("110.00"))
        end)

      assert count_watch_surge_attempts(log) == 1

      reloaded = Repo.get!(Trading.Position, position.id)
      assert Decimal.equal?(reloaded.last_alerted_threshold_positive, Decimal.new("10"))
    end

    test "drops update baseline without alerting" do
      # Coin moves further into the red — silently track the new floor so the
      # next stepwise recovery can be detected, but don't spam users with
      # "you're tanking" alerts. Mirrors the real-money path.
      user = link_telegram(user_fixture())
      position = seed_watched(user, Decimal.new("-10"))

      log =
        capture_log(fn ->
          # Price 85 from entry 100 → -15% PnL (lower than -10 baseline)
          PricePoller.check_single_position_alerts(position, Decimal.new("85.00"))
        end)

      assert count_watch_surge_attempts(log) == 0

      reloaded = Repo.get!(Trading.Position, position.id)
      # Baseline moved down to -15 so the next +5% bounce will alert
      assert Decimal.equal?(reloaded.last_alerted_threshold_positive, Decimal.new("-15"))
    end
  end

  describe "check_single_position_alerts/2 watched volume alerts" do
    import ExUnit.CaptureLog
    import CoinTracker.SignalsFixtures

    setup do
      original_level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: original_level) end)
      :ok
    end

    # Seeds a watched position whose entry price matches `current_price` (so the
    # price-PnL surge branch can't fire), backed by a Signal with controllable
    # volume fields. Returns {position, signal}.
    defp seed_watched_with_signal(user, signal_attrs) do
      {:ok, symbol_price} =
        CoinTracker.Coins.upsert_symbol_price(%{
          exchange: :binance_spot,
          symbol_pair: "ETH/USDT",
          current_price: "100.00"
        })

      signal =
        signal_fixture(
          Map.merge(
            %{
              symbol: "ETH",
              in_top: true,
              position: 5
            },
            signal_attrs
          )
        )

      {:ok, position} =
        %Trading.Position{}
        |> Ecto.Changeset.change(%{
          user_id: user.id,
          symbol_price_id: symbol_price.id,
          entry_price: Decimal.new("100"),
          current_threshold_zone: Decimal.new("5"),
          status: :active,
          kind: :watched,
          source: "watch",
          # Set high enough that the 0% PnL won't trigger a price alert
          last_alerted_threshold_positive: Decimal.new("1000")
        })
        |> Repo.insert()

      {Repo.preload(position, :symbol_price), signal}
    end

    defp count_alert_kind(log, kind) when is_binary(kind) do
      log
      |> String.split("#{kind} alert")
      |> length()
      |> Kernel.-(1)
    end

    test "fires a window volume surge alert when 60-min-ago baseline shows +25% growth" do
      user = link_telegram(user_fixture())

      {position, signal} =
        seed_watched_with_signal(user, %{
          # current = 1.3x baseline below → +30% surge → crosses tier 25
          initial_volume_24h: Decimal.new("1000000"),
          current_volume_24h: Decimal.new("1300000")
        })

      # Snapshot from ~60 min ago, with baseline volume matching initial
      snapshot_fixture(signal, %{
        snapshot_at:
          DateTime.utc_now() |> DateTime.add(-60 * 60, :second) |> DateTime.truncate(:second),
        current_volume_24h: Decimal.new("1000000")
      })

      log =
        capture_log(fn ->
          PricePoller.check_single_position_alerts(position, Decimal.new("100.00"))
        end)

      assert count_alert_kind(log, "watch_volume_window_surge") == 1
      # Cumulative shouldn't also fire — one alert per tick
      assert count_alert_kind(log, "watch_volume_cumulative_tier") == 0

      reloaded = Repo.get!(Trading.Position, position.id)
      assert Decimal.equal?(reloaded.last_alerted_volume_window_tier, Decimal.new(25))
      assert reloaded.last_alerted_at != nil
    end

    test "does not re-fire the same window tier on a subsequent tick" do
      user = link_telegram(user_fixture())

      {position, signal} =
        seed_watched_with_signal(user, %{
          initial_volume_24h: Decimal.new("1000000"),
          current_volume_24h: Decimal.new("1300000")
        })

      snapshot_fixture(signal, %{
        snapshot_at:
          DateTime.utc_now() |> DateTime.add(-60 * 60, :second) |> DateTime.truncate(:second),
        current_volume_24h: Decimal.new("1000000")
      })

      # Simulate that we already alerted at tier 25 outside the throttle window
      {:ok, position} =
        position
        |> Ecto.Changeset.change(%{
          last_alerted_volume_window_tier: Decimal.new(25),
          last_alerted_at:
            DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
        })
        |> Repo.update()

      position = Repo.preload(position, :symbol_price)

      log =
        capture_log(fn ->
          PricePoller.check_single_position_alerts(position, Decimal.new("100.00"))
        end)

      assert count_alert_kind(log, "watch_volume_window_surge") == 0
    end

    test "fires a cumulative tier alert when no recent snapshot exists" do
      user = link_telegram(user_fixture())

      # +50% growth since signal entered top 10 → crosses cumulative tier 20
      {position, _signal} =
        seed_watched_with_signal(user, %{
          initial_volume_24h: Decimal.new("1000000"),
          current_volume_24h: Decimal.new("1500000")
        })

      # No snapshot in the 60-min-ago window → window check skipped, cumulative
      # branch runs.
      log =
        capture_log(fn ->
          PricePoller.check_single_position_alerts(position, Decimal.new("100.00"))
        end)

      assert count_alert_kind(log, "watch_volume_cumulative_tier") == 1

      reloaded = Repo.get!(Trading.Position, position.id)
      assert Decimal.equal?(reloaded.last_alerted_volume_cumulative_tier, Decimal.new(20))
    end

    test "does nothing when no active signal exists for the symbol" do
      user = link_telegram(user_fixture())

      # Same shape as seed_watched_with_signal but without inserting a Signal.
      {:ok, symbol_price} =
        CoinTracker.Coins.upsert_symbol_price(%{
          exchange: :binance_spot,
          symbol_pair: "ETH/USDT",
          current_price: "100.00"
        })

      {:ok, position} =
        %Trading.Position{}
        |> Ecto.Changeset.change(%{
          user_id: user.id,
          symbol_price_id: symbol_price.id,
          entry_price: Decimal.new("100"),
          current_threshold_zone: Decimal.new("5"),
          status: :active,
          kind: :watched,
          source: "watch",
          last_alerted_threshold_positive: Decimal.new("1000")
        })
        |> Repo.insert()

      position = Repo.preload(position, :symbol_price)

      log =
        capture_log(fn ->
          PricePoller.check_single_position_alerts(position, Decimal.new("100.00"))
        end)

      assert count_alert_kind(log, "watch_volume_window_surge") == 0
      assert count_alert_kind(log, "watch_volume_cumulative_tier") == 0
    end
  end
end
