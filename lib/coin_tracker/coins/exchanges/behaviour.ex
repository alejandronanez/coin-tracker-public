defmodule CoinTracker.Coins.Exchanges.Behaviour do
  @moduledoc """
  Behavior defining the contract for cryptocurrency exchange integrations.

  Each exchange module must implement this behavior to fetch current prices
  for a list of cryptocurrency symbols.
  """

  @type price_data :: %{symbol: String.t(), price: Decimal.t()}

  @doc """
  Fetches current prices for the given cryptocurrency symbols.

  ## Parameters
    - symbols: List of cryptocurrency symbols (e.g., ["BTC", "ETH"])
    - opts: Optional keyword list for configuration (e.g., http_client)

  ## Returns
    - `{:ok, [price_data()]}` on success
    - `{:error, term()}` on failure
  """
  @callback fetch_prices([String.t()], keyword()) ::
              {:ok, [price_data()]} | {:error, term()}
end
