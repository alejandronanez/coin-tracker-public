## ADDED Requirements

### Requirement: Three-step trade execution

The system SHALL provide `Trading.AutoBuy.execute/4` that orchestrates buying a coin and placing an OCO
order in a single operation. `AutoBuy` is exchange-agnostic — it calls `TradingClient` (the facade),
never a specific exchange module directly. The exchange is determined by the signal's `symbol_price.exchange`.

#### Scenario: Full success — buy and OCO both succeed
- **WHEN** `execute(user, signal, amount_usdt, %{take_profit: 15.0, stop_loss: 20.0})` is called
- **AND** the user has valid credentials for the signal's exchange
- **AND** the market buy fills successfully
- **AND** the OCO sell order is placed successfully
- **THEN** it returns `{:ok, %{position: position, buy_order: buy, oco_order: oco}}`
- **AND** a position is created with `source: "auto_buy"`
- **AND** the position's `entry_price` is the actual fill price (not the preview estimate)
- **AND** the position's `amount_invested` is the actual USDT spent
- **AND** the credential's `last_used_at` is updated

#### Scenario: Partial success — buy succeeds, OCO fails
- **WHEN** the market buy fills successfully
- **AND** the OCO sell order fails (price rule violation, API error, etc.)
- **THEN** it returns `{:partial, %{position: position, buy_order: buy, oco_error: reason}}`
- **AND** a position is still created with `source: "auto_buy"` (so it's tracked)
- **AND** an urgent Telegram alert is sent to the user with:
  - The symbol and quantity purchased
  - The fill price
  - The error reason
  - Instructions to place a stop-loss manually on Binance

#### Scenario: Buy fails — nothing happens
- **WHEN** the market buy fails (insufficient balance, invalid symbol, auth error)
- **THEN** it returns `{:error, reason}`
- **AND** no position is created
- **AND** no OCO order is attempted
- **AND** no Telegram alert is sent

#### Scenario: No credentials found
- **WHEN** `execute/4` is called
- **AND** the user has no credential stored for the signal's exchange
- **THEN** it returns `{:error, :no_credentials}`

#### Scenario: Unsupported exchange
- **WHEN** `execute/4` is called
- **AND** the signal's exchange does not have a trading adapter implemented
- **THEN** it returns `{:error, {:exchange_not_supported, exchange_name}}`

### Requirement: OCO prices calculated from actual fill price

The OCO take-profit and stop-loss prices SHALL be calculated from the actual market buy fill price,
not from the signal's current price shown in the preview.

#### Scenario: TP and SL price calculation
- **WHEN** a market buy fills at $0.00001234
- **AND** take_profit is 15% and stop_loss is 20%
- **THEN** the OCO take-profit price is `$0.00001234 × 1.15 = $0.00001419`
- **AND** the OCO stop price is `$0.00001234 × 0.80 = $0.00000987`

### Requirement: Correct decimal precision for Binance

OCO order prices and quantities SHALL be rounded to the correct decimal precision for the given
symbol on Binance. Sending too many decimal places causes order rejection.

#### Scenario: Price and quantity precision
- **WHEN** calculating OCO prices for a symbol
- **THEN** the system uses the appropriate tick size and step size for that symbol
- **AND** prices and quantities are truncated (not rounded up) to avoid exceeding targets

### Requirement: Position auto-creation mirrors existing pattern

The auto-created position SHALL use the existing `Trading.create_position/3` path with the same
validations and side effects (PubSub broadcast, SymbolPrice upsert).

#### Scenario: Position created with signal's symbol_price
- **WHEN** the auto-buy creates a position
- **THEN** the position is linked to the same `SymbolPrice` record as the signal
- **AND** the position appears on `/positions` immediately via PubSub
- **AND** the `PricePoller` begins tracking it on the next cycle

### Requirement: Feature flag gating

All auto-buy functionality SHALL be gated behind the `:automatic_buying` feature flag.

#### Scenario: Flag disabled — execute returns error
- **WHEN** `execute/4` is called
- **AND** the `:automatic_buying` flag is not enabled for the user
- **THEN** it returns `{:error, :feature_disabled}`

#### Scenario: Flag enabled for admin
- **WHEN** an admin user calls `execute/4`
- **THEN** the feature flag check passes (admin-first behavior)
- **AND** the trade proceeds normally
