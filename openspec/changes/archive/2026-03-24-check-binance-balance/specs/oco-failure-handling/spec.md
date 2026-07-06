## ADDED Requirements

### Requirement: OCO failure must not create a position
When the OCO sell order fails after a successful market buy, `AutoBuy.execute/5` SHALL NOT create a position in the app. It SHALL return a full error and send a Telegram alert so the user can manage the unprotected buy on the exchange manually.

#### Scenario: OCO order fails after successful market buy
- **WHEN** the market buy succeeds but the OCO sell order fails
- **THEN** the system does not create a position in the app
- **THEN** the system returns `{:error, {:oco_failed, %{buy_order: buy_result, reason: oco_reason}}}` with the buy details so the caller knows what happened
- **THEN** the system sends a Telegram alert to the user with the buy details and instructions to place a stop-loss manually

#### Scenario: UI displays OCO failure as a full error
- **WHEN** the trade UI receives an `{:error, {:oco_failed, details}}` result
- **THEN** the error step is shown (not the partial failure step)
- **THEN** the error message clearly states the buy succeeded but the OCO failed, and the user must manage the position on the exchange

#### Scenario: No partial success return type
- **WHEN** `AutoBuy.execute/5` completes
- **THEN** the return type is either `{:ok, result}` (full success) or `{:error, reason}` (any failure) — the `{:partial, ...}` return type is removed
