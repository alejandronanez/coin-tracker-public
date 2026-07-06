## ADDED Requirements

### Requirement: TradingBehaviour defines the exchange-agnostic trading contract

The system SHALL provide a `CoinTracker.Coins.Exchanges.TradingBehaviour` module that defines callbacks
for placing orders, mirroring how `Exchanges.Behaviour` defines `fetch_prices/2` for price fetching.

#### Scenario: Behaviour defines market_buy callback
- **WHEN** an exchange trading module implements `TradingBehaviour`
- **THEN** it MUST implement `market_buy(credential, symbol, quote_qty, opts)`
- **AND** return `{:ok, buy_result}` or `{:error, {error_type, message}}`

#### Scenario: Behaviour defines place_oco_sell callback
- **WHEN** an exchange trading module implements `TradingBehaviour`
- **THEN** it MUST implement `place_oco_sell(credential, symbol, qty, tp_price, sl_price, opts)`
- **AND** return `{:ok, oco_result}` or `{:error, {error_type, message}}`

### Requirement: TradingClient facade dispatches by exchange

The system SHALL provide a `CoinTracker.Coins.TradingClient` facade that dispatches trading calls
to the correct exchange module, mirroring how `PriceClient` dispatches `fetch_current_prices/3`.

#### Scenario: Dispatch to Binance
- **WHEN** `TradingClient.market_buy(:binance_spot, credential, symbol, amount, opts)` is called
- **THEN** it delegates to `Exchanges.Binance.Trading.market_buy(credential, symbol, amount, opts)`

#### Scenario: Dispatch to unsupported exchange
- **WHEN** `TradingClient.market_buy(:bitget_spot, credential, symbol, amount, opts)` is called
- **AND** Bitget trading is not yet implemented
- **THEN** it returns `{:error, {:exchange_not_supported, "Trading not supported on bitget_spot"}}`

#### Scenario: OCO dispatch follows same pattern
- **WHEN** `TradingClient.place_oco_sell(:binance_spot, credential, symbol, qty, tp, sl, opts)` is called
- **THEN** it delegates to `Exchanges.Binance.Trading.place_oco_sell(credential, symbol, qty, tp, sl, opts)`

### Requirement: Binance authentication plugin for Req

The system SHALL provide a `Binance.AuthPlugin` module that signs Binance API requests using HMAC-SHA256.
The plugin works as a Req request step.

#### Scenario: Signing a request
- **WHEN** the auth plugin processes an outgoing request
- **THEN** it adds a `timestamp` parameter (current UTC time in milliseconds)
- **AND** computes an HMAC-SHA256 signature of all query parameters using the API secret
- **AND** appends the `signature` parameter to the query string
- **AND** sets the `X-MBX-APIKEY` header to the API key

#### Scenario: Timestamp accuracy
- **WHEN** the auth plugin generates a timestamp
- **THEN** the timestamp is within 1000ms of the current server time
- **AND** Binance accepts the request without a timestamp error

### Requirement: Market buy order

The system SHALL place market buy orders on Binance via `Binance.Trading.market_buy/4`, implementing
the `TradingBehaviour` callback.

#### Scenario: Successful market buy
- **WHEN** `market_buy(credential, "PEPE/USDT", 100.0, opts)` is called
- **AND** the Binance API returns a filled order
- **THEN** it returns `{:ok, %{order_id: id, symbol: symbol, fill_price: avg_price, filled_qty: qty, quote_qty: spent}}`
- **AND** `fill_price` is the weighted average fill price across all fills
- **AND** `filled_qty` is the total base asset quantity received

#### Scenario: Insufficient balance
- **WHEN** a market buy is attempted
- **AND** the user's Binance USDT balance is less than the requested amount
- **THEN** it returns `{:error, {:insufficient_balance, message}}`

#### Scenario: Invalid symbol
- **WHEN** a market buy is attempted with a symbol not listed on Binance
- **THEN** it returns `{:error, {:invalid_symbol, message}}`

#### Scenario: API authentication failure
- **WHEN** a market buy is attempted with invalid or expired credentials
- **THEN** it returns `{:error, {:auth_error, message}}`

#### Scenario: Network or unknown error
- **WHEN** a market buy fails due to network issues or an unexpected Binance error
- **THEN** it returns `{:error, {:api_error, reason}}`

### Requirement: OCO sell order

The system SHALL place OCO (One-Cancels-Other) sell orders on Binance via `Binance.Trading.place_oco_sell/6`,
implementing the `TradingBehaviour` callback.

#### Scenario: Successful OCO placement
- **WHEN** `place_oco_sell(credential, "PEPE/USDT", qty, tp_price, sl_price, opts)` is called
- **AND** the prices satisfy Binance's OCO rules (TP above market, SL below market)
- **THEN** it returns `{:ok, %{order_list_id: id, tp_order_id: tp_id, sl_order_id: sl_id}}`
- **AND** the OCO order is active on Binance managing the exit automatically

#### Scenario: Price rule violation
- **WHEN** an OCO sell is attempted
- **AND** the take-profit price is not above the current market price
- **OR** the stop-loss price is not below the current market price
- **THEN** it returns `{:error, {:price_rule_violation, message}}`

#### Scenario: Quantity below minimum
- **WHEN** an OCO sell is attempted with a quantity below the symbol's minimum lot size
- **THEN** it returns `{:error, {:min_lot_size, message}}`

#### Scenario: Symbol normalization
- **WHEN** any trading function receives a symbol in the app's format (e.g., "PEPE/USDT")
- **THEN** it normalizes to Binance's format (e.g., "PEPEUSDT") before making the API call

### Requirement: Stop-loss slippage buffer

The OCO sell order SHALL include a small slippage buffer on the stop-limit price to improve fill probability.

#### Scenario: Stop-limit price calculation
- **WHEN** an OCO sell order is placed with stop price $0.00000987
- **THEN** the `stopLimitPrice` is set to `stop_price × 0.995` (0.5% below stop)
- **AND** `stopLimitTimeInForce` is set to `GTC` (Good Till Cancelled)

### Requirement: Testable via dependency injection

All trading functions SHALL accept an `opts` keyword list that allows injecting a mock HTTP client,
following the same pattern as the existing `Exchanges.Binance.fetch_prices/2`.

#### Scenario: Test with mock client
- **WHEN** `market_buy(credential, symbol, amount, http_client: MockClient)` is called
- **THEN** the mock client receives the signed request
- **AND** no real Binance API call is made
