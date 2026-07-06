## ADDED Requirements

### Requirement: On-demand brief refresh via CTA

The system SHALL provide a "Refresh Analysis" button in the Insights LiveView that triggers
re-enrichment and brief regeneration for the currently viewed signal. Users can pull fresh
data after the 20-minute cooldown — coin trends rarely shift meaningfully in less time.

#### Scenario: User clicks Refresh Analysis

- **WHEN** a user clicks "Refresh Analysis" on the insights page for a signal
- **AND** no refresh has been requested for this signal in the current session within the last 20 minutes
- **THEN** the system spawns a Task that calls `Signals.refresh_enrichment/1` for that signal
- **AND** the button immediately changes to a "Refreshing..." disabled state
- **AND** when the enrichment completes, the PubSub broadcast updates the LiveView with the new brief
- **AND** the button returns to its normal "Refresh Analysis" state

#### Scenario: Throttled refresh attempt

- **WHEN** a user clicks "Refresh Analysis"
- **AND** a refresh was already requested within the last 20 minutes for this signal in the current session
- **THEN** the system shows an info flash: "Analysis was recently refreshed. Try again in X minutes."
- **AND** no API calls are made

#### Scenario: Refresh task failure

- **WHEN** a refresh Task crashes or times out (>30s)
- **THEN** the system resets the button to its normal "Refresh Analysis" state
- **AND** shows an error flash: "Refresh failed. Please try again."
- **AND** the previous brief remains unchanged

### Requirement: Admin-visible LLM cost display

The system SHALL show the LLM generation cost of the current brief to admin users in the
freshness bar of the Insights page.

#### Scenario: Admin views insights with brief

- **WHEN** an admin user views the insights page for a signal with a generated brief
- **THEN** the freshness bar displays the `llm_cost_usd` from the enrichment record
  formatted as "$X.XXXX" alongside the "Updated X minutes ago" text
- **AND** the cost is visually secondary (smaller text, muted color)

#### Scenario: Non-admin views insights

- **WHEN** a non-admin user views the insights page
- **THEN** no cost information is displayed anywhere on the page

#### Scenario: No cost data available

- **WHEN** an admin views insights for a signal whose enrichment has `llm_cost_usd` as nil
- **THEN** no cost badge is rendered (no "Cost: N/A" — just omit it)

### Requirement: Extracted enrichment function in Signals context

The system SHALL provide a public `Signals.refresh_enrichment/1` function that performs the
full enrichment flow for a single signal.

#### Scenario: Successful refresh

- **WHEN** `Signals.refresh_enrichment(signal)` is called
- **AND** the signal has a CoinGecko mapping
- **AND** CoinGecko API returns data
- **AND** brief generation succeeds
- **THEN** the system upserts the signal enrichment with fresh CoinGecko data
- **AND** generates a new brief via `BriefGenerator.generate/2`
- **AND** saves the brief and LLM usage to the enrichment record
- **AND** broadcasts `signal_enrichments:updated` via PubSub
- **AND** returns `{:ok, enrichment}`

#### Scenario: CoinGecko API failure

- **WHEN** `Signals.refresh_enrichment(signal)` is called
- **AND** CoinGecko returns an error
- **THEN** the system logs the error
- **AND** returns `{:error, :coingecko_fetch_failed}`
- **AND** does NOT modify the existing enrichment or brief

#### Scenario: No CoinGecko mapping

- **WHEN** `Signals.refresh_enrichment(signal)` is called
- **AND** the signal's symbol has no CoinGecko mapping
- **THEN** the system returns `{:error, :no_coingecko_mapping}`
- **AND** logs a debug message

#### Scenario: Brief generation failure

- **WHEN** `Signals.refresh_enrichment(signal)` is called
- **AND** CoinGecko succeeds but brief generation fails
- **THEN** the system still upserts the enrichment with fresh CoinGecko data
- **AND** logs the brief generation error
- **AND** returns `{:ok, enrichment}` (enrichment updated, brief kept from previous)
