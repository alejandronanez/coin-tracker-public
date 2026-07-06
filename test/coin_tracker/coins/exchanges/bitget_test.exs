defmodule CoinTracker.Coins.Exchanges.BitgetTest do
  use ExUnit.Case, async: true

  import Mox

  alias CoinTracker.Coins.Exchanges.Bitget
  alias CoinTracker.Coins.HTTPClientMock

  setup :verify_on_exit!

  describe "fetch_prices/2" do
    test "successfully fetches and parses a single price from Bitget API" do
      symbols = ["ETH/USDT"]

      expect(HTTPClientMock, :get, fn url, opts ->
        assert url == "https://api.bitget.com/api/v2/spot/market/tickers"
        assert opts[:params][:symbol] == "ETHUSDT"

        {:ok,
         %{
           status: 200,
           body: %{
             "code" => "00000",
             "msg" => "success",
             "data" => [
               %{
                 "symbol" => "ETHUSDT",
                 "lastPr" => "2999.85"
               }
             ]
           }
         }}
      end)

      assert {:ok, prices} = Bitget.fetch_prices(symbols, http_client: HTTPClientMock)

      assert length(prices) == 1
      assert hd(prices) == %{symbol: "ETH/USDT", price: Decimal.new("2999.85")}
    end

    test "successfully fetches multiple symbols in parallel" do
      symbols = ["BTC/USDT", "ETH/USDT"]

      expect(HTTPClientMock, :get, 2, fn url, opts ->
        assert url == "https://api.bitget.com/api/v2/spot/market/tickers"
        symbol = opts[:params][:symbol]

        response =
          case symbol do
            "BTCUSDT" ->
              %{
                "code" => "00000",
                "msg" => "success",
                "data" => [%{"symbol" => "BTCUSDT", "lastPr" => "50000.00"}]
              }

            "ETHUSDT" ->
              %{
                "code" => "00000",
                "msg" => "success",
                "data" => [%{"symbol" => "ETHUSDT", "lastPr" => "3000.50"}]
              }
          end

        {:ok, %{status: 200, body: response}}
      end)

      assert {:ok, prices} = Bitget.fetch_prices(symbols, http_client: HTTPClientMock)

      assert length(prices) == 2

      assert Enum.find(prices, &(&1.symbol == "BTC/USDT")) == %{
               symbol: "BTC/USDT",
               price: Decimal.new("50000.00")
             }

      assert Enum.find(prices, &(&1.symbol == "ETH/USDT")) == %{
               symbol: "ETH/USDT",
               price: Decimal.new("3000.50")
             }
    end

    test "handles API errors gracefully" do
      symbols = ["INVALID/USDT"]

      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             "code" => "40012",
             "msg" => "Invalid symbol"
           }
         }}
      end)

      assert Bitget.fetch_prices(symbols, http_client: HTTPClientMock) ==
               {:error, {:api_error, "Invalid symbol"}}
    end

    test "handles network errors gracefully" do
      symbols = ["BTC/USDT"]

      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert Bitget.fetch_prices(symbols, http_client: HTTPClientMock) ==
               {:error, :network_error}
    end

    test "handles HTTP errors gracefully" do
      symbols = ["BTC/USDT"]

      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 500,
           body: %{"msg" => "Internal server error"}
         }}
      end)

      assert Bitget.fetch_prices(symbols, http_client: HTTPClientMock) ==
               {:error, {:api_error, "Internal server error"}}
    end
  end
end
