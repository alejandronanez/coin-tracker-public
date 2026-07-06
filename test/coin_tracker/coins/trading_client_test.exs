defmodule CoinTracker.Coins.TradingClientTest do
  use CoinTracker.DataCase, async: true

  alias CoinTracker.Coins.TradingClient

  describe "market_buy/5 dispatch" do
    test "unsupported exchange returns error" do
      credential = %{api_key: "k", api_secret: "s"}

      assert {:error, {:exchange_not_supported, msg}} =
               TradingClient.market_buy(:bitget_spot, credential, "BTC/USDT", 100)

      assert msg =~ "bitget_spot"
    end

    test "mexc_spot returns unsupported" do
      credential = %{api_key: "k", api_secret: "s"}

      assert {:error, {:exchange_not_supported, _}} =
               TradingClient.market_buy(:mexc_spot, credential, "BTC/USDT", 100)
    end
  end

  describe "place_oco_sell/7 dispatch" do
    test "unsupported exchange returns error" do
      credential = %{api_key: "k", api_secret: "s"}

      assert {:error, {:exchange_not_supported, msg}} =
               TradingClient.place_oco_sell(
                 :bitget_spot,
                 credential,
                 "BTC/USDT",
                 Decimal.new("1"),
                 Decimal.new("50000"),
                 Decimal.new("40000")
               )

      assert msg =~ "bitget_spot"
    end
  end
end
