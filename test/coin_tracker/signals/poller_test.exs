defmodule CoinTracker.Signals.PollerTest do
  # Not async because we're dealing with a globally registered GenServer
  use CoinTracker.DataCase, async: false

  alias CoinTracker.Signals.Poller
  alias CoinTracker.Signals
  alias CoinTracker.Signals.Signal
  import CoinTracker.ApiFixtures

  # Acts as a synchronous barrier: GenServer mailboxes are FIFO, so a sync
  # call returns only after any prior `handle_cast(:poll, ...)` has finished
  # all of its DB work. Use this at the end of any test that triggers
  # `Poller.poll_now/0` so the sandbox connection isn't torn down mid-query.
  defp wait_for_poll, do: Poller.get_status()

  setup do
    bypass = Bypass.open()

    # Get current config to merge with, preserving test settings
    original_config =
      Application.get_env(:coin_tracker, CoinTracker.Signals.CoinscanApiClient, [])

    # Merge test-specific URL and API key
    test_config =
      Keyword.merge(original_config,
        base_url: "http://localhost:#{bypass.port}",
        api_key: "test_api_key"
      )

    Application.put_env(:coin_tracker, CoinTracker.Signals.CoinscanApiClient, test_config)

    # The Poller is a singleton GenServer started by the application supervisor;
    # its fingerprint state persists across tests. Reset it so each test sees a
    # clean slate and the first poll always runs the full pipeline.
    Poller.reset_fingerprint()

    on_exit(fn ->
      Application.put_env(:coin_tracker, CoinTracker.Signals.CoinscanApiClient, original_config)
    end)

    {:ok, bypass: bypass}
  end

  describe "init/1" do
    test "poller is already started in application" do
      # Verify the Poller is running (started by application.ex)
      pid = Process.whereis(Poller)
      assert pid != nil
      assert Process.alive?(pid)
    end

    test "poller respects enabled: false config in test environment" do
      # In test.exs, we configured enabled: false
      # This test verifies that no polling happens automatically
      # We just need to verify the process exists but isn't scheduling polls

      pid = Process.whereis(Poller)
      assert pid != nil
    end
  end

  describe "periodic polling" do
    # Note: In test environment, the Poller is configured with enabled: false
    # so we test the polling behavior indirectly via poll_now/0

    test "poller does not automatically poll when disabled in test config" do
      # Wait a bit to ensure no automatic polling happens
      Process.sleep(100)

      # No signals should exist since no polling happened
      assert Signals.list_signals() == []
    end
  end

  describe "poll_now/0" do
    test "triggers immediate poll via cast", %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [
              coin(
                symbol: "ETH",
                name: "Ethereum",
                initial_price_usd: 3000.0,
                volumen24h: 500_000
              )
            ]
          )
        )
      end)

      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, api_grace_period_response(coins: []))
      end)

      Poller.poll_now()
      wait_for_poll()

      signals = Signals.list_signals()
      assert length(signals) == 1
      assert List.first(signals).symbol == "ETH"
    end

    test "poll_now/0 deactivates expired signals after ingestion", %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, api_top10_response(coins: []))
      end)

      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, api_grace_period_response(coins: []))
      end)

      # Insert expired signal (exit_date > 24 hours ago)
      old_exit = DateTime.add(DateTime.utc_now(), -25, :hour)

      %Signal{}
      |> Signal.changeset(%{
        symbol: "EXPIRED",
        name: "Expired Coin",
        in_top_since: ~U[2025-01-01 00:00:00Z],
        active: true,
        in_top: false,
        exit_date: old_exit
      })
      |> Repo.insert!()

      Poller.poll_now()
      wait_for_poll()

      signal = Signals.list_signals(symbol: "EXPIRED") |> List.first()
      assert signal.active == false
    end
  end

  describe "change detection" do
    test "skips grace period fetch and DB writes when top 10 is unchanged",
         %{bypass: bypass} do
      test_pid = self()

      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        send(test_pid, :top10_called)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [
              coin(symbol: "ETH", name: "Ethereum", position: 1, in_top: true)
            ]
          )
        )
      end)

      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        send(test_pid, :grace_period_called)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, api_grace_period_response(coins: []))
      end)

      # First poll: full ingestion runs.
      Poller.poll_now()
      assert_receive :top10_called, 500
      assert_receive :grace_period_called, 500

      assert [%Signal{symbol: "ETH"}] = Signals.list_signals()
      [eth] = Signals.list_signals()
      first_updated_at = eth.updated_at

      # Second poll with identical data: top10 is fetched (we need it to compare)
      # but everything downstream is skipped.
      Poller.poll_now()
      assert_receive :top10_called, 500
      refute_receive :grace_period_called, 300

      # Row was not touched (updated_at unchanged from the first poll).
      [eth_after] = Signals.list_signals()
      assert eth_after.updated_at == first_updated_at

      wait_for_poll()
    end

    test "runs full ingestion again when the top 10 changes between polls",
         %{bypass: bypass} do
      test_pid = self()
      {:ok, call_count} = Agent.start_link(fn -> 0 end)

      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        n = Agent.get_and_update(call_count, fn n -> {n + 1, n + 1} end)
        # First call → ETH at #1; subsequent calls → BTC at #1 (different fingerprint).
        coins =
          if n == 1 do
            [coin(symbol: "ETH", name: "Ethereum", position: 1, in_top: true)]
          else
            [coin(symbol: "BTC", name: "Bitcoin", position: 1, in_top: true)]
          end

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, api_top10_response(coins: coins))
      end)

      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        send(test_pid, :grace_period_called)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, api_grace_period_response(coins: []))
      end)

      # First poll → ingests ETH, hits grace period.
      Poller.poll_now()
      assert_receive :grace_period_called, 500

      # Second poll → top 10 has flipped to BTC, so grace period must be hit again.
      Poller.poll_now()
      assert_receive :grace_period_called, 500

      symbols = Signals.list_signals() |> Enum.map(& &1.symbol) |> Enum.sort()
      assert symbols == ["BTC", "ETH"]

      wait_for_poll()
    end

    test "preserves fingerprint when top 10 fetch fails", %{bypass: bypass} do
      test_pid = self()
      {:ok, call_count} = Agent.start_link(fn -> 0 end)

      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        n = Agent.get_and_update(call_count, fn n -> {n + 1, n + 1} end)
        # Call 1: success. Call 2: 500 error. Call 3: success again with the
        # SAME data as call 1 — should short-circuit if fingerprint was preserved.
        case n do
          2 ->
            Plug.Conn.resp(conn, 500, "boom")

          _ ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(
              200,
              api_top10_response(
                coins: [coin(symbol: "ETH", name: "Ethereum", position: 1, in_top: true)]
              )
            )
        end
      end)

      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        send(test_pid, :grace_period_called)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, api_grace_period_response(coins: []))
      end)

      Poller.poll_now()
      assert_receive :grace_period_called, 500

      # Failed top 10 fetch → no grace period call, fingerprint preserved.
      Poller.poll_now()
      refute_receive :grace_period_called, 300

      # Recovery poll with identical data → fingerprint match → still skipped.
      Poller.poll_now()
      refute_receive :grace_period_called, 300

      wait_for_poll()
    end

    test "get_status/0 returns nil values before any change is observed" do
      assert %{fingerprint: nil, last_changed_at: nil} = Poller.get_status()
    end

    test "get_status/0 reflects fingerprint and timestamp after a change",
         %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [coin(symbol: "ETH", name: "Ethereum", position: 1, in_top: true)]
          )
        )
      end)

      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, api_grace_period_response(coins: []))
      end)

      before = DateTime.utc_now() |> DateTime.truncate(:second)
      Poller.poll_now()
      # Wait for poll to complete by waiting on the broadcast.
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, Poller.status_topic())
      assert_receive {:poller_status_updated, _}, 500

      status = Poller.get_status()
      assert is_integer(status.fingerprint)
      assert %DateTime{} = status.last_changed_at
      assert DateTime.compare(status.last_changed_at, before) in [:eq, :gt]
    end

    test "broadcasts {:poller_status_updated, _} when fingerprint changes",
         %{bypass: bypass} do
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, Poller.status_topic())

      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [coin(symbol: "ETH", name: "Ethereum", position: 1, in_top: true)]
          )
        )
      end)

      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, api_grace_period_response(coins: []))
      end)

      Poller.poll_now()
      assert_receive {:poller_status_updated, status}, 500
      assert is_integer(status.fingerprint)
      assert %DateTime{} = status.last_changed_at

      # Identical second poll → fingerprint unchanged → no broadcast.
      Poller.poll_now()
      refute_receive {:poller_status_updated, _}, 300

      wait_for_poll()
    end

    test "reset_fingerprint/0 clears last_changed_at too", %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [coin(symbol: "ETH", name: "Ethereum", position: 1, in_top: true)]
          )
        )
      end)

      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, api_grace_period_response(coins: []))
      end)

      Phoenix.PubSub.subscribe(CoinTracker.PubSub, Poller.status_topic())
      Poller.poll_now()
      assert_receive {:poller_status_updated, _}, 500
      assert %{fingerprint: fp, last_changed_at: %DateTime{}} = Poller.get_status()
      assert is_integer(fp)

      Poller.reset_fingerprint()
      assert %{fingerprint: nil, last_changed_at: nil} = Poller.get_status()
    end

    test "reset_fingerprint/0 forces the next poll to run the full pipeline",
         %{bypass: bypass} do
      test_pid = self()

      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [coin(symbol: "ETH", name: "Ethereum", position: 1, in_top: true)]
          )
        )
      end)

      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        send(test_pid, :grace_period_called)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, api_grace_period_response(coins: []))
      end)

      Poller.poll_now()
      assert_receive :grace_period_called, 500

      # Without reset, the second identical poll would short-circuit.
      Poller.reset_fingerprint()
      Poller.poll_now()
      assert_receive :grace_period_called, 500

      wait_for_poll()
    end
  end
end
