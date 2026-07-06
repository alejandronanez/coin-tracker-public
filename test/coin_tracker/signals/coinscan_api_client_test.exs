defmodule CoinTracker.Signals.CoinscanApiClientTest do
  use ExUnit.Case, async: true
  import Mox

  alias CoinTracker.Signals.CoinscanApiClient
  alias CoinTracker.Signals.HTTPClientMock
  import CoinTracker.ApiFixtures

  # Make sure mocks are verified
  setup :verify_on_exit!

  describe "fetch_top_10/0" do
    test "sends API key as a Bearer token in the Authorization header" do
      expect(HTTPClientMock, :get, fn _url, opts ->
        assert opts[:auth] == {:bearer, "test_api_key"}
        refute Keyword.has_key?(Keyword.get(opts, :params, []), :apikey)

        body = api_top10_response(coins: []) |> Jason.decode!()
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:ok, _signals} = CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
    end

    test "successfully fetches and transforms top 10 signals" do
      # Mock the HTTP response
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body =
          api_top10_response(
            coins: [
              %{
                symbol: "TRAC",
                name: "OriginTrail",
                initial_price_usd: 0.9843,
                max_price_usd: 1.234,
                max_increase_percentage: 25.33,
                in_top_since: "2025-10-15T12:00:00Z",
                in_top: true,
                volumen24h: 1_000_000
              },
              %{
                symbol: "ETH",
                name: "Ethereum",
                initial_price_usd: 3000.0,
                max_price_usd: 3100.0,
                max_increase_percentage: 3.33,
                in_top_since: "2025-10-14T12:00:00Z",
                in_top: true,
                volumen24h: 10_000_000
              },
              %{
                symbol: "BTC",
                name: "Bitcoin",
                initial_price_usd: 50000.0,
                max_price_usd: 51000.0,
                max_increase_percentage: 2.0,
                in_top_since: "2025-10-13T12:00:00Z",
                in_top: true,
                volumen24h: 100_000_000
              }
            ]
          )
          |> Jason.decode!()

        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:ok, signals} = CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)

      # Verify we got the right number of signals
      assert length(signals) == 3

      # Check first signal structure and values
      [first | _] = signals
      assert first.symbol == "TRAC"
      assert first.name == "OriginTrail"
      assert first.in_top == true
      assert first.active == true
      assert Decimal.equal?(first.initial_price_usd, Decimal.from_float(0.9843))
      assert Decimal.equal?(first.max_price_usd, Decimal.from_float(1.234))
      assert Decimal.equal?(first.max_increase_percentage, Decimal.from_float(25.33))
      assert first.in_top_since == ~U[2025-10-15 12:00:00Z]
    end

    test "handles integer volumes correctly" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body =
          api_top10_response(
            coins: [
              %{
                symbol: "BTC",
                name: "Bitcoin",
                volumen24h: 1_000_000,
                initial_price_usd: 50000.0,
                max_price_usd: 51000.0,
                in_top: true,
                in_top_since: iso_timestamp(60)
              }
            ]
          )
          |> Jason.decode!()

        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:ok, [signal]} = CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
      assert Decimal.equal?(signal.initial_volume_24h, Decimal.new("1000000"))
    end

    test "handles zero values correctly" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body =
          api_top10_response(
            coins: [
              %{
                symbol: "ZERO",
                name: "ZeroCoin",
                volumen24h: 0,
                initial_price_usd: 0,
                max_price_usd: 0,
                max_increase_percentage: 0,
                in_top: true,
                in_top_since: iso_timestamp(60)
              }
            ]
          )
          |> Jason.decode!()

        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:ok, [signal]} = CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
      assert Decimal.equal?(signal.initial_volume_24h, Decimal.new("0"))
      assert Decimal.equal?(signal.initial_price_usd, Decimal.new("0"))
    end

    test "captures initial volume for all signals regardless of age" do
      fresh_timestamp = iso_timestamp(60)
      stale_timestamp = iso_timestamp(600)

      expect(HTTPClientMock, :get, fn _url, _opts ->
        body =
          api_top10_response(
            coins: [
              %{
                symbol: "FRESH",
                name: "FreshCoin",
                volumen24h: 1_500_000,
                in_top: true,
                in_top_since: fresh_timestamp
              },
              %{
                symbol: "STALE",
                name: "StaleCoin",
                volumen24h: 2_500_000,
                in_top: true,
                in_top_since: stale_timestamp
              }
            ]
          )
          |> Jason.decode!()

        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:ok, [fresh, stale]} =
               CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)

      # Both fresh and stale signals should capture their initial volume
      assert Decimal.equal?(fresh.initial_volume_24h, Decimal.new("1500000"))
      assert Decimal.equal?(fresh.current_volume_24h, Decimal.new("1500000"))

      assert Decimal.equal?(stale.initial_volume_24h, Decimal.new("2500000"))
      assert Decimal.equal?(stale.current_volume_24h, Decimal.new("2500000"))
    end

    test "leaves volume nil when the API returns nil for volumen24h" do
      # `nil` must propagate to the upsert so COALESCE can preserve any existing
      # current_volume_24h instead of clobbering it with 0.
      fresh_timestamp = iso_timestamp(60)

      expect(HTTPClientMock, :get, fn _url, _opts ->
        body =
          api_top10_response(
            coins: [
              %{
                symbol: "NOVOLUME",
                name: "NoVolumeCoin",
                volumen24h: nil,
                in_top: true,
                in_top_since: fresh_timestamp
              }
            ]
          )
          |> Jason.decode!()

        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:ok, [signal]} = CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)

      assert is_nil(signal.initial_volume_24h)
      assert is_nil(signal.current_volume_24h)
    end

    test "returns empty list when API returns no data" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body = api_top10_response(coins: []) |> Jason.decode!()
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:ok, []} = CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
    end
  end

  describe "fetch_grace_period/0" do
    test "successfully fetches and transforms grace period signals" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body =
          api_grace_period_response(
            coins: [
              %{
                symbol: "SNX",
                name: "Synthetix Network Token",
                initial_price_usd: 2.5,
                max_price_usd: 3.0,
                max_increase_percentage: 20.0,
                in_top_since: "2025-10-12T16:10:03Z",
                exit_date: "2025-10-18T02:40:02Z",
                in_top: false,
                volumen24h: 500_000
              },
              %{
                symbol: "LINK",
                name: "Chainlink",
                initial_price_usd: 15.0,
                max_price_usd: 18.0,
                max_increase_percentage: 20.0,
                in_top_since: "2025-10-10T10:00:00Z",
                exit_date: "2025-10-17T10:00:00Z",
                in_top: false,
                volumen24h: 2_000_000
              }
            ]
          )
          |> Jason.decode!()

        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:ok, signals} = CoinscanApiClient.fetch_grace_period(http_client: HTTPClientMock)

      # Verify we got the right number of signals
      assert length(signals) == 2

      # Check first signal (SNX)
      [snx | _] = signals
      assert snx.symbol == "SNX"
      assert snx.name == "Synthetix Network Token"
      assert snx.in_top == false
      assert snx.active == true
      assert snx.in_top_since == ~U[2025-10-12 16:10:03Z]
      assert snx.exit_date == ~U[2025-10-18 02:40:02Z]
    end

    test "sets active=true for grace period coins" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body = api_grace_period_response() |> Jason.decode!()
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:ok, signals} = CoinscanApiClient.fetch_grace_period(http_client: HTTPClientMock)

      # All grace period signals should have active=true
      assert Enum.all?(signals, &(&1.active == true))
    end
  end

  describe "HTTP error handling" do
    test "handles 401 Unauthorized - invalid API key" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body = %{
          "status" => "error",
          "message" => "La clave de API es inválida o no fue proporcionada"
        }

        {:ok, %Req.Response{status: 401, body: body}}
      end)

      assert {:error, {:http_error, 401, body}} =
               CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)

      assert body["message"] == "La clave de API es inválida o no fue proporcionada"
    end

    test "handles 404 Not Found - endpoint doesn't exist" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body = %{
          "status" => "error",
          "message" => "Endpoint no encontrado"
        }

        {:ok, %Req.Response{status: 404, body: body}}
      end)

      assert {:error, {:http_error, 404, _}} =
               CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
    end

    test "handles 429 Too Many Requests - rate limit exceeded" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body = %{
          "status" => "error",
          "message" => "Demasiadas solicitudes. Por favor, inténtalo de nuevo más tarde."
        }

        {:ok, %Req.Response{status: 429, body: body}}
      end)

      assert {:error, {:http_error, 429, body}} =
               CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)

      assert body["message"] =~ "Demasiadas solicitudes"
    end

    test "handles 500 Internal Server Error" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body = %{
          "status" => "error",
          "message" => "Error interno del servidor"
        }

        {:ok, %Req.Response{status: 500, body: body}}
      end)

      assert {:error, {:http_error, 500, body}} =
               CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)

      assert body["message"] == "Error interno del servidor"
    end
  end

  describe "network error handling" do
    test "handles connection errors" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:error, %Mint.TransportError{reason: :econnrefused}}
      end)

      assert {:error, :network_error} =
               CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
    end
  end

  describe "invalid response handling" do
    test "handles missing status field" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body = %{"data" => %{"top_criptomonedas" => []}}
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:error, :parse_error} =
               CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
    end

    test "handles non-success status" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body = %{"status" => "error", "message" => "Something went wrong"}
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:error, :parse_error} =
               CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
    end

    test "handles missing data wrapper" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body = %{"status" => "success"}
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:error, :parse_error} =
               CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
    end

    test "handles missing nested data key" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body = %{"status" => "success", "data" => %{}}
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:error, :parse_error} =
               CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
    end

    test "handles invalid JSON" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        # Return a string that looks like it should be JSON but isn't properly parsed
        body = "not valid json"
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:error, :parse_error} =
               CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
    end
  end

  describe "edge cases" do
    test "handles missing optional fields gracefully" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body =
          api_top10_response(
            coins: [
              %{
                symbol: "MIN",
                name: "MinimalCoin",
                # No other fields provided
                in_top: true
              }
            ]
          )
          |> Jason.decode!()

        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:ok, [signal]} = CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
      assert signal.symbol == "MIN"
      assert signal.name == "MinimalCoin"
      assert is_nil(signal.initial_price_usd)
      assert is_nil(signal.max_price_usd)
      assert is_nil(signal.max_increase_percentage)
      assert is_nil(signal.in_top_since)
    end

    test "handles float decimals correctly" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body =
          api_top10_response(
            coins: [
              %{
                symbol: "FLOAT",
                name: "FloatCoin",
                initial_price_usd: 0.123456789,
                max_price_usd: 999.87654321,
                max_increase_percentage: 12.34567,
                volumen24h: 1234.5678,
                in_top: true,
                in_top_since: iso_timestamp(60)
              }
            ]
          )
          |> Jason.decode!()

        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:ok, [signal]} = CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
      assert Decimal.equal?(signal.initial_price_usd, Decimal.from_float(0.123456789))
      assert Decimal.equal?(signal.max_price_usd, Decimal.from_float(999.87654321))
      assert Decimal.equal?(signal.max_increase_percentage, Decimal.from_float(12.34567))
      assert Decimal.equal?(signal.initial_volume_24h, Decimal.from_float(1234.5678))
    end

    test "handles invalid datetime gracefully" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        body =
          api_top10_response(
            coins: [
              %{
                symbol: "BADTIME",
                name: "BadTimeCoin",
                in_top_since: "not-a-date",
                exit_date: "invalid",
                in_top: false
              }
            ]
          )
          |> Jason.decode!()

        {:ok, %Req.Response{status: 200, body: body}}
      end)

      assert {:ok, [signal]} = CoinscanApiClient.fetch_top_10(http_client: HTTPClientMock)
      assert signal.symbol == "BADTIME"
      assert is_nil(signal.in_top_since)
      assert is_nil(signal.exit_date)
    end
  end

  defp iso_timestamp(seconds_ago) when is_integer(seconds_ago) do
    DateTime.utc_now()
    |> DateTime.add(-seconds_ago, :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
