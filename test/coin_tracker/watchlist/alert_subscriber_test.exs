defmodule CoinTracker.Watchlist.AlertSubscriberTest do
  use CoinTracker.DataCase, async: false

  alias CoinTracker.Watchlist.AlertSubscriber

  import CoinTracker.AccountsFixtures
  import CoinTracker.SignalsFixtures
  import CoinTracker.TradingFixtures

  defmodule TelegramStub do
    @moduledoc false
    def broadcast_message(user_ids, message, opts \\ []) do
      send(:test_inbox, {:telegram_broadcast, user_ids, message, opts})
      {:ok, length(user_ids)}
    end
  end

  setup do
    Process.register(self(), :test_inbox)
    :ok
  end

  describe "transitions" do
    test "fires :entered alert when a signal goes from out-of-top to in-top" do
      user = user_fixture()
      position_fixture(user_id: user.id, symbol: "ETH")

      # Seed initial state with ETH out of top.
      previous_signal =
        signal_fixture(%{symbol: "ETH", in_top: false, active: true, position: nil})

      pid =
        start_supervised!(
          {AlertSubscriber,
           name: :test_alert_subscriber_a, subscribe?: false, telegram: TelegramStub}
        )

      # Simulate a poll that puts ETH into the top 10 at rank 4.
      new_signal = %{previous_signal | in_top: true, position: 4}
      send(pid, {:signals_updated, [new_signal]})

      assert_receive {:telegram_broadcast, user_ids, message, opts}, 500
      assert user.id in user_ids
      assert message =~ "ETH"
      assert message =~ "top 10"
      assert message =~ "#4"
      assert Keyword.get(opts, :kind) == :watchlist_entered
    end

    test "fires :dropped alert when a signal goes from in-top to out-of-top" do
      user = user_fixture()
      position_fixture(user_id: user.id, symbol: "DOGE")

      previous_signal =
        signal_fixture(%{symbol: "DOGE", in_top: true, active: true, position: 6})

      pid =
        start_supervised!(
          {AlertSubscriber,
           name: :test_alert_subscriber_b, subscribe?: false, telegram: TelegramStub}
        )

      dropped = %{previous_signal | in_top: false, position: nil}
      send(pid, {:signals_updated, [dropped]})

      assert_receive {:telegram_broadcast, _user_ids, message, opts}, 500
      assert message =~ "DOGE"
      assert message =~ "dropped out"
      assert message =~ "#6"
      assert Keyword.get(opts, :kind) == :watchlist_dropped
    end

    test "does not fire on no-op broadcasts (in_top unchanged)" do
      user = user_fixture()
      position_fixture(user_id: user.id, symbol: "BTC")

      previous_signal =
        signal_fixture(%{symbol: "BTC", in_top: true, active: true, position: 1})

      pid =
        start_supervised!(
          {AlertSubscriber,
           name: :test_alert_subscriber_c, subscribe?: false, telegram: TelegramStub}
        )

      # Same in_top status — only rank changed.
      same_status = %{previous_signal | position: 2}
      send(pid, {:signals_updated, [same_status]})

      refute_receive {:telegram_broadcast, _, _, _}, 200
    end

    test "does not fire when no users hold the affected symbol" do
      _user = user_fixture()

      previous_signal =
        signal_fixture(%{symbol: "ZZZ", in_top: false, active: true, position: nil})

      pid =
        start_supervised!(
          {AlertSubscriber,
           name: :test_alert_subscriber_d, subscribe?: false, telegram: TelegramStub}
        )

      entered = %{previous_signal | in_top: true, position: 7}
      send(pid, {:signals_updated, [entered]})

      refute_receive {:telegram_broadcast, _, _, _}, 200
    end

    test "fires :entered for a brand-new symbol entering the top 10" do
      user = user_fixture()
      position_fixture(user_id: user.id, symbol: "NEWCOIN")

      pid =
        start_supervised!(
          {AlertSubscriber,
           name: :test_alert_subscriber_e, subscribe?: false, telegram: TelegramStub}
        )

      # No prior state for NEWCOIN; the first broadcast that puts it in_top
      # should be treated as an :entered transition.
      fresh_signal =
        signal_fixture(%{symbol: "NEWCOIN", in_top: true, active: true, position: 5})

      send(pid, {:signals_updated, [fresh_signal]})

      assert_receive {:telegram_broadcast, user_ids, message, _opts}, 500
      assert user.id in user_ids
      assert message =~ "NEWCOIN"
      assert message =~ "#5"
    end
  end
end
