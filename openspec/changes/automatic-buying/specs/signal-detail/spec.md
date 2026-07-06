## MODIFIED Requirements

### Requirement: Trade button on signal detail page

The signal detail page (`/signals/:id`) SHALL display a "Trade this signal" button that navigates
to the trade page, gated by the `:automatic_buying` feature flag and credential availability.

#### Scenario: Button visible when feature enabled and credentials exist
- **WHEN** a user views `/signals/:id`
- **AND** the `:automatic_buying` feature flag is enabled for the user
- **AND** the user has at least one Binance credential stored
- **THEN** a "Trade this signal" button is displayed prominently
- **AND** clicking it navigates to `/signals/:id/trade`

#### Scenario: Button hidden when feature disabled
- **WHEN** a user views `/signals/:id`
- **AND** the `:automatic_buying` feature flag is NOT enabled for the user
- **THEN** no trade button is visible

#### Scenario: Setup prompt when no credentials
- **WHEN** a user views `/signals/:id`
- **AND** the `:automatic_buying` feature flag is enabled for the user
- **AND** the user has NO Binance credentials stored
- **THEN** a prompt is shown: "Set up your Binance API key to trade directly"
- **AND** it links to the credential settings page
