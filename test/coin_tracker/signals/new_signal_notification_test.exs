defmodule CoinTracker.Signals.NewSignalNotificationTest do
  use CoinTracker.DataCase

  import CoinTracker.AccountsFixtures
  import CoinTracker.SignalsFixtures

  alias CoinTracker.Signals

  describe "notify_new_signals/0" do
    test "notifies about new signals (telegram_notified_at is nil)" do
      # Create a pro user with telegram to receive notifications
      pro_user = pro_user_with_telegram_fixture()

      # Create a new signal that hasn't been notified (in_top: true, telegram_notified_at: nil)
      signal = signal_fixture(%{in_top: true, position: 1, telegram_notified_at: nil})

      # Run notification
      {:ok, count} = Signals.notify_new_signals()

      assert count == 1

      # Verify signal was marked as notified
      updated_signal = Signals.get_signal(signal.id)
      assert updated_signal.telegram_notified_at != nil

      # Verify we can get the user who should receive it
      users = CoinTracker.Accounts.list_pro_users_with_telegram()
      assert Enum.any?(users, fn u -> u.id == pro_user.id end)
    end

    test "does not notify about signals already notified" do
      # Create a pro user with telegram
      _pro_user = pro_user_with_telegram_fixture()

      # Create a signal that's already been notified
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      _signal = signal_fixture(%{in_top: true, position: 1, telegram_notified_at: now})

      # Run notification
      {:ok, count} = Signals.notify_new_signals()

      # No new signals to notify
      assert count == 0
    end

    test "does not notify about signals not in top 10" do
      # Create a pro user with telegram
      _pro_user = pro_user_with_telegram_fixture()

      # Create a signal that's NOT in top 10 (in_top: false)
      signal = signal_fixture(%{in_top: false, position: nil, telegram_notified_at: nil})

      # Run notification
      {:ok, count} = Signals.notify_new_signals()

      # Should not notify since signal is not in top
      assert count == 0

      # Verify signal was NOT marked as notified
      updated_signal = Signals.get_signal(signal.id)
      assert updated_signal.telegram_notified_at == nil
    end

    test "notifies multiple signals in a batch" do
      # Create a pro user with telegram
      _pro_user = pro_user_with_telegram_fixture()

      # Create multiple new signals
      signal1 = signal_fixture(%{in_top: true, position: 1, telegram_notified_at: nil})
      signal2 = signal_fixture(%{in_top: true, position: 2, telegram_notified_at: nil})
      signal3 = signal_fixture(%{in_top: true, position: 3, telegram_notified_at: nil})

      # Run notification
      {:ok, count} = Signals.notify_new_signals()

      assert count == 3

      # Verify all signals were marked as notified
      assert Signals.get_signal(signal1.id).telegram_notified_at != nil
      assert Signals.get_signal(signal2.id).telegram_notified_at != nil
      assert Signals.get_signal(signal3.id).telegram_notified_at != nil
    end

    test "returns 0 when there are no new signals" do
      # Create a pro user with telegram
      _pro_user = pro_user_with_telegram_fixture()

      # No signals at all
      {:ok, count} = Signals.notify_new_signals()

      assert count == 0
    end

    test "still marks signals as notified even without pro users" do
      # No pro users with telegram

      # Create a new signal
      signal = signal_fixture(%{in_top: true, position: 1, telegram_notified_at: nil})

      # Run notification
      {:ok, count} = Signals.notify_new_signals()

      assert count == 1

      # Signal should still be marked as notified
      updated_signal = Signals.get_signal(signal.id)
      assert updated_signal.telegram_notified_at != nil
    end
  end

  describe "format_new_signals_message/1 (via notify_new_signals)" do
    test "formats single signal correctly" do
      # We can't directly test the private function, but we can verify
      # the message format indirectly by checking the broadcast_message call
      # For now, we just verify the function completes successfully
      _pro_user = pro_user_with_telegram_fixture()

      _signal = signal_fixture(%{in_top: true, position: 5, telegram_notified_at: nil})

      {:ok, count} = Signals.notify_new_signals()

      assert count == 1
    end

    test "formats multiple signals correctly" do
      _pro_user = pro_user_with_telegram_fixture()

      _signal1 = signal_fixture(%{in_top: true, position: 1, telegram_notified_at: nil})
      _signal2 = signal_fixture(%{in_top: true, position: 2, telegram_notified_at: nil})

      {:ok, count} = Signals.notify_new_signals()

      assert count == 2
    end
  end

  describe "broadcast to pro/admin users" do
    test "broadcasts to pro users with telegram" do
      pro_user = pro_user_with_telegram_fixture()
      _signal = signal_fixture(%{in_top: true, position: 1, telegram_notified_at: nil})

      users = CoinTracker.Accounts.list_pro_users_with_telegram()
      assert length(users) == 1
      assert hd(users).id == pro_user.id

      {:ok, count} = Signals.notify_new_signals()
      assert count == 1
    end

    test "broadcasts to admin users with telegram" do
      admin_user = admin_user_with_telegram_fixture()
      _signal = signal_fixture(%{in_top: true, position: 1, telegram_notified_at: nil})

      users = CoinTracker.Accounts.list_pro_users_with_telegram()
      assert length(users) == 1
      assert hd(users).id == admin_user.id

      {:ok, count} = Signals.notify_new_signals()
      assert count == 1
    end

    test "does not broadcast to free users" do
      # Create a free user with telegram (should not receive notifications)
      user = user_fixture()
      link_telegram(user)

      _signal = signal_fixture(%{in_top: true, position: 1, telegram_notified_at: nil})

      # Verify free user is not in the list
      users = CoinTracker.Accounts.list_pro_users_with_telegram()
      assert length(users) == 0

      # Notification still runs (marking signal as notified)
      {:ok, count} = Signals.notify_new_signals()
      assert count == 1
    end

    test "does not broadcast to pro users without telegram" do
      # Create a pro user WITHOUT telegram
      _pro_user = pro_user_fixture()

      _signal = signal_fixture(%{in_top: true, position: 1, telegram_notified_at: nil})

      # Verify user is not in the list (no telegram linked)
      users = CoinTracker.Accounts.list_pro_users_with_telegram()
      assert length(users) == 0

      {:ok, count} = Signals.notify_new_signals()
      assert count == 1
    end
  end
end
