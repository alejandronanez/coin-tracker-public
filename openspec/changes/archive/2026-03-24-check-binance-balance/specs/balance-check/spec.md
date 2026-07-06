## ADDED Requirements

### Requirement: Fetch account balance from exchange
The system SHALL provide a `fetch_balance/3` function in `TradingClient` that retrieves the free (available) balance for a given quote asset from the user's exchange account.

#### Scenario: Successful USDT balance fetch
- **WHEN** `fetch_balance(:binance_spot, credential, "USDT")` is called with valid credentials
- **THEN** the system returns `{:ok, %{free: Decimal.t(), asset: "USDT"}}` with the available balance

#### Scenario: Asset not found in account
- **WHEN** `fetch_balance(:binance_spot, credential, "NONEXISTENT")` is called
- **THEN** the system returns `{:ok, %{free: Decimal.new("0"), asset: "NONEXISTENT"}}`

#### Scenario: Invalid credentials
- **WHEN** `fetch_balance(:binance_spot, credential, "USDT")` is called with invalid API keys
- **THEN** the system returns `{:error, {:auth_error, message}}`

#### Scenario: Network failure
- **WHEN** the Binance API is unreachable
- **THEN** the system returns `{:error, :network_error}`

#### Scenario: Unsupported exchange
- **WHEN** `fetch_balance(:unsupported_exchange, credential, "USDT")` is called
- **THEN** the system returns `{:error, {:exchange_not_supported, message}}`

### Requirement: Cap order amount to available balance
The `AutoBuy.execute/5` function SHALL check the user's available USDT balance before placing a market buy order and cap the order amount to `available_balance * 0.99` if the requested amount exceeds it.

#### Scenario: Requested amount within available balance
- **WHEN** the user requests to buy $100 USDT and the available balance is $500 USDT
- **THEN** the system places the market buy for $100 USDT (no capping)

#### Scenario: Requested amount exceeds available balance
- **WHEN** the user requests to buy $500 USDT and the available balance is $200 USDT
- **THEN** the system caps the buy amount to `$200 * 0.99 = $198 USDT` and places the order with the capped amount

#### Scenario: Available balance too low for any order
- **WHEN** the user requests to buy any amount and the available balance after applying the 1% margin is below the minimum order threshold
- **THEN** the system returns `{:error, {:insufficient_balance, message}}` without placing any order

#### Scenario: Balance fetch fails
- **WHEN** the balance check fails due to a network or auth error
- **THEN** the system propagates the error and does not attempt to place the order

### Requirement: Display available balance in trade UI
The trade form SHALL display the user's available USDT balance so they can see their spending limit before entering an amount.

#### Scenario: Balance loads successfully
- **WHEN** a user with valid Binance credentials opens the trade page
- **THEN** the available USDT balance is displayed near the amount input field after the page connects

#### Scenario: Balance loading state
- **WHEN** the trade page is loading the balance
- **THEN** a loading indicator is shown in place of the balance value

#### Scenario: Balance fetch fails in UI
- **WHEN** the balance fetch fails (network error, auth error)
- **THEN** the form remains usable and a subtle warning indicates the balance could not be loaded

#### Scenario: No exchange credentials
- **WHEN** a user without Binance credentials opens the trade page
- **THEN** no balance fetch is attempted and the credentials-required warning is shown (existing behavior)
