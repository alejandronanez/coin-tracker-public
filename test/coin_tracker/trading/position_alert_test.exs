defmodule CoinTracker.Trading.PositionAlertTest do
  use ExUnit.Case

  alias CoinTracker.Trading.PositionAlert

  describe "calculate_current_threshold/2" do
    test "returns 0 when profit is below first threshold" do
      current_pnl = Decimal.new("1.5")
      step = Decimal.new("2")

      result = PositionAlert.calculate_current_threshold(current_pnl, step)

      assert Decimal.equal?(result, Decimal.new("0"))
    end

    test "returns 2 when profit is exactly 2%" do
      current_pnl = Decimal.new("2.0")
      step = Decimal.new("2")

      result = PositionAlert.calculate_current_threshold(current_pnl, step)

      assert Decimal.equal?(result, Decimal.new("2"))
    end

    test "returns 4 when profit is 5.5% with 2% step" do
      current_pnl = Decimal.new("5.5")
      step = Decimal.new("2")

      result = PositionAlert.calculate_current_threshold(current_pnl, step)

      assert Decimal.equal?(result, Decimal.new("4"))
    end

    test "returns 6 when profit is 6.9% with 2% step" do
      current_pnl = Decimal.new("6.9")
      step = Decimal.new("2")

      result = PositionAlert.calculate_current_threshold(current_pnl, step)

      assert Decimal.equal?(result, Decimal.new("6"))
    end

    test "works with 4% step size" do
      current_pnl = Decimal.new("11.5")
      step = Decimal.new("4")

      result = PositionAlert.calculate_current_threshold(current_pnl, step)

      assert Decimal.equal?(result, Decimal.new("8"))
    end

    test "works with 50% step size" do
      current_pnl = Decimal.new("75")
      step = Decimal.new("50")

      result = PositionAlert.calculate_current_threshold(current_pnl, step)

      assert Decimal.equal?(result, Decimal.new("50"))
    end

    test "works with negative profit" do
      current_pnl = Decimal.new("-5.5")
      step = Decimal.new("2")

      result = PositionAlert.calculate_current_threshold(current_pnl, step)

      # -5.5 / 2 = -2.75, round(:down) = -2, -2 * 2 = -4
      assert Decimal.equal?(result, Decimal.new("-4"))
    end
  end

  describe "seconds_since_alert/1" do
    test "returns 999999 when never alerted (nil)" do
      result = PositionAlert.seconds_since_alert(nil)

      assert result == 999_999
    end

    test "returns 0 for very recent alert" do
      now = DateTime.utc_now()
      result = PositionAlert.seconds_since_alert(now, now)

      assert result == 0
    end

    test "returns 60 for alert 60 seconds ago" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -60, :second)
      result = PositionAlert.seconds_since_alert(past, now)

      assert result == 60
    end
  end

  describe "check_positive_alert/3" do
    setup do
      now = DateTime.utc_now()
      past_30 = DateTime.add(now, -30, :second)
      past_20 = DateTime.add(now, -20, :second)

      {:ok, now: now, past_30: past_30, past_20: past_20}
    end

    test "alerts when crossing first threshold", %{now: now} do
      position = %{
        current_threshold_zone: Decimal.new("2"),
        last_alerted_threshold_positive: nil,
        last_alerted_at: nil
      }

      current_pnl = Decimal.new("2.5")

      result = PositionAlert.check_positive_alert(position, current_pnl, now)

      assert {:alert, "🚀 Crossed 2.00% profit"} = result
    end

    test "alerts when crossing new higher threshold", %{now: now, past_30: past_30} do
      position = %{
        current_threshold_zone: Decimal.new("2"),
        last_alerted_threshold_positive: Decimal.new("2"),
        last_alerted_at: past_30
      }

      current_pnl = Decimal.new("5.5")

      result = PositionAlert.check_positive_alert(position, current_pnl, now)

      assert {:alert, "🚀 Crossed 4.00% profit"} = result
    end

    test "does not alert when still in same threshold", %{now: now} do
      position = %{
        current_threshold_zone: Decimal.new("2"),
        last_alerted_threshold_positive: Decimal.new("2"),
        last_alerted_at: nil
      }

      current_pnl = Decimal.new("3.0")

      result = PositionAlert.check_positive_alert(position, current_pnl, now)

      assert :no_alert = result
    end

    test "does not alert when price dropped below threshold", %{now: now} do
      position = %{
        current_threshold_zone: Decimal.new("2"),
        last_alerted_threshold_positive: Decimal.new("4"),
        last_alerted_at: nil
      }

      current_pnl = Decimal.new("3.5")

      result = PositionAlert.check_positive_alert(position, current_pnl, now)

      assert :no_alert = result
    end

    test "throttles alerts within 30 seconds", %{now: now, past_20: past_20} do
      position = %{
        current_threshold_zone: Decimal.new("2"),
        last_alerted_threshold_positive: Decimal.new("2"),
        last_alerted_at: past_20
      }

      current_pnl = Decimal.new("5.5")

      result = PositionAlert.check_positive_alert(position, current_pnl, now)

      assert :no_alert = result
    end

    test "allows alert after 30 seconds have passed", %{now: now, past_30: past_30} do
      position = %{
        current_threshold_zone: Decimal.new("2"),
        last_alerted_threshold_positive: Decimal.new("2"),
        last_alerted_at: past_30
      }

      current_pnl = Decimal.new("5.5")

      result = PositionAlert.check_positive_alert(position, current_pnl, now)

      assert {:alert, "🚀 Crossed 4.00% profit"} = result
    end

    test "re-alerts when price drops and comes back up", %{now: now, past_30: past_30} do
      position = %{
        current_threshold_zone: Decimal.new("2"),
        last_alerted_threshold_positive: Decimal.new("4"),
        last_alerted_at: past_30
      }

      current_pnl = Decimal.new("5.5")

      result = PositionAlert.check_positive_alert(position, current_pnl, now)

      assert :no_alert = result
    end

    test "alerts when re-crossing after dropping below threshold", %{now: now, past_30: past_30} do
      # Scenario: Previously alerted at 2%, then price dropped to 0% zone,
      # now price is back at 2%. After the drop, last_alerted_threshold_positive
      # should have been updated to 0% by the system, so we can re-cross.
      position = %{
        current_threshold_zone: Decimal.new("2"),
        last_alerted_threshold_positive: Decimal.new("0"),
        last_alerted_at: past_30
      }

      current_pnl = Decimal.new("2.5")

      result = PositionAlert.check_positive_alert(position, current_pnl, now)

      # Should alert because 2% > 0% (re-crossing the 2% threshold)
      assert {:alert, "🚀 Crossed 2.00% profit"} = result
    end

    test "does not alert on negative threshold recovery", %{now: now, past_30: past_30} do
      # Scenario: Position recovering from -4% loss to -2% loss
      # Still negative, so should NOT trigger positive threshold alert
      position = %{
        current_threshold_zone: Decimal.new("2"),
        last_alerted_threshold_positive: Decimal.new("-4"),
        last_alerted_at: past_30
      }

      current_pnl = Decimal.new("-2.5")

      result = PositionAlert.check_positive_alert(position, current_pnl, now)

      # Should NOT alert because -2% is still negative (not profit)
      # Positive threshold alerts should only trigger for positive thresholds
      assert :no_alert = result
    end
  end

  describe "check_watch_surge_alert/3" do
    setup do
      now = DateTime.utc_now()
      past_30 = DateTime.add(now, -30, :second)
      past_20 = DateTime.add(now, -20, :second)

      {:ok, now: now, past_30: past_30, past_20: past_20}
    end

    test "alerts on negative-to-less-negative step crossing (the dip recovery bug)",
         %{now: now} do
      # Coin was -20%, now -15% — must alert even though still in red.
      position = %{
        current_threshold_zone: Decimal.new("5"),
        last_alerted_threshold_positive: Decimal.new("-20"),
        last_alerted_at: nil
      }

      result =
        PositionAlert.check_watch_surge_alert(position, Decimal.new("-15"), now)

      assert {:alert, threshold} = result
      assert Decimal.equal?(threshold, Decimal.new("-15"))
    end

    test "alerts on recovery to break-even (0%)", %{now: now} do
      position = %{
        current_threshold_zone: Decimal.new("5"),
        last_alerted_threshold_positive: Decimal.new("-5"),
        last_alerted_at: nil
      }

      result = PositionAlert.check_watch_surge_alert(position, Decimal.new("0"), now)

      assert {:alert, threshold} = result
      assert Decimal.equal?(threshold, Decimal.new("0"))
    end

    test "alerts on first positive step (0 → +5)", %{now: now} do
      position = %{
        current_threshold_zone: Decimal.new("5"),
        last_alerted_threshold_positive: nil,
        last_alerted_at: nil
      }

      result =
        PositionAlert.check_watch_surge_alert(position, Decimal.new("5.5"), now)

      assert {:alert, threshold} = result
      assert Decimal.equal?(threshold, Decimal.new("5"))
    end

    test "alerts on continued surge (+5 → +10)", %{now: now, past_30: past_30} do
      position = %{
        current_threshold_zone: Decimal.new("5"),
        last_alerted_threshold_positive: Decimal.new("5"),
        last_alerted_at: past_30
      }

      result =
        PositionAlert.check_watch_surge_alert(position, Decimal.new("10.1"), now)

      assert {:alert, threshold} = result
      assert Decimal.equal?(threshold, Decimal.new("10"))
    end

    test "does not alert when threshold is unchanged", %{now: now} do
      position = %{
        current_threshold_zone: Decimal.new("5"),
        last_alerted_threshold_positive: Decimal.new("-15"),
        last_alerted_at: nil
      }

      # PnL of -13 still rounds toward zero into the -10 bucket — that's higher
      # than -15, so it WOULD alert. Use -16 (still in -15 bucket) to test no-op.
      result =
        PositionAlert.check_watch_surge_alert(position, Decimal.new("-16"), now)

      assert :no_alert = result
    end

    test "does not alert when threshold dropped (caller persists baseline)",
         %{now: now} do
      position = %{
        current_threshold_zone: Decimal.new("5"),
        last_alerted_threshold_positive: Decimal.new("10"),
        last_alerted_at: nil
      }

      result =
        PositionAlert.check_watch_surge_alert(position, Decimal.new("3"), now)

      assert :no_alert = result
    end

    test "throttles within 30 seconds even on valid upward crossing",
         %{now: now, past_20: past_20} do
      position = %{
        current_threshold_zone: Decimal.new("5"),
        last_alerted_threshold_positive: Decimal.new("-20"),
        last_alerted_at: past_20
      }

      result =
        PositionAlert.check_watch_surge_alert(position, Decimal.new("-15"), now)

      assert :no_alert = result
    end
  end

  describe "watch_surge_message/1" do
    test "uses 'Up X%' wording for positive thresholds" do
      assert PositionAlert.watch_surge_message(Decimal.new("5")) ==
               "📈 Up 5.00% since entering the top 10"

      assert PositionAlert.watch_surge_message(Decimal.new("10")) ==
               "📈 Up 10.00% since entering the top 10"
    end

    test "uses 'Back to break-even' wording at exactly 0%" do
      assert PositionAlert.watch_surge_message(Decimal.new("0")) ==
               "🔄 Back to break-even since entering the top 10"
    end

    test "uses 'Recovering to -X%' wording for negative thresholds" do
      assert PositionAlert.watch_surge_message(Decimal.new("-15")) ==
               "🔼 Recovering to -15.00% since entering the top 10"

      assert PositionAlert.watch_surge_message(Decimal.new("-5")) ==
               "🔼 Recovering to -5.00% since entering the top 10"
    end
  end

  describe "check_recovery_alert/4" do
    setup do
      now = DateTime.utc_now()
      past_30 = DateTime.add(now, -30, :second)

      {:ok, now: now, past_30: past_30}
    end

    test "alerts when recovering from negative to positive", %{now: now} do
      last_pnl = Decimal.new("-2")
      current_pnl = Decimal.new("2")

      result = PositionAlert.check_recovery_alert(last_pnl, current_pnl, now, nil)

      assert {:alert, "🔄 Position recovered to positive!"} = result
    end

    test "does not alert when staying positive", %{now: now} do
      last_pnl = Decimal.new("2")
      current_pnl = Decimal.new("5")

      result = PositionAlert.check_recovery_alert(last_pnl, current_pnl, now, nil)

      assert :no_alert = result
    end

    test "does not alert when staying negative", %{now: now} do
      last_pnl = Decimal.new("-5")
      current_pnl = Decimal.new("-2")

      result = PositionAlert.check_recovery_alert(last_pnl, current_pnl, now, nil)

      assert :no_alert = result
    end

    test "throttles recovery alerts", %{now: now} do
      last_pnl = Decimal.new("-2")
      current_pnl = Decimal.new("2")

      # Simulate recent alert (within 30 seconds)
      past_20 = DateTime.add(now, -20, :second)

      result = PositionAlert.check_recovery_alert(last_pnl, current_pnl, now, past_20)

      assert :no_alert = result
    end
  end

  describe "check_negative_proximity_alert/3" do
    setup do
      now = DateTime.utc_now()
      past_30 = DateTime.add(now, -30, :second)

      {:ok, now: now, past_30: past_30}
    end

    test "alerts when entering 80% proximity zone", %{now: now} do
      position = %{
        stop_loss_percent: Decimal.new("-20"),
        last_alerted_negative_proximity: nil,
        last_alerted_at: nil
      }

      current_pnl = Decimal.new("-16.5")

      result = PositionAlert.check_negative_proximity_alert(position, current_pnl, now)

      assert {:alert, message, 80} = result
      assert String.contains?(message, "80%")
      assert String.contains?(message, "-16.50%")
    end

    test "alerts when entering 85% proximity zone", %{now: now} do
      position = %{
        stop_loss_percent: Decimal.new("-20"),
        last_alerted_negative_proximity: nil,
        last_alerted_at: nil
      }

      current_pnl = Decimal.new("-17.5")

      result = PositionAlert.check_negative_proximity_alert(position, current_pnl, now)

      assert {:alert, message, 85} = result
      assert String.contains?(message, "85%")
    end

    test "alerts on worse proximity level", %{now: now, past_30: past_30} do
      position = %{
        stop_loss_percent: Decimal.new("-20"),
        last_alerted_negative_proximity: 80,
        last_alerted_at: past_30
      }

      current_pnl = Decimal.new("-18")

      result = PositionAlert.check_negative_proximity_alert(position, current_pnl, now)

      assert {:alert, message, 90} = result
      assert String.contains?(message, "90%")
    end

    test "does not alert if same proximity level", %{now: now} do
      position = %{
        stop_loss_percent: Decimal.new("-20"),
        last_alerted_negative_proximity: 85,
        last_alerted_at: nil
      }

      current_pnl = Decimal.new("-17.2")

      result = PositionAlert.check_negative_proximity_alert(position, current_pnl, now)

      assert :no_alert = result
    end

    test "does not alert if recovering from proximity zone", %{now: now} do
      position = %{
        stop_loss_percent: Decimal.new("-20"),
        last_alerted_negative_proximity: 85,
        last_alerted_at: nil
      }

      current_pnl = Decimal.new("-16.5")

      result = PositionAlert.check_negative_proximity_alert(position, current_pnl, now)

      assert :no_alert = result
    end

    test "does not alert when not in any proximity zone", %{now: now} do
      position = %{
        stop_loss_percent: Decimal.new("-20"),
        last_alerted_negative_proximity: nil,
        last_alerted_at: nil
      }

      current_pnl = Decimal.new("-10")

      result = PositionAlert.check_negative_proximity_alert(position, current_pnl, now)

      assert :no_alert = result
    end

    test "throttles alerts within 30 seconds", %{now: now} do
      position = %{
        stop_loss_percent: Decimal.new("-20"),
        last_alerted_negative_proximity: 80,
        last_alerted_at: DateTime.add(now, -20, :second)
      }

      current_pnl = Decimal.new("-18")

      result = PositionAlert.check_negative_proximity_alert(position, current_pnl, now)

      assert :no_alert = result
    end
  end

  describe "check_closure_alert/4" do
    test "alerts on take-profit without amount_invested" do
      zones = %{
        take_profit: Decimal.new("25"),
        stop_loss: Decimal.new("-20")
      }

      current_pnl = Decimal.new("26")
      current_price = Decimal.new("125")

      result = PositionAlert.check_closure_alert(current_pnl, zones, current_price)

      assert {:close, :take_profit, message} = result
      assert String.contains?(message, "🎯")
      assert String.contains?(message, "Take-profit")
      assert String.contains?(message, "125")
      assert String.contains?(message, "Check your exchange to see your PnL.")
    end

    test "alerts on stop-loss without amount_invested" do
      zones = %{
        take_profit: Decimal.new("25"),
        stop_loss: Decimal.new("-20")
      }

      current_pnl = Decimal.new("-21")
      current_price = Decimal.new("79")

      result = PositionAlert.check_closure_alert(current_pnl, zones, current_price)

      assert {:close, :stop_loss, message} = result
      assert String.contains?(message, "🛑")
      assert String.contains?(message, "Stop-loss")
      assert String.contains?(message, "79")
      assert String.contains?(message, "Check your exchange to see your PnL.")
    end

    test "does not alert when in between targets" do
      zones = %{
        take_profit: Decimal.new("25"),
        stop_loss: Decimal.new("-20")
      }

      current_pnl = Decimal.new("10")
      current_price = Decimal.new("110")

      result = PositionAlert.check_closure_alert(current_pnl, zones, current_price)

      assert :no_close = result
    end

    test "alerts at exact take-profit threshold" do
      zones = %{
        take_profit: Decimal.new("25"),
        stop_loss: Decimal.new("-20")
      }

      current_pnl = Decimal.new("25")
      current_price = Decimal.new("125")

      result = PositionAlert.check_closure_alert(current_pnl, zones, current_price)

      assert {:close, :take_profit, _message} = result
    end

    test "alerts at exact stop-loss threshold" do
      zones = %{
        take_profit: Decimal.new("25"),
        stop_loss: Decimal.new("-20")
      }

      current_pnl = Decimal.new("-20")
      current_price = Decimal.new("80")

      result = PositionAlert.check_closure_alert(current_pnl, zones, current_price)

      assert {:close, :stop_loss, _message} = result
    end

    test "formats positive PnL with amount_invested on take-profit" do
      zones = %{
        take_profit: Decimal.new("5"),
        stop_loss: Decimal.new("-20")
      }

      # 5% gain on $1000 = $50 profit
      current_pnl = Decimal.new("5")
      current_price = Decimal.new("105")
      amount_invested = Decimal.new("1000")

      result =
        PositionAlert.check_closure_alert(current_pnl, zones, current_price, amount_invested)

      assert {:close, :take_profit, message} = result
      assert String.contains?(message, "🎯")
      assert String.contains?(message, "Take-profit")
      assert String.contains?(message, "PnL: ~+$50")
      assert String.contains?(message, "(+5.00%)")
    end

    test "formats negative PnL with amount_invested on stop-loss" do
      zones = %{
        take_profit: Decimal.new("25"),
        stop_loss: Decimal.new("-10")
      }

      # -10% loss on $1000 = -$100 loss
      current_pnl = Decimal.new("-10")
      current_price = Decimal.new("90")
      amount_invested = Decimal.new("1000")

      result =
        PositionAlert.check_closure_alert(current_pnl, zones, current_price, amount_invested)

      assert {:close, :stop_loss, message} = result
      assert String.contains?(message, "🛑")
      assert String.contains?(message, "Stop-loss")
      assert String.contains?(message, "PnL: ~-$100")
      assert String.contains?(message, "(-10.00%)")
    end

    test "handles decimal amount_invested correctly" do
      zones = %{
        take_profit: Decimal.new("10"),
        stop_loss: Decimal.new("-20")
      }

      # 10% gain on $500.50 = $50.05 profit
      current_pnl = Decimal.new("10")
      current_price = Decimal.new("110")
      amount_invested = Decimal.new("500.50")

      result =
        PositionAlert.check_closure_alert(current_pnl, zones, current_price, amount_invested)

      assert {:close, :take_profit, message} = result
      assert String.contains?(message, "PnL: ~+$50.05")
      assert String.contains?(message, "(+10.00%)")
    end
  end

  describe "highest_crossed_tier/2" do
    test "returns nil when growth is below the smallest tier" do
      assert PositionAlert.highest_crossed_tier(Decimal.new("5"), [10, 25, 50]) == nil
    end

    test "returns nil when growth is negative" do
      assert PositionAlert.highest_crossed_tier(Decimal.new("-3"), [10, 25, 50]) == nil
    end

    test "returns the smallest tier when growth equals it exactly" do
      result = PositionAlert.highest_crossed_tier(Decimal.new("10"), [10, 25, 50])
      assert Decimal.equal?(result, Decimal.new(10))
    end

    test "returns the largest tier crossed" do
      result = PositionAlert.highest_crossed_tier(Decimal.new("30"), [10, 25, 50])
      assert Decimal.equal?(result, Decimal.new(25))
    end

    test "returns the top tier when growth exceeds it" do
      result = PositionAlert.highest_crossed_tier(Decimal.new("75"), [10, 25, 50])
      assert Decimal.equal?(result, Decimal.new(50))
    end

    test "sorts unsorted tier lists before comparing" do
      result = PositionAlert.highest_crossed_tier(Decimal.new("30"), [50, 10, 25])
      assert Decimal.equal?(result, Decimal.new(25))
    end
  end

  describe "check_volume_window_surge/4" do
    setup do
      now = DateTime.utc_now()
      past_30 = DateTime.add(now, -30, :second)
      past_20 = DateTime.add(now, -20, :second)
      {:ok, now: now, past_30: past_30, past_20: past_20}
    end

    test "alerts when growth crosses the first tier", %{now: now} do
      position = %{
        last_alerted_volume_window_tier: nil,
        last_alerted_at: nil
      }

      # 100 → 115 = +15% → tier 10 (crossed but not 25)
      result =
        PositionAlert.check_volume_window_surge(
          position,
          Decimal.new("115"),
          Decimal.new("100"),
          now
        )

      assert {:alert, tier} = result
      assert Decimal.equal?(tier, Decimal.new(10))
    end

    test "alerts when growth crosses a new higher tier", %{now: now, past_30: past_30} do
      position = %{
        last_alerted_volume_window_tier: Decimal.new(10),
        last_alerted_at: past_30
      }

      # +30% → tier 25
      result =
        PositionAlert.check_volume_window_surge(
          position,
          Decimal.new("130"),
          Decimal.new("100"),
          now
        )

      assert {:alert, tier} = result
      assert Decimal.equal?(tier, Decimal.new(25))
    end

    test "does not re-alert at the same tier", %{now: now, past_30: past_30} do
      position = %{
        last_alerted_volume_window_tier: Decimal.new(25),
        last_alerted_at: past_30
      }

      # +30% → tier 25 (same as last alerted)
      result =
        PositionAlert.check_volume_window_surge(
          position,
          Decimal.new("130"),
          Decimal.new("100"),
          now
        )

      assert :no_alert = result
    end

    test "does not alert when baseline is nil", %{now: now} do
      position = %{last_alerted_volume_window_tier: nil, last_alerted_at: nil}

      result = PositionAlert.check_volume_window_surge(position, Decimal.new("100"), nil, now)

      assert :no_alert = result
    end

    test "does not alert when baseline is zero", %{now: now} do
      position = %{last_alerted_volume_window_tier: nil, last_alerted_at: nil}

      result =
        PositionAlert.check_volume_window_surge(
          position,
          Decimal.new("100"),
          Decimal.new("0"),
          now
        )

      assert :no_alert = result
    end

    test "does not alert when current volume is nil", %{now: now} do
      position = %{last_alerted_volume_window_tier: nil, last_alerted_at: nil}

      result =
        PositionAlert.check_volume_window_surge(position, nil, Decimal.new("100"), now)

      assert :no_alert = result
    end

    test "does not alert when volume dropped", %{now: now} do
      position = %{last_alerted_volume_window_tier: nil, last_alerted_at: nil}

      # 100 → 80 = -20%
      result =
        PositionAlert.check_volume_window_surge(
          position,
          Decimal.new("80"),
          Decimal.new("100"),
          now
        )

      assert :no_alert = result
    end

    test "throttles alerts within 30 seconds of last_alerted_at",
         %{now: now, past_20: past_20} do
      position = %{
        last_alerted_volume_window_tier: nil,
        last_alerted_at: past_20
      }

      result =
        PositionAlert.check_volume_window_surge(
          position,
          Decimal.new("150"),
          Decimal.new("100"),
          now
        )

      assert :no_alert = result
    end
  end

  describe "check_volume_cumulative_tier/3" do
    setup do
      now = DateTime.utc_now()
      past_30 = DateTime.add(now, -30, :second)
      past_20 = DateTime.add(now, -20, :second)
      {:ok, now: now, past_30: past_30, past_20: past_20}
    end

    test "alerts when growth crosses the 20% tier", %{now: now} do
      position = %{
        last_alerted_volume_cumulative_tier: nil,
        last_alerted_at: nil
      }

      result =
        PositionAlert.check_volume_cumulative_tier(position, Decimal.new("25"), now)

      assert {:alert, tier} = result
      assert Decimal.equal?(tier, Decimal.new(20))
    end

    test "alerts when growth crosses the 100% tier after previously alerting on 20%",
         %{now: now, past_30: past_30} do
      position = %{
        last_alerted_volume_cumulative_tier: Decimal.new(20),
        last_alerted_at: past_30
      }

      result =
        PositionAlert.check_volume_cumulative_tier(position, Decimal.new("150"), now)

      assert {:alert, tier} = result
      assert Decimal.equal?(tier, Decimal.new(100))
    end

    test "does not re-alert at the same tier", %{now: now, past_30: past_30} do
      position = %{
        last_alerted_volume_cumulative_tier: Decimal.new(100),
        last_alerted_at: past_30
      }

      result =
        PositionAlert.check_volume_cumulative_tier(position, Decimal.new("150"), now)

      assert :no_alert = result
    end

    test "does not alert below the smallest tier", %{now: now} do
      position = %{
        last_alerted_volume_cumulative_tier: nil,
        last_alerted_at: nil
      }

      result =
        PositionAlert.check_volume_cumulative_tier(position, Decimal.new("15"), now)

      assert :no_alert = result
    end

    test "does not alert when growth is nil", %{now: now} do
      position = %{
        last_alerted_volume_cumulative_tier: nil,
        last_alerted_at: nil
      }

      result = PositionAlert.check_volume_cumulative_tier(position, nil, now)
      assert :no_alert = result
    end

    test "throttles within 30 seconds", %{now: now, past_20: past_20} do
      position = %{
        last_alerted_volume_cumulative_tier: nil,
        last_alerted_at: past_20
      }

      result =
        PositionAlert.check_volume_cumulative_tier(position, Decimal.new("150"), now)

      assert :no_alert = result
    end
  end

  describe "volume message formatters" do
    test "volume_window_surge_message/1 formats the tier and emoji" do
      assert PositionAlert.volume_window_surge_message(Decimal.new(25)) ==
               "🔊 Volume surging: +25.00% in the last hour"
    end

    test "volume_cumulative_tier_message/1 formats the tier and emoji" do
      assert PositionAlert.volume_cumulative_tier_message(Decimal.new(100)) ==
               "📊 Volume up 100.00% since entering the top 10"
    end
  end
end
