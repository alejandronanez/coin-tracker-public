## ADDED Requirements

### Requirement: Trade page at /signals/:id/trade

The system SHALL provide a LiveView page at `/signals/:id/trade` for placing quick trades on signals.
The page is only accessible when the `:automatic_buying` feature flag is enabled for the user.

#### Scenario: Accessing the trade page
- **WHEN** a user navigates to `/signals/:id/trade`
- **AND** the `:automatic_buying` feature flag is enabled for the user
- **AND** the signal exists
- **THEN** the trade page renders with the signal's symbol and current price
- **AND** a form with Amount (USDT), Take Profit (%), and Stop Loss (%) fields

#### Scenario: Accessing without feature flag
- **WHEN** a user navigates to `/signals/:id/trade`
- **AND** the `:automatic_buying` feature flag is NOT enabled for the user
- **THEN** the user is redirected to `/signals/:id` with no error shown

#### Scenario: Accessing without credentials
- **WHEN** a user navigates to `/signals/:id/trade`
- **AND** the feature flag is enabled
- **AND** the user has no Binance credentials stored
- **THEN** the page shows a message explaining credentials are needed
- **AND** links to the credential settings page

#### Scenario: Signal not found
- **WHEN** a user navigates to `/signals/:id/trade` with an invalid signal ID
- **THEN** the user is redirected to `/signals` with an error flash

### Requirement: Form with sensible defaults

The trade form SHALL pre-fill take-profit and stop-loss with defaults to minimize friction.

#### Scenario: Default form values
- **WHEN** the trade form renders
- **THEN** the Amount (USDT) field is empty (user must decide)
- **AND** Take Profit defaults to 15%
- **AND** Stop Loss defaults to 20% (displayed as positive, stored as negative internally)

#### Scenario: Form validation
- **WHEN** the user enters values in the form
- **THEN** Amount must be a positive number
- **AND** Take Profit must be a positive percentage
- **AND** Stop Loss must be a positive percentage (converted to negative internally)
- **AND** validation errors display inline on the form fields

### Requirement: Preview step before execution

The trade form SHALL show a preview of the order before execution, including estimated quantities
and target prices with percentages.

#### Scenario: Preview displays estimated values
- **WHEN** the user clicks "Preview Order" with valid inputs
- **THEN** the preview shows:
  - Symbol and current price
  - Amount to spend (USDT)
  - Estimated quantity of coins to receive
  - Take-profit target price with percentage (e.g., "$0.00001419 (+15%)")
  - Stop-loss target price with percentage (e.g., "$0.00000987 (-20%)")
  - Estimated profit in USDT (e.g., "+$15.00")
  - Estimated loss in USDT (e.g., "-$20.00")

#### Scenario: Preview shows sync warning
- **WHEN** the preview is displayed
- **THEN** a warning is shown explaining:
  - This places a real order on Binance
  - The OCO manages the exit automatically on the exchange
  - The position in the app must be closed manually when the OCO fills

#### Scenario: User can go back to edit
- **WHEN** the preview is displayed
- **AND** the user clicks "Edit"
- **THEN** the form returns to the editable state with previously entered values preserved

### Requirement: Execution with progress feedback

The trade execution SHALL show step-by-step progress to the user.

#### Scenario: Execution progress
- **WHEN** the user clicks "Confirm & Buy"
- **THEN** the page shows executing state with progress indicators:
  - Step 1: "Placing market buy..." → checkmark when done
  - Step 2: "Placing OCO sell order..." → checkmark when done
  - Step 3: "Creating position..." → checkmark when done

#### Scenario: Successful execution
- **WHEN** all three steps complete successfully
- **THEN** the user is redirected to `/positions`
- **AND** a flash message confirms: "Bought [symbol]. OCO order placed on Binance."

#### Scenario: Partial failure display
- **WHEN** the buy succeeds but OCO fails
- **THEN** the page shows an error state with:
  - Checkmark on market buy (with fill details)
  - Error on OCO placement (with reason)
  - Message: "Your position was created but has no stop-loss on Binance."
  - "Go to Positions" button
  - "Retry OCO" button

#### Scenario: Buy failure display
- **WHEN** the market buy fails
- **THEN** the page shows an error state with the failure reason
  - "Go back" button to return to the form

### Requirement: Execution happens in a supervised task

The trade execution SHALL run in a `Task.Supervisor`-supervised task to avoid blocking the
LiveView process.

#### Scenario: Non-blocking execution
- **WHEN** the user confirms a trade
- **THEN** the execution runs in a supervised task
- **AND** the LiveView remains responsive (showing progress)
- **AND** results are sent back via `send(self(), {:trade_result, result})`

#### Scenario: Task crash recovery
- **WHEN** the execution task crashes unexpectedly
- **THEN** the LiveView receives a DOWN message
- **AND** displays an error: "Something went wrong. Check your Binance account."

### Requirement: Live price updates during form entry

The trade page SHALL display the signal's live price, updating in real-time via PubSub.

#### Scenario: Price updates while on form
- **WHEN** the user is filling out the trade form
- **AND** a new price arrives via the `"price_updates"` PubSub topic
- **THEN** the displayed current price updates
- **AND** the estimated quantity in the preview (if visible) recalculates
