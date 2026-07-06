defmodule CoinTracker.Coins.Exchanges.BinanceTest do
  use ExUnit.Case, async: true

  import Mox

  alias CoinTracker.Coins.Exchanges.Binance
  alias CoinTracker.Coins.HTTPClientMock

  # Ensure mocks are verified after each test
  setup :verify_on_exit!

  describe "fetch_prices/2" do
    test "successfully fetches and parses prices from Binance API" do
      symbols = ["BTC/USDT", "ETH/USDT"]

      # Mock the HTTP client to return a successful response
      expect(HTTPClientMock, :get, fn url, opts ->
        assert url == "https://api.binance.com/api/v3/ticker/price"
        assert opts[:params][:symbols] == Jason.encode!(["BTCUSDT", "ETHUSDT"])

        {:ok,
         %{
           status: 200,
           body: [
             %{"symbol" => "BTCUSDT", "price" => "50000.00"},
             %{"symbol" => "ETHUSDT", "price" => "3000.50"}
           ]
         }}
      end)

      assert {:ok, prices} = Binance.fetch_prices(symbols, http_client: HTTPClientMock)

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
      symbols = ["BTC/USDT"]

      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 400,
           body: %{"code" => -1121, "msg" => "Invalid symbol."}
         }}
      end)

      assert Binance.fetch_prices(symbols, http_client: HTTPClientMock) ==
               {:error, {:api_error, "Invalid symbol."}}
    end
  end
end
