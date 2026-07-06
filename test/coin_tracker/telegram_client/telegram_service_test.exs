defmodule CoinTracker.TelegramClient.TelegramServiceTest do
  use CoinTracker.DataCase, async: true

  import ExUnit.CaptureLog

  alias CoinTracker.Repo
  alias CoinTracker.TelegramClient.DispatchClaim
  alias CoinTracker.TelegramClient.TelegramService

  import CoinTracker.AccountsFixtures
  import CoinTracker.SignalsFixtures
  import CoinTracker.TradingFixtures

  describe "send_message/3 cluster-wide deduplication" do
    setup do
      original_level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: original_level) end)
      :ok
    end

    test "second identical send returns {:ok, :suppressed} and skips wire send" do
      user = user_fixture()
      chat_id = System.unique_integer([:positive])
      link_telegram(user, chat_id)

      # Force a stable bucket so both calls land in it
      now_seconds = 1_500_000
      Process.put(:dispatch_claim_now_override, now_seconds)
      bucket = div(now_seconds, DispatchClaim.window_seconds())

      message = "alert content #{System.unique_integer([:positive])}"

      log =
        capture_log(fn ->
          # First call wins the claim and proceeds to do_send. ExGram is
          # unconfigured in tests so the wire send fails — the important
          # assertion is that this is NOT :suppressed.
          first = TelegramService.send_message(user.id, message, kind: :test)
          refute match?({:ok, :suppressed}, first)

          # Second identical call must be suppressed by the DispatchClaim gate
          # *before* the wire send.
          assert {:ok, :suppressed} =
                   TelegramService.send_message(user.id, message, kind: :test)
        end)

      assert log =~ "telegram dispatch suppressed (cluster-wide duplicate)"

      # Exactly one claim row exists for this (user, fingerprint, bucket)
      claims =
        Repo.all(
          from(c in DispatchClaim,
            where: c.user_id == ^user.id and c.window_bucket == ^bucket
          )
        )

      assert length(claims) == 1
    end

    test "different messages from same user both go through" do
      user = user_fixture()
      chat_id = System.unique_integer([:positive])
      link_telegram(user, chat_id)

      Process.put(:dispatch_claim_now_override, 1_500_000)

      result_a = TelegramService.send_message(user.id, "msg A", kind: :test)
      result_b = TelegramService.send_message(user.id, "msg B", kind: :test)

      # Neither should be :suppressed (different fingerprints).
      refute match?({:ok, :suppressed}, result_a)
      refute match?({:ok, :suppressed}, result_b)
    end

    test "user with no Telegram linked still claims — second call still suppressed" do
      # Important: claim happens *before* the chat_id lookup, so even users
      # without Telegram exhibit the suppression. The wire send returns :ok
      # (no chat) on the first call; the second returns {:ok, :suppressed}.
      user = user_fixture()
      Process.put(:dispatch_claim_now_override, 1_500_000)

      message = "no-chat dedup #{System.unique_integer([:positive])}"

      assert :ok = TelegramService.send_message(user.id, message, kind: :test)

      assert {:ok, :suppressed} =
               TelegramService.send_message(user.id, message, kind: :test)
    end
  end

  describe "list_positions/1" do
    test "returns error for unlinked chat_id" do
      # Random chat_id that doesn't exist
      unlinked_chat_id = System.unique_integer([:positive])

      assert {:error, "Telegram account not linked to any user"} =
               TelegramService.list_positions(unlinked_chat_id)
    end

    test "returns no positions message for user with no active positions" do
      user = user_fixture()
      chat_id = System.unique_integer([:positive])
      link_telegram(user, chat_id)

      assert {:ok, message} = TelegramService.list_positions(chat_id)
      assert message == "📊 You have no active positions yet."
    end

    test "returns formatted positions for user with active positions" do
      user = user_fixture()
      chat_id = System.unique_integer([:positive])
      link_telegram(user, chat_id)

      # Create an active position
      _position = position_fixture(user_id: user.id, symbol: "ETH", entry_price: "2000.00")

      assert {:ok, message} = TelegramService.list_positions(chat_id)
      assert message =~ "📊 Your Active Positions:"
      assert message =~ "ETH/USDT"
      assert message =~ "Entry: $2000"
    end

    test "only shows active positions, not closed ones" do
      user = user_fixture()
      chat_id = System.unique_integer([:positive])
      link_telegram(user, chat_id)

      # Create one active and one closed position
      _active = position_fixture(user_id: user.id, symbol: "ETH", entry_price: "2000.00")

      _closed =
        position_fixture(
          user_id: user.id,
          symbol: "BTC",
          entry_price: "50000.00",
          status: :closed
        )

      assert {:ok, message} = TelegramService.list_positions(chat_id)
      assert message =~ "ETH/USDT"
      refute message =~ "BTC/USDT"
    end

    test "shows multiple active positions" do
      user = user_fixture()
      chat_id = System.unique_integer([:positive])
      link_telegram(user, chat_id)

      _position1 = position_fixture(user_id: user.id, symbol: "ETH", entry_price: "2000.00")
      _position2 = position_fixture(user_id: user.id, symbol: "BTC", entry_price: "50000.00")

      assert {:ok, message} = TelegramService.list_positions(chat_id)
      assert message =~ "ETH/USDT"
      assert message =~ "BTC/USDT"
      # Should have position numbers
      assert message =~ "1."
      assert message =~ "2."
    end

    test "sorts positions by gains descending (highest gains first)" do
      user = user_fixture()
      chat_id = System.unique_integer([:positive])
      link_telegram(user, chat_id)

      # Position with -10% loss: entry 1000, current 900
      position_fixture(
        user_id: user.id,
        symbol: "DOGE",
        entry_price: "1000.00",
        current_price: "900.00"
      )

      # Position with +50% gain: entry 2000, current 3000
      position_fixture(
        user_id: user.id,
        symbol: "ETH",
        entry_price: "2000.00",
        current_price: "3000.00"
      )

      # Position with +20% gain: entry 50000, current 60000
      position_fixture(
        user_id: user.id,
        symbol: "BTC",
        entry_price: "50000.00",
        current_price: "60000.00"
      )

      assert {:ok, message} = TelegramService.list_positions(chat_id)

      # Find the line numbers for each position
      eth_position =
        Regex.run(~r/(\d+)\. .+ ETH\/USDT/, message) |> List.last() |> String.to_integer()

      btc_position =
        Regex.run(~r/(\d+)\. .+ BTC\/USDT/, message) |> List.last() |> String.to_integer()

      doge_position =
        Regex.run(~r/(\d+)\. .+ DOGE\/USDT/, message) |> List.last() |> String.to_integer()

      # ETH (+50%) should be first, BTC (+20%) second, DOGE (-10%) last
      assert eth_position == 1, "ETH with +50% gain should be position 1, got #{eth_position}"
      assert btc_position == 2, "BTC with +20% gain should be position 2, got #{btc_position}"
      assert doge_position == 3, "DOGE with -10% loss should be position 3, got #{doge_position}"
    end
  end

  describe "list_positions/1 formatting" do
    test "formats position with correct structure" do
      user = user_fixture()
      chat_id = System.unique_integer([:positive])
      link_telegram(user, chat_id)

      _position =
        position_fixture(
          user_id: user.id,
          symbol: "ETH",
          entry_price: "2000.00",
          stop_loss_percent: "-10.0",
          take_profit_percent: "20.0",
          current_price: "2200.00"
        )

      assert {:ok, message} = TelegramService.list_positions(chat_id)

      # Check structure
      assert message =~ "1. 🟢 ETH/USDT"
      assert message =~ "Entry: $2000"
      assert message =~ "Current: $2200"
      assert message =~ "SL: -10.0%"
      assert message =~ "TP: 20.0%"
    end

    test "calculates price change percentage correctly" do
      user = user_fixture()
      chat_id = System.unique_integer([:positive])
      link_telegram(user, chat_id)

      # Entry: 2000, Current: 2200 = +10% change
      _position =
        position_fixture(
          user_id: user.id,
          symbol: "ETH",
          entry_price: "2000.00",
          current_price: "2200.00"
        )

      assert {:ok, message} = TelegramService.list_positions(chat_id)
      # (2200 - 2000) / 2000 * 100 = 10%
      assert message =~ "(10.0%)" or message =~ "(10.00%)"
    end
  end

  describe "get_market_status/1" do
    test "returns error for unlinked chat_id" do
      unlinked_chat_id = System.unique_integer([:positive])

      assert {:error, "Telegram account not linked to any user"} =
               TelegramService.get_market_status(unlinked_chat_id)
    end

    test "returns green status when market is at full capacity (10/10)" do
      user = user_fixture()
      chat_id = System.unique_integer([:positive])
      link_telegram(user, chat_id)

      # Create 10 active signals in top 10
      for i <- 1..10 do
        signal_fixture(%{active: true, in_top: true, position: i})
      end

      assert {:ok, "🟢 Market: 10/10"} = TelegramService.get_market_status(chat_id)
    end

    test "returns red status when market is below capacity" do
      user = user_fixture()
      chat_id = System.unique_integer([:positive])
      link_telegram(user, chat_id)

      # Create only 7 active signals in top 10
      for i <- 1..7 do
        signal_fixture(%{active: true, in_top: true, position: i})
      end

      assert {:ok, "🔴 Market: 7/10"} = TelegramService.get_market_status(chat_id)
    end

    test "returns red status when market is empty" do
      user = user_fixture()
      chat_id = System.unique_integer([:positive])
      link_telegram(user, chat_id)

      # No signals created

      assert {:ok, "🔴 Market: 0/10"} = TelegramService.get_market_status(chat_id)
    end

    test "only counts signals that are both active and in_top" do
      user = user_fixture()
      chat_id = System.unique_integer([:positive])
      link_telegram(user, chat_id)

      # 5 active + in_top (should count)
      for i <- 1..5 do
        signal_fixture(%{active: true, in_top: true, position: i})
      end

      # 3 active but NOT in_top (should NOT count)
      for _ <- 1..3 do
        signal_fixture(%{active: true, in_top: false})
      end

      # 2 in_top but NOT active (should NOT count)
      for i <- 6..7 do
        signal_fixture(%{active: false, in_top: true, position: i})
      end

      assert {:ok, "🔴 Market: 5/10"} = TelegramService.get_market_status(chat_id)
    end
  end
end
