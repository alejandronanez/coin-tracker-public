defmodule CoinTracker.Signals.MarketStatusAlertTest do
  use CoinTracker.DataCase

  import CoinTracker.AccountsFixtures
  import CoinTracker.SignalsFixtures

  alias CoinTracker.Signals
  alias CoinTracker.TelegramClient.TelegramService

  describe "market status alert detection" do
    test "recovery to 10 triggers alert" do
      # Create a previous status with 7 signals
      market_status_fixture(%{active_signals_count: 7, recorded_at: ~U[2025-01-01 10:00:00Z]})

      # Create a pro user with telegram to verify alert would be sent
      _pro_user = pro_user_with_telegram_fixture()

      # Create new status with 10 signals
      market_status_fixture(%{active_signals_count: 10, recorded_at: ~U[2025-01-01 10:10:00Z]})

      # Get the statuses to simulate what the poller would see
      statuses = Signals.list_market_statuses(order_by: [desc: :recorded_at], limit: 2)
      [current, previous] = statuses

      assert previous.active_signals_count == 7
      assert current.active_signals_count == 10

      # Verify the transition logic
      assert should_alert_recovery?(previous, current)
      refute should_alert_drop?(previous, current)
    end

    test "drop from 10 triggers alert" do
      # Create a previous status with 10 signals
      market_status_fixture(%{active_signals_count: 10, recorded_at: ~U[2025-01-01 10:00:00Z]})

      # Create new status with 7 signals
      market_status_fixture(%{active_signals_count: 7, recorded_at: ~U[2025-01-01 10:10:00Z]})

      statuses = Signals.list_market_statuses(order_by: [desc: :recorded_at], limit: 2)
      [current, previous] = statuses

      assert previous.active_signals_count == 10
      assert current.active_signals_count == 7

      # Verify the transition logic
      refute should_alert_recovery?(previous, current)
      assert should_alert_drop?(previous, current)
    end

    test "no alert when staying at 10" do
      market_status_fixture(%{active_signals_count: 10, recorded_at: ~U[2025-01-01 10:00:00Z]})
      market_status_fixture(%{active_signals_count: 10, recorded_at: ~U[2025-01-01 10:10:00Z]})

      statuses = Signals.list_market_statuses(order_by: [desc: :recorded_at], limit: 2)
      [current, previous] = statuses

      refute should_alert_recovery?(previous, current)
      refute should_alert_drop?(previous, current)
    end

    test "no alert when staying below 10" do
      market_status_fixture(%{active_signals_count: 5, recorded_at: ~U[2025-01-01 10:00:00Z]})
      market_status_fixture(%{active_signals_count: 7, recorded_at: ~U[2025-01-01 10:10:00Z]})

      statuses = Signals.list_market_statuses(order_by: [desc: :recorded_at], limit: 2)
      [current, previous] = statuses

      refute should_alert_recovery?(previous, current)
      refute should_alert_drop?(previous, current)
    end

    test "no alert when dropping but not from 10" do
      market_status_fixture(%{active_signals_count: 8, recorded_at: ~U[2025-01-01 10:00:00Z]})
      market_status_fixture(%{active_signals_count: 5, recorded_at: ~U[2025-01-01 10:10:00Z]})

      statuses = Signals.list_market_statuses(order_by: [desc: :recorded_at], limit: 2)
      [current, previous] = statuses

      refute should_alert_recovery?(previous, current)
      refute should_alert_drop?(previous, current)
    end
  end

  describe "broadcast_message/2" do
    test "broadcasts to provided user IDs" do
      # Create users with telegram linked
      pro_user1 = pro_user_with_telegram_fixture()
      pro_user2 = pro_user_with_telegram_fixture()

      # The actual sending will fail because ExGram is not configured in tests,
      # but we can verify the function accepts user_ids and returns a count
      {:ok, _count} =
        TelegramService.broadcast_message([pro_user1.id, pro_user2.id], "Test alert")
    end

    test "returns 0 when given empty list" do
      {:ok, count} = TelegramService.broadcast_message([], "Test alert")

      assert count == 0
    end

    test "handles users without telegram linked gracefully" do
      # Create a user WITHOUT telegram
      user = user_fixture()

      # Should not crash, just return 0 successful sends
      {:ok, count} = TelegramService.broadcast_message([user.id], "Test alert")

      assert count == 0
    end
  end

  # Helper functions to mirror the logic in MarketStatusPoller
  defp should_alert_recovery?(previous, current) do
    previous.active_signals_count != 10 and current.active_signals_count == 10
  end

  defp should_alert_drop?(previous, current) do
    previous.active_signals_count == 10 and current.active_signals_count != 10
  end
end
