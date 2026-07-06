defmodule CoinTracker.SignalsTest do
  # Not async because we're modifying Application config for CoinscanApiClient
  use CoinTracker.DataCase, async: false

  alias CoinTracker.Signals
  alias CoinTracker.Signals.Signal
  import CoinTracker.ApiFixtures

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

    on_exit(fn ->
      Application.put_env(:coin_tracker, CoinTracker.Signals.CoinscanApiClient, original_config)
    end)

    {:ok, bypass: bypass}
  end

  describe "ingest_top_10/0" do
    test "successfully ingests top 10 signals from API", %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, top10_response())
      end)

      assert {:ok, 2} = Signals.ingest_top_10()

      signals = Signals.list_signals(in_top: true)
      assert length(signals) == 2

      # Verify TRAC signal was inserted correctly
      trac = Enum.find(signals, &(&1.symbol == "TRAC"))
      assert trac.name == "OriginTrail"
      assert Decimal.equal?(trac.initial_price_usd, Decimal.new("0.6047"))
      assert trac.in_top == true
      assert trac.active == true
    end

    test "returns error when API request fails", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, :network_error} = Signals.ingest_top_10()
    end

    test "handles empty API response", %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, api_top10_response(coins: []))
      end)

      assert {:ok, 0} = Signals.ingest_top_10()
      assert Signals.list_signals(in_top: true) == []
    end
  end

  describe "ingest_grace_period/0" do
    test "successfully ingests grace period signals from API", %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, grace_period_response())
      end)

      assert {:ok, 1} = Signals.ingest_grace_period()

      signals = Signals.list_signals(in_top: false)
      assert length(signals) == 1

      # Verify SNX signal was inserted correctly
      snx = List.first(signals)
      assert snx.symbol == "SNX"
      assert snx.name == "Synthetix"
      assert snx.in_top == false
      assert snx.active == true
      assert snx.exit_date != nil
    end

    test "returns error when API request fails", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, :network_error} = Signals.ingest_grace_period()
    end
  end

  describe "ingest_all/0" do
    test "successfully ingests both top 10 and grace period", %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, top10_response())
      end)

      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, grace_period_response())
      end)

      assert {:ok, %{top_10: 2, grace_period: 1}} = Signals.ingest_all()

      assert length(Signals.list_signals()) == 3
    end

    test "returns partial error when one endpoint fails", %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, top10_response())
      end)

      # Grace period endpoint fails
      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      assert {:error, %{top_10: {:ok, 2}, grace_period: {:error, _}}} = Signals.ingest_all()

      # Top 10 should still be ingested
      assert length(Signals.list_signals(in_top: true)) == 2
    end
  end

  describe "upsert logic" do
    test "inserts new signal when it doesn't exist", %{bypass: bypass} do
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, top10_response())
      end)

      assert {:ok, 2} = Signals.ingest_top_10()

      trac = CoinTracker.Repo.get_by(Signal, symbol: "TRAC")
      assert trac != nil
      assert trac.symbol == "TRAC"
    end

    test "updates existing signal with mutable fields", %{bypass: bypass} do
      fresh_timestamp =
        DateTime.utc_now()
        |> DateTime.add(-60, :second)
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      # First ingestion
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [
              coin(
                symbol: "BTC",
                name: "Bitcoin",
                initial_price_usd: 50000.0,
                max_price_usd: 51000.0,
                max_increase_percentage: 2.0,
                in_top_since: fresh_timestamp,
                volumen24h: 1_000_000
              )
            ]
          )
        )
      end)

      assert {:ok, 1} = Signals.ingest_top_10()
      first_signal = CoinTracker.Repo.get_by(Signal, symbol: "BTC")
      first_id = first_signal.id

      assert Decimal.equal?(first_signal.initial_price_usd, Decimal.new("50000.0"))
      assert Decimal.equal?(first_signal.max_price_usd, Decimal.new("51000.0"))
      assert Decimal.equal?(first_signal.initial_volume_24h, Decimal.new("1000000"))

      # Second ingestion with updated values
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [
              coin(
                symbol: "BTC",
                name: "Bitcoin",
                initial_price_usd: 50000.0,
                max_price_usd: 55000.0,
                max_increase_percentage: 10.0,
                in_top_since: fresh_timestamp,
                volumen24h: 2_000_000
              )
            ]
          )
        )
      end)

      assert {:ok, 1} = Signals.ingest_top_10()
      updated_signal = CoinTracker.Repo.get_by(Signal, symbol: "BTC")

      # Should be same record (same ID)
      assert updated_signal.id == first_id

      # Immutable fields should NOT change
      assert Decimal.equal?(updated_signal.initial_price_usd, Decimal.new("50000.0"))
      assert Decimal.equal?(updated_signal.initial_volume_24h, Decimal.new("1000000"))
      assert updated_signal.in_top_since == first_signal.in_top_since

      # Mutable fields SHOULD change
      assert Decimal.equal?(updated_signal.max_price_usd, Decimal.new("55000.0"))
      assert Decimal.equal?(updated_signal.max_increase_percentage, Decimal.new("10.0"))
      assert Decimal.equal?(updated_signal.current_volume_24h, Decimal.new("2000000"))
    end

    test "creates separate records for same symbol with different in_top_since", %{
      bypass: bypass
    } do
      # First ingestion - BTC enters top 10 on date 1
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [
              coin(
                symbol: "BTC",
                name: "Bitcoin",
                initial_price_usd: 50000.0,
                max_price_usd: 51000.0,
                in_top_since: "2025-10-18T00:00:00+00:00",
                volumen24h: 1_000_000
              )
            ]
          )
        )
      end)

      assert {:ok, 1} = Signals.ingest_top_10()

      # Second ingestion - BTC enters top 10 again on different date
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [
              coin(
                symbol: "BTC",
                name: "Bitcoin",
                initial_price_usd: 60000.0,
                max_price_usd: 61000.0,
                in_top_since: "2025-10-20T00:00:00+00:00",
                volumen24h: 1_500_000
              )
            ]
          )
        )
      end)

      assert {:ok, 1} = Signals.ingest_top_10()

      # Should have 2 separate BTC records
      btc_signals =
        Signal
        |> where([s], s.symbol == "BTC")
        |> order_by([s], asc: s.in_top_since)
        |> Repo.all()

      assert length(btc_signals) == 2
      assert Decimal.equal?(Enum.at(btc_signals, 0).initial_price_usd, Decimal.new("50000.0"))
      assert Decimal.equal?(Enum.at(btc_signals, 1).initial_price_usd, Decimal.new("60000.0"))
    end

    test "initial volume is captured on first insert and remains immutable", %{
      bypass: bypass
    } do
      stale_timestamp =
        DateTime.utc_now()
        |> DateTime.add(-600, :second)
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [
              coin(
                symbol: "STALE",
                name: "StaleCoin",
                initial_price_usd: 10.0,
                max_price_usd: 10.5,
                in_top_since: stale_timestamp,
                volumen24h: 1_000_000
              )
            ]
          )
        )
      end)

      assert {:ok, 1} = Signals.ingest_top_10()

      stale_signal = CoinTracker.Repo.get_by(Signal, symbol: "STALE")
      # Initial volume is now captured on first insert regardless of signal age
      assert Decimal.equal?(stale_signal.initial_volume_24h, Decimal.new("1000000"))
      assert Decimal.equal?(stale_signal.current_volume_24h, Decimal.new("1000000"))

      # Second ingestion should update the current volume but keep initial volume immutable
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [
              coin(
                symbol: "STALE",
                name: "StaleCoin",
                initial_price_usd: 10.0,
                max_price_usd: 11.0,
                in_top_since: stale_timestamp,
                volumen24h: 5_000_000
              )
            ]
          )
        )
      end)

      assert {:ok, 1} = Signals.ingest_top_10()

      updated_stale_signal = CoinTracker.Repo.get_by(Signal, symbol: "STALE")
      # Initial volume stays at 1000000 (immutable), current volume is updated
      assert Decimal.equal?(updated_stale_signal.initial_volume_24h, Decimal.new("1000000"))
      assert Decimal.equal?(updated_stale_signal.current_volume_24h, Decimal.new("5000000"))
    end

    test "refreshes current_volume_24h when the grace-period API returns a new value",
         %{bypass: bypass} do
      fresh_timestamp =
        DateTime.utc_now()
        |> DateTime.add(-60, :second)
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      # First ingestion: signal enters top 10 with an initial volume.
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [
              coin(
                symbol: "EXIT",
                name: "ExitCoin",
                initial_price_usd: 10.0,
                max_price_usd: 12.0,
                in_top_since: fresh_timestamp,
                volumen24h: 5_000_000,
                in_top: true
              )
            ]
          )
        )
      end)

      assert {:ok, 1} = Signals.ingest_top_10()

      signal_in_top = CoinTracker.Repo.get_by(Signal, symbol: "EXIT")
      assert signal_in_top.in_top == true
      assert Decimal.equal?(signal_in_top.current_volume_24h, Decimal.new("5000000"))

      # Coin exits top 10. The grace-period endpoint now reports a fresh
      # 24h volume — this is the value we want to surface for grace-period UIs.
      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_grace_period_response(
            coins: [
              coin(
                symbol: "EXIT",
                name: "ExitCoin",
                in_top_since: fresh_timestamp,
                in_top: false,
                volumen24h: 7_500_000
              )
            ]
          )
        )
      end)

      assert {:ok, 1} = Signals.ingest_grace_period()

      signal_in_grace = CoinTracker.Repo.get_by(Signal, symbol: "EXIT")
      assert signal_in_grace.in_top == false
      # initial_volume_24h stays locked at the first-seen value
      assert Decimal.equal?(signal_in_grace.initial_volume_24h, Decimal.new("5000000"))
      # current_volume_24h reflects the latest grace-period reading
      assert Decimal.equal?(signal_in_grace.current_volume_24h, Decimal.new("7500000"))
    end

    test "preserves current_volume_24h when the API omits volumen24h", %{bypass: bypass} do
      fresh_timestamp =
        DateTime.utc_now()
        |> DateTime.add(-60, :second)
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      # First ingestion captures a healthy volume.
      Bypass.stub(bypass, "GET", "/v3/top10", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_top10_response(
            coins: [
              coin(
                symbol: "HICCUP",
                name: "HiccupCoin",
                initial_price_usd: 1.0,
                max_price_usd: 1.0,
                in_top_since: fresh_timestamp,
                volumen24h: 4_200_000,
                in_top: true
              )
            ]
          )
        )
      end)

      assert {:ok, 1} = Signals.ingest_top_10()

      # Upstream regression / partial response: the next grace-period payload
      # is missing `volumen24h` entirely. COALESCE in the upsert must keep
      # the last known good value rather than nulling it out.
      Bypass.stub(bypass, "GET", "/v3/periodo-gracia", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          api_grace_period_response(
            coins: [
              coin(
                symbol: "HICCUP",
                name: "HiccupCoin",
                in_top_since: fresh_timestamp,
                in_top: false
                # volumen24h intentionally omitted
              )
            ]
          )
        )
      end)

      assert {:ok, 1} = Signals.ingest_grace_period()

      preserved = CoinTracker.Repo.get_by(Signal, symbol: "HICCUP")
      assert preserved.in_top == false
      assert Decimal.equal?(preserved.current_volume_24h, Decimal.new("4200000"))
    end
  end

  describe "list_signals/1" do
    setup do
      # Insert test data
      insert_test_signals()
      :ok
    end

    test "lists all signals without filters" do
      signals = Signals.list_signals()
      assert length(signals) == 3
    end

    test "filters by active status" do
      active_signals = Signals.list_signals(active: true)
      assert length(active_signals) == 2
    end

    test "filters by in_top status" do
      in_top_signals = Signals.list_signals(in_top: true)
      assert length(in_top_signals) == 2
    end

    test "filters by symbol" do
      btc_signals = Signals.list_signals(symbol: "BTC")
      assert length(btc_signals) == 1
      assert List.first(btc_signals).symbol == "BTC"
    end

    test "applies limit" do
      signals = Signals.list_signals(limit: 2)
      assert length(signals) == 2
    end

    test "applies custom ordering" do
      signals = Signals.list_signals(order_by: [asc: :symbol])
      symbols = Enum.map(signals, & &1.symbol)
      assert symbols == Enum.sort(symbols)
    end

    test "combines multiple filters" do
      signals = Signals.list_signals(active: true, in_top: true, limit: 1)
      assert length(signals) == 1
    end
  end

  describe "deactivate_expired_signals/0" do
    test "deactivates signals with exit_date older than 24 hours" do
      old_exit = DateTime.add(DateTime.utc_now(), -25, :hour)

      insert_test_signal("OLD", ~U[2025-01-01 00:00:00Z], %{
        active: true,
        in_top: false,
        exit_date: old_exit
      })

      assert {:ok, 1} = Signals.deactivate_expired_signals()

      signal = Signals.list_signals(symbol: "OLD") |> List.first()
      assert signal.active == false
    end

    test "does not deactivate signals with exit_date less than 24 hours ago" do
      recent_exit = DateTime.add(DateTime.utc_now(), -23, :hour)

      insert_test_signal("RECENT", ~U[2025-01-01 00:00:00Z], %{
        active: true,
        in_top: false,
        exit_date: recent_exit
      })

      assert {:ok, 0} = Signals.deactivate_expired_signals()

      signal = Signals.list_signals(symbol: "RECENT") |> List.first()
      assert signal.active == true
    end

    test "does not deactivate signals without exit_date" do
      insert_test_signal("NOTOP", ~U[2025-01-01 00:00:00Z], %{
        active: true,
        in_top: true,
        exit_date: nil
      })

      assert {:ok, 0} = Signals.deactivate_expired_signals()

      signal = Signals.list_signals(symbol: "NOTOP") |> List.first()
      assert signal.active == true
    end

    test "does not deactivate already inactive signals" do
      old_exit = DateTime.add(DateTime.utc_now(), -25, :hour)

      insert_test_signal("INACTIVE", ~U[2025-01-01 00:00:00Z], %{
        active: false,
        in_top: false,
        exit_date: old_exit
      })

      assert {:ok, 0} = Signals.deactivate_expired_signals()
    end

    test "deactivates multiple expired signals at once" do
      old_exit = DateTime.add(DateTime.utc_now(), -30, :hour)

      insert_test_signal("EXP1", ~U[2025-01-01 00:00:00Z], %{
        active: true,
        in_top: false,
        exit_date: old_exit
      })

      insert_test_signal("EXP2", ~U[2025-01-02 00:00:00Z], %{
        active: true,
        in_top: false,
        exit_date: old_exit
      })

      assert {:ok, 2} = Signals.deactivate_expired_signals()

      signals = Signals.list_signals()
      assert Enum.all?(signals, fn s -> s.active == false end)
    end
  end

  # Helper functions

  defp insert_test_signals do
    insert_test_signal("BTC", ~U[2025-10-18 00:00:00Z], %{
      in_top: true,
      active: true,
      initial_price_usd: Decimal.new("50000")
    })

    insert_test_signal("ETH", ~U[2025-10-18 00:00:00Z], %{
      in_top: true,
      active: true,
      initial_price_usd: Decimal.new("3000")
    })

    insert_test_signal("XRP", ~U[2025-10-17 00:00:00Z], %{
      in_top: false,
      active: false,
      initial_price_usd: Decimal.new("0.50"),
      exit_date: ~U[2025-10-18 00:00:00Z]
    })
  end

  defp insert_test_signal(symbol, in_top_since, attrs) do
    default_attrs = %{
      symbol: symbol,
      name: "#{symbol} Name",
      in_top_since: in_top_since,
      in_top: true,
      active: true
    }

    attrs = Map.merge(default_attrs, attrs)

    %Signal{}
    |> Signal.changeset(attrs)
    |> Repo.insert!()
  end

  defp top10_response do
    api_top10_response(
      coins: [
        coin(
          symbol: "TRAC",
          name: "OriginTrail",
          initial_price_usd: 0.6047,
          max_price_usd: 0.8348,
          max_increase_percentage: 38.06,
          in_top_since: "2025-10-12T00:50:02+00:00",
          volumen24h: 9_972_980
        ),
        coin(
          symbol: "RSR",
          name: "Reserve Rights",
          initial_price_usd: 0.006263,
          max_price_usd: 0.006993,
          max_increase_percentage: 11.67,
          in_top_since: "2025-10-15T04:20:20+00:00",
          volumen24h: 49_102_244
        )
      ]
    )
  end

  defp grace_period_response do
    api_grace_period_response(
      coins: [
        coin(
          symbol: "SNX",
          name: "Synthetix",
          initial_price_usd: 1.29,
          max_price_usd: 2.51,
          max_increase_percentage: 94.57,
          in_top_since: "2025-10-12T16:10:03+00:00",
          exit_date: "2025-10-18T02:40:02+00:00",
          in_top: false
        )
      ]
    )
  end

  # =============================================================================
  # Market Status Tests
  # =============================================================================

  describe "create_market_status/0" do
    test "creates market status with current active signals count" do
      # Create some active signals in top 10
      insert_test_signal("BTC", ~U[2025-10-18 00:00:00Z], %{in_top: true, active: true})
      insert_test_signal("ETH", ~U[2025-10-18 00:00:00Z], %{in_top: true, active: true})
      insert_test_signal("XRP", ~U[2025-10-17 00:00:00Z], %{in_top: false, active: true})

      assert {:ok, market_status} = Signals.create_market_status()
      assert market_status.active_signals_count == 2
      assert market_status.recorded_at != nil
    end

    test "broadcasts via PubSub after creation" do
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "market_status:updated")

      {:ok, market_status} = Signals.create_market_status()

      assert_receive {:market_status_created, ^market_status}
    end

    test "records timestamp truncated to seconds" do
      {:ok, market_status} = Signals.create_market_status()

      # Microseconds should be {0, 6} (truncated to second precision)
      assert market_status.recorded_at.microsecond == {0, 0}
    end
  end

  describe "count_active_signals/0" do
    test "returns 0 when no signals exist" do
      assert Signals.count_active_signals() == 0
    end

    test "counts only signals with active: true AND in_top: true" do
      insert_test_signal("BTC", ~U[2025-10-18 00:00:00Z], %{in_top: true, active: true})
      insert_test_signal("ETH", ~U[2025-10-18 00:00:00Z], %{in_top: true, active: true})
      insert_test_signal("SOL", ~U[2025-10-18 00:00:00Z], %{in_top: true, active: true})

      assert Signals.count_active_signals() == 3
    end

    test "excludes signals that are active but not in_top" do
      insert_test_signal("BTC", ~U[2025-10-18 00:00:00Z], %{in_top: true, active: true})
      insert_test_signal("ETH", ~U[2025-10-18 00:00:00Z], %{in_top: false, active: true})

      assert Signals.count_active_signals() == 1
    end

    test "excludes signals that are in_top but not active" do
      insert_test_signal("BTC", ~U[2025-10-18 00:00:00Z], %{in_top: true, active: true})
      insert_test_signal("ETH", ~U[2025-10-18 00:00:00Z], %{in_top: true, active: false})

      assert Signals.count_active_signals() == 1
    end
  end

  describe "count_total_active_signals/0" do
    test "returns 0 when no signals exist" do
      assert Signals.count_total_active_signals() == 0
    end

    test "counts all active signals regardless of in_top" do
      insert_test_signal("BTC", ~U[2025-10-18 00:00:00Z], %{in_top: true, active: true})
      insert_test_signal("ETH", ~U[2025-10-18 00:00:00Z], %{in_top: false, active: true})
      insert_test_signal("SOL", ~U[2025-10-18 00:00:00Z], %{in_top: true, active: true})

      assert Signals.count_total_active_signals() == 3
    end

    test "excludes inactive signals" do
      insert_test_signal("BTC", ~U[2025-10-18 00:00:00Z], %{in_top: true, active: true})
      insert_test_signal("ETH", ~U[2025-10-18 00:00:00Z], %{in_top: true, active: false})

      assert Signals.count_total_active_signals() == 1
    end
  end

  describe "list_market_statuses/1" do
    import CoinTracker.SignalsFixtures, only: [market_status_fixture: 1]

    test "returns all statuses ordered by recorded_at desc by default" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      earlier = DateTime.add(now, -3600, :second)
      earliest = DateTime.add(now, -7200, :second)

      _status1 = market_status_fixture(%{recorded_at: earliest, active_signals_count: 3})
      _status2 = market_status_fixture(%{recorded_at: earlier, active_signals_count: 5})
      _status3 = market_status_fixture(%{recorded_at: now, active_signals_count: 7})

      statuses = Signals.list_market_statuses()

      assert length(statuses) == 3
      # Default order is desc by recorded_at
      counts = Enum.map(statuses, & &1.active_signals_count)
      assert counts == [7, 5, 3]
    end

    test "filters by :from datetime" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      one_hour_ago = DateTime.add(now, -3600, :second)
      two_hours_ago = DateTime.add(now, -7200, :second)

      _old_status = market_status_fixture(%{recorded_at: two_hours_ago, active_signals_count: 3})
      _recent_status = market_status_fixture(%{recorded_at: now, active_signals_count: 7})

      statuses = Signals.list_market_statuses(from: one_hour_ago)

      assert length(statuses) == 1
      assert List.first(statuses).active_signals_count == 7
    end

    test "filters by :to datetime" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      one_hour_ago = DateTime.add(now, -3600, :second)
      two_hours_ago = DateTime.add(now, -7200, :second)

      _old_status = market_status_fixture(%{recorded_at: two_hours_ago, active_signals_count: 3})
      _recent_status = market_status_fixture(%{recorded_at: now, active_signals_count: 7})

      statuses = Signals.list_market_statuses(to: one_hour_ago)

      assert length(statuses) == 1
      assert List.first(statuses).active_signals_count == 3
    end

    test "applies :limit option" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for i <- 1..5 do
        recorded_at = DateTime.add(now, -i * 60, :second)
        market_status_fixture(%{recorded_at: recorded_at, active_signals_count: i})
      end

      statuses = Signals.list_market_statuses(limit: 2)

      assert length(statuses) == 2
    end

    test "applies custom :order_by option" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      market_status_fixture(%{recorded_at: now, active_signals_count: 5})

      market_status_fixture(%{
        recorded_at: DateTime.add(now, -60, :second),
        active_signals_count: 2
      })

      market_status_fixture(%{
        recorded_at: DateTime.add(now, -120, :second),
        active_signals_count: 8
      })

      statuses = Signals.list_market_statuses(order_by: [asc: :active_signals_count])

      counts = Enum.map(statuses, & &1.active_signals_count)
      assert counts == [2, 5, 8]
    end

    test "returns empty list when no statuses exist" do
      assert Signals.list_market_statuses() == []
    end
  end

  describe "list_market_statuses_aggregated/1" do
    import CoinTracker.SignalsFixtures, only: [market_status_fixture: 1]

    test "returns raw data for 'today' period" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      market_status_fixture(%{recorded_at: now, active_signals_count: 5})

      market_status_fixture(%{
        recorded_at: DateTime.add(now, -60, :second),
        active_signals_count: 6
      })

      statuses = Signals.list_market_statuses_aggregated("today")

      # Should return raw MarketStatus structs for "today"
      assert length(statuses) == 2
      assert Enum.all?(statuses, &match?(%Signals.MarketStatus{}, &1))
    end

    test "returns hourly averages for 'week' period" do
      # Create statuses with the same hour but different minutes
      base_time = DateTime.utc_now() |> DateTime.truncate(:second)
      hour_start = %{base_time | minute: 0, second: 0, microsecond: {0, 0}}

      # Two statuses in the same hour
      market_status_fixture(%{
        recorded_at: %{hour_start | minute: 10},
        active_signals_count: 4
      })

      market_status_fixture(%{
        recorded_at: %{hour_start | minute: 40},
        active_signals_count: 6
      })

      statuses = Signals.list_market_statuses_aggregated("week")

      # Should be aggregated to hourly average: (4 + 6) / 2 = 5
      assert length(statuses) == 1
      assert List.first(statuses).active_signals_count == 5
    end

    test "returns 4-hour averages for 'month' period" do
      # Create statuses within same 4-hour bucket
      base_time = DateTime.utc_now() |> DateTime.truncate(:second)
      # Use hour 8 which is in bucket 8-11
      bucket_start = %{base_time | hour: 8, minute: 0, second: 0, microsecond: {0, 0}}

      market_status_fixture(%{
        recorded_at: %{bucket_start | hour: 8, minute: 30},
        active_signals_count: 4
      })

      market_status_fixture(%{
        recorded_at: %{bucket_start | hour: 10, minute: 15},
        active_signals_count: 8
      })

      statuses = Signals.list_market_statuses_aggregated("month")

      # Should be aggregated: (4 + 8) / 2 = 6
      assert length(statuses) == 1
      assert List.first(statuses).active_signals_count == 6
    end

    test "handles empty result sets gracefully" do
      assert Signals.list_market_statuses_aggregated("today") == []
      assert Signals.list_market_statuses_aggregated("week") == []
      assert Signals.list_market_statuses_aggregated("month") == []
    end
  end

  describe "aggregate_by_hour/1 (private, tested via list_market_statuses_aggregated)" do
    import CoinTracker.SignalsFixtures, only: [market_status_fixture: 1]

    test "groups statuses by hour" do
      base_time = DateTime.utc_now() |> DateTime.truncate(:second)
      hour1 = %{base_time | hour: 10, minute: 0, second: 0, microsecond: {0, 0}}
      hour2 = %{base_time | hour: 11, minute: 0, second: 0, microsecond: {0, 0}}

      # Two statuses in hour 10
      market_status_fixture(%{recorded_at: %{hour1 | minute: 15}, active_signals_count: 3})
      market_status_fixture(%{recorded_at: %{hour1 | minute: 45}, active_signals_count: 5})

      # One status in hour 11
      market_status_fixture(%{recorded_at: %{hour2 | minute: 30}, active_signals_count: 7})

      statuses = Signals.list_market_statuses_aggregated("week")

      assert length(statuses) == 2
      counts = Enum.map(statuses, & &1.active_signals_count)
      # Hour 10: (3+5)/2 = 4, Hour 11: 7
      assert Enum.sort(counts) == [4, 7]
    end

    test "calculates average active_signals_count per hour using floor division" do
      base_time = DateTime.utc_now() |> DateTime.truncate(:second)
      hour1 = %{base_time | hour: 10, minute: 0, second: 0, microsecond: {0, 0}}

      # Three statuses that average to 4.33... should floor to 4
      market_status_fixture(%{recorded_at: %{hour1 | minute: 10}, active_signals_count: 3})
      market_status_fixture(%{recorded_at: %{hour1 | minute: 30}, active_signals_count: 5})
      market_status_fixture(%{recorded_at: %{hour1 | minute: 50}, active_signals_count: 5})

      statuses = Signals.list_market_statuses_aggregated("week")

      # (3 + 5 + 5) / 3 = 4.33... floored to 4
      assert length(statuses) == 1
      assert List.first(statuses).active_signals_count == 4
    end

    test "handles single item per hour bucket" do
      base_time = DateTime.utc_now() |> DateTime.truncate(:second)
      hour1 = %{base_time | hour: 10, minute: 30, second: 0, microsecond: {0, 0}}

      market_status_fixture(%{recorded_at: hour1, active_signals_count: 7})

      statuses = Signals.list_market_statuses_aggregated("week")

      assert length(statuses) == 1
      assert List.first(statuses).active_signals_count == 7
    end
  end

  describe "aggregate_by_four_hours/1 (private, tested via list_market_statuses_aggregated)" do
    import CoinTracker.SignalsFixtures, only: [market_status_fixture: 1]

    test "groups statuses into 4-hour buckets (0, 4, 8, 12, 16, 20)" do
      base_time = DateTime.utc_now() |> DateTime.truncate(:second)

      # Bucket 0-3
      market_status_fixture(%{
        recorded_at: %{base_time | hour: 1, minute: 30, second: 0, microsecond: {0, 0}},
        active_signals_count: 3
      })

      # Bucket 4-7
      market_status_fixture(%{
        recorded_at: %{base_time | hour: 5, minute: 0, second: 0, microsecond: {0, 0}},
        active_signals_count: 5
      })

      # Another in bucket 4-7
      market_status_fixture(%{
        recorded_at: %{base_time | hour: 7, minute: 30, second: 0, microsecond: {0, 0}},
        active_signals_count: 7
      })

      statuses = Signals.list_market_statuses_aggregated("month")

      assert length(statuses) == 2
      # Bucket 0: 3, Bucket 4: (5+7)/2 = 6
      counts = Enum.map(statuses, & &1.active_signals_count) |> Enum.sort()
      assert counts == [3, 6]
    end

    test "calculates average active_signals_count per bucket using floor division" do
      base_time = DateTime.utc_now() |> DateTime.truncate(:second)

      # Three statuses in bucket 8-11 that average to 4.33...
      market_status_fixture(%{
        recorded_at: %{base_time | hour: 8, minute: 0, second: 0, microsecond: {0, 0}},
        active_signals_count: 3
      })

      market_status_fixture(%{
        recorded_at: %{base_time | hour: 9, minute: 30, second: 0, microsecond: {0, 0}},
        active_signals_count: 5
      })

      market_status_fixture(%{
        recorded_at: %{base_time | hour: 11, minute: 0, second: 0, microsecond: {0, 0}},
        active_signals_count: 5
      })

      statuses = Signals.list_market_statuses_aggregated("month")

      # (3 + 5 + 5) / 3 = 4.33... floored to 4
      assert length(statuses) == 1
      assert List.first(statuses).active_signals_count == 4
    end

    test "handles single item per bucket" do
      base_time = DateTime.utc_now() |> DateTime.truncate(:second)

      market_status_fixture(%{
        recorded_at: %{base_time | hour: 14, minute: 30, second: 0, microsecond: {0, 0}},
        active_signals_count: 8
      })

      statuses = Signals.list_market_statuses_aggregated("month")

      assert length(statuses) == 1
      assert List.first(statuses).active_signals_count == 8
    end
  end

  describe "get_previous_occurrences/3 and count_previous_occurrences/2" do
    import CoinTracker.SignalsFixtures,
      only: [signal_fixture: 1, snapshot_fixture: 2]

    setup do
      base = ~U[2025-01-01 00:00:00Z]
      {:ok, base: base}
    end

    test "returns prior occurrences for the same symbol excluding the current signal", %{
      base: base
    } do
      symbol = "HIST1"

      # Three signals for the same symbol at different times
      oldest =
        signal_fixture(%{
          symbol: symbol,
          in_top_since: DateTime.add(base, -3, :day),
          exit_date: DateTime.add(base, -2, :day),
          initial_price_usd: Decimal.new("1.00"),
          current_price_usd: Decimal.new("2.00")
        })

      middle =
        signal_fixture(%{
          symbol: symbol,
          in_top_since: DateTime.add(base, -2, :day),
          exit_date: DateTime.add(base, -1, :day),
          initial_price_usd: Decimal.new("2.00"),
          current_price_usd: Decimal.new("1.50")
        })

      current =
        signal_fixture(%{
          symbol: symbol,
          in_top_since: base,
          initial_price_usd: Decimal.new("1.50"),
          current_price_usd: Decimal.new("1.80")
        })

      occurrences = Signals.get_previous_occurrences(symbol, current.id)

      assert length(occurrences) == 2
      [first, second] = occurrences

      # Ordered desc by in_top_since
      assert first.signal.id == middle.id
      assert second.signal.id == oldest.id

      # Current signal is excluded
      refute Enum.any?(occurrences, fn o -> o.signal.id == current.id end)

      assert Signals.count_previous_occurrences(symbol, current.id) == 2
    end

    test "honours the :limit option", %{base: base} do
      symbol = "HIST2"

      for i <- 1..7 do
        signal_fixture(%{
          symbol: symbol,
          in_top_since: DateTime.add(base, -i, :day),
          exit_date: DateTime.add(base, -i, :hour),
          initial_price_usd: Decimal.new("1.00"),
          current_price_usd: Decimal.new("1.00")
        })
      end

      # Use a non-existent id to exclude nothing
      occurrences = Signals.get_previous_occurrences(symbol, -1, limit: 3)
      assert length(occurrences) == 3

      all_occurrences = Signals.get_previous_occurrences(symbol, -1, limit: :all)
      assert length(all_occurrences) == 7
    end

    test "computes entry/exit prices with last snapshot fallback", %{base: base} do
      symbol = "HIST3"

      past =
        signal_fixture(%{
          symbol: symbol,
          in_top_since: DateTime.add(base, -1, :day),
          exit_date: DateTime.add(base, -12, :hour),
          initial_price_usd: Decimal.new("10.00"),
          current_price_usd: Decimal.new("99.00")
        })

      # Most recent snapshot should be the source of the exit price
      snapshot_fixture(past, %{
        snapshot_at: DateTime.add(base, -23, :hour),
        current_price_usd: Decimal.new("11.00"),
        in_top: true,
        position: 1
      })

      snapshot_fixture(past, %{
        snapshot_at: DateTime.add(base, -13, :hour),
        current_price_usd: Decimal.new("13.50"),
        in_top: true,
        position: 2
      })

      current = signal_fixture(%{symbol: symbol, in_top_since: base})

      [occurrence] = Signals.get_previous_occurrences(symbol, current.id)

      assert Decimal.equal?(occurrence.entry_price, Decimal.new("10.00"))
      assert Decimal.equal?(occurrence.exit_price, Decimal.new("13.50"))
      assert occurrence.entry_at == past.in_top_since
      assert occurrence.exit_at == past.exit_date
    end

    test "uses Signal.max_price_usd as the top price when set", %{base: base} do
      symbol = "HIST_TOP1"

      past =
        signal_fixture(%{
          symbol: symbol,
          in_top_since: DateTime.add(base, -2, :day),
          exit_date: DateTime.add(base, -1, :day),
          initial_price_usd: Decimal.new("10.00"),
          current_price_usd: Decimal.new("12.00"),
          max_price_usd: Decimal.new("25.50")
        })

      current = signal_fixture(%{symbol: symbol, in_top_since: base})

      [occurrence] = Signals.get_previous_occurrences(symbol, current.id)

      assert Decimal.equal?(occurrence.top_price, Decimal.new("25.50"))
      assert occurrence.signal.id == past.id
    end

    test "falls back to max snapshot price when Signal.max_price_usd is nil", %{base: base} do
      symbol = "HIST_TOP2"

      past =
        signal_fixture(%{
          symbol: symbol,
          in_top_since: DateTime.add(base, -2, :day),
          exit_date: DateTime.add(base, -1, :day),
          initial_price_usd: Decimal.new("10.00"),
          current_price_usd: Decimal.new("12.00"),
          max_price_usd: nil
        })

      snapshot_fixture(past, %{
        snapshot_at: DateTime.add(base, -47, :hour),
        current_price_usd: Decimal.new("11.00"),
        in_top: true,
        position: 1
      })

      snapshot_fixture(past, %{
        snapshot_at: DateTime.add(base, -36, :hour),
        current_price_usd: Decimal.new("18.75"),
        in_top: true,
        position: 1
      })

      snapshot_fixture(past, %{
        snapshot_at: DateTime.add(base, -25, :hour),
        current_price_usd: Decimal.new("14.00"),
        in_top: true,
        position: 2
      })

      current = signal_fixture(%{symbol: symbol, in_top_since: base})

      [occurrence] = Signals.get_previous_occurrences(symbol, current.id)

      assert Decimal.equal?(occurrence.top_price, Decimal.new("18.75"))
    end

    test "top_price is nil when max_price_usd is nil and there are no snapshots", %{base: base} do
      symbol = "HIST_TOP3"

      signal_fixture(%{
        symbol: symbol,
        in_top_since: DateTime.add(base, -2, :day),
        exit_date: DateTime.add(base, -1, :day),
        initial_price_usd: Decimal.new("10.00"),
        current_price_usd: Decimal.new("12.00"),
        max_price_usd: nil
      })

      current = signal_fixture(%{symbol: symbol, in_top_since: base})

      [occurrence] = Signals.get_previous_occurrences(symbol, current.id)

      assert occurrence.top_price == nil
    end

    test "falls back to Signal.current_price_usd when there are no snapshots", %{base: base} do
      symbol = "HIST4"

      past =
        signal_fixture(%{
          symbol: symbol,
          in_top_since: DateTime.add(base, -2, :day),
          exit_date: DateTime.add(base, -1, :day),
          initial_price_usd: Decimal.new("5.00"),
          current_price_usd: Decimal.new("7.00")
        })

      current = signal_fixture(%{symbol: symbol, in_top_since: base})

      [occurrence] = Signals.get_previous_occurrences(symbol, current.id)

      assert Decimal.equal?(occurrence.exit_price, Decimal.new("7.00"))
      assert occurrence.position_durations == %{}
      assert occurrence.best_position == nil
      # Exited signal: duration is exit_date - in_top_since = 1 day
      assert occurrence.duration_seconds == 86_400
      assert occurrence.signal.id == past.id
    end

    test "sums position durations from consecutive snapshots", %{base: base} do
      symbol = "HIST5"

      past =
        signal_fixture(%{
          symbol: symbol,
          in_top_since: DateTime.add(base, -6, :hour),
          exit_date: base,
          initial_price_usd: Decimal.new("1.00"),
          current_price_usd: Decimal.new("1.00")
        })

      # 6 snapshots, 10 minutes apart (600s each)
      # positions: [1, 1, 2, 2, 2, 9]
      # Expected durations (using delta-to-next, last falls back to median interval of 600s):
      #   position 1: 600 + 600 = 1200
      #   position 2: 600 + 600 + 600 = 1800
      #   position 9: 600 (fallback for final snapshot)
      positions = [1, 1, 2, 2, 2, 9]

      positions
      |> Enum.with_index()
      |> Enum.each(fn {position, idx} ->
        snapshot_fixture(past, %{
          snapshot_at: DateTime.add(base, -6 * 600 + idx * 600, :second),
          current_price_usd: Decimal.new("1.00"),
          in_top: true,
          position: position
        })
      end)

      current = signal_fixture(%{symbol: symbol, in_top_since: base})

      [occurrence] = Signals.get_previous_occurrences(symbol, current.id)

      assert occurrence.position_durations == %{1 => 1200, 2 => 1800, 9 => 600}
      assert occurrence.best_position == 1
    end

    test "ignores snapshots with nil position or in_top false", %{base: base} do
      symbol = "HIST6"

      past =
        signal_fixture(%{
          symbol: symbol,
          in_top_since: DateTime.add(base, -2, :hour),
          exit_date: base,
          initial_price_usd: Decimal.new("1.00"),
          current_price_usd: Decimal.new("1.00")
        })

      # Mixed: one valid, one out-of-top, one with nil position
      snapshot_fixture(past, %{
        snapshot_at: DateTime.add(base, -3600, :second),
        current_price_usd: Decimal.new("1.00"),
        in_top: true,
        position: 3
      })

      snapshot_fixture(past, %{
        snapshot_at: DateTime.add(base, -1800, :second),
        current_price_usd: Decimal.new("1.00"),
        in_top: false,
        position: nil
      })

      snapshot_fixture(past, %{
        snapshot_at: base,
        current_price_usd: Decimal.new("1.00"),
        in_top: true,
        position: nil
      })

      current = signal_fixture(%{symbol: symbol, in_top_since: base})

      [occurrence] = Signals.get_previous_occurrences(symbol, current.id)

      # Only position 3 should appear
      assert Map.keys(occurrence.position_durations) == [3]
      assert occurrence.best_position == 3
    end

    test "computes duration from utc_now when signal is still active", %{base: _base} do
      symbol = "HIST7"
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      entry = DateTime.add(now, -3600, :second)

      still_active =
        signal_fixture(%{
          symbol: symbol,
          in_top_since: entry,
          exit_date: nil,
          initial_price_usd: Decimal.new("1.00"),
          current_price_usd: Decimal.new("1.00")
        })

      current = signal_fixture(%{symbol: symbol, in_top_since: now})

      [occurrence] = Signals.get_previous_occurrences(symbol, current.id)

      assert occurrence.signal.id == still_active.id
      assert occurrence.exit_at == nil
      # Should be approximately 3600 seconds (give some slack for timing)
      assert_in_delta occurrence.duration_seconds, 3600, 5
    end

    test "returns empty list when no prior occurrences exist" do
      current = signal_fixture(%{symbol: "LONELY"})

      assert Signals.get_previous_occurrences("LONELY", current.id) == []
      assert Signals.count_previous_occurrences("LONELY", current.id) == 0
    end
  end
end
