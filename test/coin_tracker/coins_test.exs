defmodule CoinTracker.CoinsTest do
  use CoinTracker.DataCase

  alias CoinTracker.Coins

  test "upsert_symbol_price/1 creates a new symbol price" do
    {:ok, symbol_price} =
      Coins.upsert_symbol_price(%{
        exchange: :binance_spot,
        symbol_pair: "BTC/USDT",
        current_price: Decimal.new("1000")
      })

    assert symbol_price.exchange == :binance_spot
    assert symbol_price.symbol_pair == "BTC/USDT"
    assert symbol_price.current_price == Decimal.new("1000")
  end

  test "upsert_symbol_price/1 errors out if the exchange is invalid" do
    assert {:error, _error} =
             Coins.upsert_symbol_price(%{
               exchange: :fake_exchange,
               symbol_pair: "BTC/USDT",
               current_price: Decimal.new("1000")
             })
  end

  test "upsert_symbol_price/1 updates a symbol's price" do
    {:ok, original} =
      Coins.upsert_symbol_price(%{
        exchange: :binance_spot,
        symbol_pair: "BTC/USDT",
        current_price: Decimal.new("1000")
      })

    {:ok, updated} =
      Coins.upsert_symbol_price(%{
        exchange: :binance_spot,
        symbol_pair: "BTC/USDT",
        current_price: Decimal.new("10000")
      })

    assert original.id == updated.id
    assert updated.current_price == Decimal.new("10000")
  end

  test "upsert_symbol_price/1 creates two symbols if they are registered in different exchanges" do
    {:ok, first} =
      Coins.upsert_symbol_price(%{
        exchange: :binance_spot,
        symbol_pair: "BTC/USDT",
        current_price: Decimal.new("1000")
      })

    assert first.exchange == :binance_spot
    assert first.symbol_pair == "BTC/USDT"
    assert first.current_price == Decimal.new("1000")

    {:ok, second} =
      Coins.upsert_symbol_price(%{
        exchange: :bitget_spot,
        symbol_pair: "BTC/USDT",
        current_price: Decimal.new("1000")
      })

    assert second.exchange == :bitget_spot
    assert second.symbol_pair == "BTC/USDT"
    assert second.current_price == Decimal.new("1000")

    assert first.id != second.id
  end
end
