defmodule CoinTracker.Coins.PriceClient do
  @moduledoc """
  Fetches current cryptocurrency prices from exchange APIs.

  This module acts as a facade that delegates to specific exchange implementations.
  """

  alias CoinTracker.Coins.Exchanges

  @type price_data :: %{symbol: String.t(), price: Decimal.t()}

  @doc """
  Fetches current prices for the given symbols from the specified exchange.

  ## Parameters
    - exchange: The exchange to fetch from (e.g., :binance_spot)
    - symbols: List of cryptocurrency symbols (e.g., ["BTC", "ETH"])
    - opts: Keyword list of options (e.g., [http_client: HTTPClientMock])

  ## Returns
    - `{:ok, [price_data()]}` on success
    - `{:error, term()}` on failure
  """
  @spec fetch_current_prices(atom(), [String.t()], keyword()) ::
          {:ok, [price_data()]} | {:error, term()}
  def fetch_current_prices(exchange, symbols, opts \\ [])

  def fetch_current_prices(:binance_spot, symbols, opts) do
    Exchanges.Binance.fetch_prices(symbols, opts)
  end

  def fetch_current_prices(:bitget_spot, symbols, opts) do
    Exchanges.Bitget.fetch_prices(symbols, opts)
  end

  def fetch_current_prices(:mexc_spot, symbols, opts) do
    Exchanges.Mexc.fetch_prices(symbols, opts)
  end
end
