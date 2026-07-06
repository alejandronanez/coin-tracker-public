defmodule CoinTracker.Coins.Exchanges.TradingBehaviour do
  @moduledoc """
  Behavior defining the contract for cryptocurrency exchange trading integrations.

  Each exchange trading module must implement this behavior to place buy orders
  and OCO sell orders. Mirrors `Exchanges.Behaviour` for price fetching.
  """

  @type credential :: %{api_key: String.t(), api_secret: String.t()}

  @type buy_result :: %{
          order_id: integer() | String.t(),
          symbol: String.t(),
          fill_price: Decimal.t(),
          filled_qty: Decimal.t(),
          quote_qty: Decimal.t()
        }

  @type oco_result :: %{
          order_list_id: integer() | String.t(),
          tp_order_id: integer() | String.t(),
          sl_order_id: integer() | String.t()
        }

  @type error_reason ::
          {:insufficient_balance, String.t()}
          | {:invalid_symbol, String.t()}
          | {:auth_error, String.t()}
          | {:price_rule_violation, String.t()}
          | {:filter_failure, String.t()}
          | {:api_error, term()}
          | :network_error

  @type balance_result :: %{
          free: Decimal.t(),
          asset: String.t()
        }

  @doc """
  Fetches the available (free) balance for a given asset from the user's exchange account.

  ## Parameters
    - credential: Map with `:api_key` and `:api_secret`
    - asset: The asset to check balance for (e.g., "USDT")
    - opts: Keyword list of options (e.g., [http_client: MockClient])
  """
  @callback fetch_balance(credential(), String.t(), keyword()) ::
              {:ok, balance_result()} | {:error, error_reason()}

  @doc """
  Places a market buy order for the given symbol using the quote asset (USDT).

  ## Parameters
    - credential: Map with `:api_key` and `:api_secret`
    - symbol: Trading pair (e.g., "PEPE/USDT")
    - quote_qty: Amount of USDT to spend
    - opts: Keyword list of options (e.g., [http_client: MockClient])
  """
  @callback market_buy(credential(), String.t(), number() | Decimal.t(), keyword()) ::
              {:ok, buy_result()} | {:error, error_reason()}

  @doc """
  Places an OCO sell order with take-profit and stop-loss prices.

  ## Parameters
    - credential: Map with `:api_key` and `:api_secret`
    - symbol: Trading pair (e.g., "PEPE/USDT")
    - quantity: Amount of base asset to sell
    - tp_price: Take-profit limit price
    - sl_price: Stop-loss trigger price
    - opts: Keyword list of options (e.g., [http_client: MockClient])
  """
  @callback place_oco_sell(
              credential(),
              String.t(),
              number() | Decimal.t(),
              number() | Decimal.t(),
              number() | Decimal.t(),
              keyword()
            ) :: {:ok, oco_result()} | {:error, error_reason()}
end
