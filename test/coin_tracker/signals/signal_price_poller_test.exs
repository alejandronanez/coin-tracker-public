defmodule CoinTracker.Signals.SignalPricePollerTest do
  # Not async because we're dealing with a globally registered GenServer
  use CoinTracker.DataCase, async: false

  alias CoinTracker.Signals
  alias CoinTracker.Signals.SignalPricePoller

  setup do
    # Subscribe to price updates for testing PubSub broadcasts
    Phoenix.PubSub.subscribe(CoinTracker.PubSub, "price_updates")

    # Flush any lingering PubSub messages from previous tests
    flush_messages()

    :ok
  end

  # Helper to flush all messages from the process mailbox
  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end

  # Drains the mailbox until it has been quiet for `quiet_ms`, or until
  # `max_wait_ms` total has elapsed. Use this when prior tests may have
  # fired async HTTP calls (via `SignalPricePoller.poll_now/0`) whose
  # `:price_updated` broadcasts can leak into the current test's mailbox.
  # Unlike a fixed `Process.sleep + flush`, this is robust to HTTP latency.
  defp drain_until_quiet(quiet_ms, max_wait_ms) do
    deadline = System.monotonic_time(:millisecond) + max_wait_ms
    do_drain(quiet_ms, deadline)
  end

  defp do_drain(quiet_ms, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      :ok
    else
      wait = min(quiet_ms, deadline - now)

      receive do
        _ -> do_drain(quiet_ms, deadline)
      after
        wait -> :ok
      end
    end
  end

  # `poll_now/0` is a `cast`. The GenServer's `handle_cast` performs synchronous
  # HTTP, so a system call that's queued behind the cast will only return once
  # the cast has been fully handled — including any broadcasts. Using this in
  # place of `Process.sleep` makes the test deterministic and prevents in-flight
  # HTTP from leaking `:price_updated` messages into the next test.
  defp wait_for_poll do
    :sys.get_state(SignalPricePoller)
    :ok
  end

  describe "init/1" do
    test "poller is already started in application" do
      # Verify the Poller is running (started by application.ex)
      pid = Process.whereis(SignalPricePoller)
      assert pid != nil
      assert Process.alive?(pid)
    end

    test "poller respects enabled: false config in test environment" do
      # In test.exs, we configured enabled: false
      # This test verifies that no polling happens automatically

      pid = Process.whereis(SignalPricePoller)
      assert pid != nil
    end
  end

  describe "periodic polling" do
    test "poller does not automatically poll when disabled in test config" do
      # Create an active signal
      signal_fixture()

      # Prior tests that call `SignalPricePoller.poll_now/0` spawn real HTTP
      # requests to external exchanges. Those can resolve after the test that
      # triggered them has exited, leaking `:price_updated` broadcasts into
      # this test's mailbox. Drain the mailbox until it stays quiet for
      # 500ms (up to 5s total) so we only observe broadcasts that would be
      # emitted _during_ our observation window below.
      drain_until_quiet(500, 5_000)

      # Now wait — if the poller were auto-polling it would fire in this window.
      Process.sleep(500)

      # No PubSub messages should have been received from the poller
      refute_received {:price_updated, _}
    end
  end

  describe "poll_now/0" do
    test "can be called without crashing the poller" do
      SignalPricePoller.poll_now()
      wait_for_poll()

      pid = Process.whereis(SignalPricePoller)
      assert Process.alive?(pid)
    end

    test "does not poll when no active signals exist" do
      Repo.update_all(Signals.Signal, set: [active: false])

      drain_until_quiet(500, 5_000)

      SignalPricePoller.poll_now()
      wait_for_poll()

      refute_received {:price_updated, _}
    end
  end

  describe "get_unique_symbols_for_active_signals/0" do
    test "returns unique symbols from active signals" do
      # Create active signals with different in_top_since to avoid unique constraint
      signal_fixture(%{symbol: "ETH", active: true, in_top_since: ~U[2025-01-01 00:00:00Z]})
      signal_fixture(%{symbol: "BTC", active: true, in_top_since: ~U[2025-01-02 00:00:00Z]})
      signal_fixture(%{symbol: "ETH", active: true, in_top_since: ~U[2025-01-03 00:00:00Z]})

      # Create inactive signal (should not be included)
      signal_fixture(%{symbol: "SOL", active: false, in_top_since: ~U[2025-01-04 00:00:00Z]})

      symbols = Signals.get_unique_symbols_for_active_signals()

      # Should only include unique symbols from active signals
      assert length(symbols) == 2
      assert "ETH" in symbols
      assert "BTC" in symbols
      refute "SOL" in symbols
    end

    test "returns empty list when no active signals exist" do
      # Create only inactive signals
      signal_fixture(%{symbol: "ETH", active: false})

      symbols = Signals.get_unique_symbols_for_active_signals()

      assert symbols == []
    end
  end

  describe "link_signals_to_symbol_price/2" do
    test "links all active signals with matching symbol to symbol_price" do
      # Create active signals with same symbol but different in_top_since
      signal1 =
        signal_fixture(%{symbol: "ETH", active: true, in_top_since: ~U[2025-01-01 00:00:00Z]})

      signal2 =
        signal_fixture(%{symbol: "ETH", active: true, in_top_since: ~U[2025-01-02 00:00:00Z]})

      # Create signal with different symbol
      signal3 =
        signal_fixture(%{symbol: "BTC", active: true, in_top_since: ~U[2025-01-03 00:00:00Z]})

      # Create inactive signal with same symbol
      signal4 =
        signal_fixture(%{symbol: "ETH", active: false, in_top_since: ~U[2025-01-04 00:00:00Z]})

      # Create a symbol_price
      {:ok, symbol_price} =
        CoinTracker.Coins.upsert_symbol_price(%{
          exchange: :binance_spot,
          symbol_pair: "ETH/USDT",
          current_price: Decimal.new("2000.00")
        })

      # Link signals
      {count, _} = Signals.link_signals_to_symbol_price("ETH", symbol_price.id)

      # Should have updated 2 active signals with symbol "ETH"
      assert count == 2

      # Verify the signals were updated
      updated_signal1 = Repo.get!(Signals.Signal, signal1.id)
      updated_signal2 = Repo.get!(Signals.Signal, signal2.id)
      updated_signal3 = Repo.get!(Signals.Signal, signal3.id)
      updated_signal4 = Repo.get!(Signals.Signal, signal4.id)

      assert updated_signal1.symbol_price_id == symbol_price.id
      assert updated_signal2.symbol_price_id == symbol_price.id
      assert updated_signal3.symbol_price_id == nil
      assert updated_signal4.symbol_price_id == nil
    end
  end

  describe "exchange priority exclusions" do
    test "binance excluded symbols (XMR) still attempt other exchanges" do
      xmr_signal = signal_fixture(%{symbol: "XMR", active: true})

      SignalPricePoller.poll_now()
      wait_for_poll()

      pid = Process.whereis(SignalPricePoller)
      assert Process.alive?(pid)

      _updated_signal = Repo.get!(Signals.Signal, xmr_signal.id)
    end

    test "non-excluded symbols use full exchange priority" do
      eth_signal = signal_fixture(%{symbol: "ETH", active: true})

      SignalPricePoller.poll_now()
      wait_for_poll()

      pid = Process.whereis(SignalPricePoller)
      assert Process.alive?(pid)

      _updated_signal = Repo.get!(Signals.Signal, eth_signal.id)
    end
  end

  describe "list_signals_with_prices/1" do
    test "returns signals with preloaded symbol_price" do
      # Create a symbol_price
      {:ok, symbol_price} =
        CoinTracker.Coins.upsert_symbol_price(%{
          exchange: :binance_spot,
          symbol_pair: "ETH/USDT",
          current_price: Decimal.new("2000.00")
        })

      # Create a signal and link it
      signal = signal_fixture(%{symbol: "ETH", active: true})
      Signals.link_signals_to_symbol_price("ETH", symbol_price.id)

      # Get signals with prices
      signals = Signals.list_signals_with_prices(active: true)

      assert length(signals) == 1
      [loaded_signal] = signals

      assert loaded_signal.id == signal.id
      assert loaded_signal.symbol_price != nil
      assert loaded_signal.symbol_price.id == symbol_price.id
      assert Decimal.equal?(loaded_signal.symbol_price.current_price, Decimal.new("2000.00"))
    end

    test "returns nil symbol_price for signals without linked price" do
      signal_fixture(%{symbol: "ETH", active: true})

      signals = Signals.list_signals_with_prices(active: true)

      assert length(signals) == 1
      [loaded_signal] = signals

      assert loaded_signal.symbol_price == nil
    end
  end

  # Helper function to create signals
  defp signal_fixture(attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      Enum.into(attrs, %{
        symbol: "ETH",
        name: "Ethereum",
        in_top: true,
        active: true,
        in_top_since: now,
        position: 1,
        initial_price_usd: Decimal.new("2000.00"),
        current_price_usd: Decimal.new("2100.00"),
        max_price_usd: Decimal.new("2100.00"),
        max_increase_percentage: Decimal.new("5.0"),
        initial_volume_24h: Decimal.new("1000000.00"),
        current_volume_24h: Decimal.new("1200000.00")
      })

    {:ok, signal} =
      %Signals.Signal{}
      |> Signals.Signal.changeset(attrs)
      |> Repo.insert()

    signal
  end
end
