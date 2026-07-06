defmodule CoinTracker.Coins.Exchanges.MexcTest do
  use ExUnit.Case, async: true

  import Mox

  alias CoinTracker.Coins.Exchanges.Mexc
  alias CoinTracker.Coins.HTTPClientMock

  setup :verify_on_exit!

  describe "fetch_prices/2" do
    test "successfully fetches and parses a single price from MEXC API" do
      symbols = ["ETH/USDT"]

      expect(HTTPClientMock, :get, fn url, opts ->
        assert url == "https://api.mexc.com/api/v3/ticker/price"
        assert opts[:params][:symbol] == "ETHUSDT"

        {:ok,
         %{
           status: 200,
           body: %{
             "symbol" => "ETHUSDT",
             "price" => "2999.85"
           }
         }}
      end)

      assert {:ok, prices} = Mexc.fetch_prices(symbols, http_client: HTTPClientMock)

      assert length(prices) == 1
      assert hd(prices) == %{symbol: "ETH/USDT", price: Decimal.new("2999.85")}
    end

    test "successfully fetches multiple symbols in parallel" do
      symbols = ["BTC/USDT", "ETH/USDT"]

      expect(HTTPClientMock, :get, 2, fn url, opts ->
        assert url == "https://api.mexc.com/api/v3/ticker/price"
        symbol = opts[:params][:symbol]

        response =
          case symbol do
            "BTCUSDT" ->
              %{"symbol" => "BTCUSDT", "price" => "50000.00"}

            "ETHUSDT" ->
              %{"symbol" => "ETHUSDT", "price" => "3000.50"}
          end

        {:ok, %{status: 200, body: response}}
      end)

      assert {:ok, prices} = Mexc.fetch_prices(symbols, http_client: HTTPClientMock)

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
             "code" => 30014,
             "msg" => "invalid symbol"
           }
         }}
      end)

      assert Mexc.fetch_prices(symbols, http_client: HTTPClientMock) ==
               {:error, {:api_error, "invalid symbol"}}
    end

    test "handles network errors gracefully" do
      symbols = ["BTC/USDT"]

      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert Mexc.fetch_prices(symbols, http_client: HTTPClientMock) ==
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

      assert Mexc.fetch_prices(symbols, http_client: HTTPClientMock) ==
               {:error, {:api_error, "Internal server error"}}
    end
  end
end
