## MODIFIED Requirements

### Requirement: Generation Trigger

Briefs are generated after enrichment data is fetched/updated. The generation trigger changes
from push (event-driven + polling) to pull (event-driven + on-demand):

- **Event-driven** (unchanged): New signal appears without enrichment → enrich + generate brief
  immediately via `Signals.refresh_enrichment/1`. One API call per signal.
- **On-demand** (new): User clicks "Refresh Analysis" → re-fetch CoinGecko + regenerate brief
  for that specific signal via `Signals.refresh_enrichment/1`. Same function, different trigger.
- **Polling** (removed): The 30-minute automatic refresh cycle is deleted entirely. No background
  brief regeneration occurs.

Both remaining paths produce identical briefs — same prompt, same model, same output format.

#### Scenario: Event-driven brief generation (unchanged)
- **WHEN** a new signal appears without a signal enrichment record
- **AND** the `:signal_insights` feature flag is enabled
- **THEN** the EnrichmentPoller calls `Signals.refresh_enrichment/1` for that signal
- **AND** the brief is stored in `signal_enrichments.brief_en`
- **AND** PubSub broadcasts `signal_enrichments:updated`

#### Scenario: On-demand brief generation (new)
- **WHEN** a user clicks "Refresh Analysis" on the insights page
- **THEN** the LiveView spawns a Task calling `Signals.refresh_enrichment/1` for that signal
- **AND** the brief is stored in `signal_enrichments.brief_en`
- **AND** PubSub broadcasts `signal_enrichments:updated`
- **AND** the LiveView receives the broadcast and updates the displayed brief

#### Scenario: No automatic refresh (polling removed)
- **WHEN** the system is running
- **THEN** no periodic timer fires to regenerate existing briefs
- **AND** existing briefs remain until a user requests a refresh or a new event-driven
  enrichment occurs

### Requirement: EnrichmentPoller simplified to event-driven only

The EnrichmentPoller GenServer SHALL only handle event-driven enrichment. All polling-related
code, config, and state are removed.

#### Scenario: Poller receives signal update
- **WHEN** the `"signals:updated"` PubSub broadcast arrives
- **AND** there are active signals without enrichment
- **THEN** the poller calls `Signals.refresh_enrichment/1` for each unenriched signal
- **AND** broadcasts `signal_enrichments:updated` after all are processed

#### Scenario: Poller has no polling timer
- **WHEN** the EnrichmentPoller starts
- **THEN** it subscribes to `"signals:updated"` PubSub topic
- **AND** it does NOT schedule any periodic `:enrich_all` messages
- **AND** it does NOT maintain an `:interval` in its state
