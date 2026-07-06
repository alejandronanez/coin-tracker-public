defmodule CoinTracker.Coins.TradingClient do
  @moduledoc """
  Facade that delegates trading calls to specific exchange implementations.

  Mirrors `PriceClient` for price fetching — dispatches by exchange atom
  to the correct trading module.
  """

  alias CoinTracker.Coins.Exchanges

  def fetch_balance(exchange, credential, asset, opts \\ [])

  def fetch_balance(:binance_spot, credential, asset, opts) do
    Exchanges.Binance.Trading.fetch_balance(credential, asset, opts)
  end

  def fetch_balance(exchange, _credential, _asset, _opts) do
    {:error, {:exchange_not_supported, "Balance check not supported on #{exchange}"}}
  end

  def market_buy(exchange, credential, symbol, quote_qty, opts \\ [])

  def market_buy(:binance_spot, credential, symbol, quote_qty, opts) do
    Exchanges.Binance.Trading.market_buy(credential, symbol, quote_qty, opts)
  end

  def market_buy(exchange, _credential, _symbol, _quote_qty, _opts) do
    {:error, {:exchange_not_supported, "Trading not supported on #{exchange}"}}
  end

  def place_oco_sell(exchange, credential, symbol, quantity, tp_price, sl_price, opts \\ [])

  def place_oco_sell(:binance_spot, credential, symbol, quantity, tp_price, sl_price, opts) do
    Exchanges.Binance.Trading.place_oco_sell(
      credential,
      symbol,
      quantity,
      tp_price,
      sl_price,
      opts
    )
  end

  def place_oco_sell(exchange, _credential, _symbol, _quantity, _tp_price, _sl_price, _opts) do
    {:error, {:exchange_not_supported, "Trading not supported on #{exchange}"}}
  end

  def fetch_symbol_filters(exchange, symbol, opts \\ [])

  def fetch_symbol_filters(:binance_spot, symbol, opts) do
    Exchanges.Binance.Trading.fetch_symbol_filters(symbol, opts)
  end

  def fetch_symbol_filters(exchange, _symbol, _opts) do
    {:error, {:exchange_not_supported, "Symbol filters not available for #{exchange}"}}
  end
end
