## Why

Signal brief generation is burning 720/month by regenerating briefs every 30 minutes for signals nobody
is actively looking at. The first brief generated when a signal enters the top 10 is the one that
drives the buy/not-buy decision. Every subsequent automatic refresh is speculative spend with near zero
read rate. Switching to a pull model (generate once, refresh on demand) reduces costs to $15-25/month
while delivering a better product: briefs are only regenerated when a user actually wants fresh analysis.

## What Changes

- **Remove polling from EnrichmentPoller**: Delete `perform_full_enrichment/0` and the 30-minute timer.
  Keep event-driven `enrich_new_signals/0` unchanged — new signals still get their first brief in 45s.
- **Add on-demand refresh**: "Refresh Analysis" CTA in the Insights UI triggers re-enrichment + brief
  regeneration for that specific signal. Throttled to max once per 20 minutes per signal.
- **Extract on-demand enrichment to Signals context**: New `Signals.refresh_enrichment/1` public function
  that both the LiveView CTA and the poller's event-driven path can call.
- **Surface LLM cost to admins**: Show the `llm_cost_usd` from the enrichment record in the freshness bar
  for admin users, providing cost visibility without cluttering the UI for regular users.

## Capabilities

### New Capabilities

- `on-demand-refresh`: User-triggered brief refresh via CTA button with throttling, plus admin-visible
  cost display in the insights UI

### Modified Capabilities

- `brief-generation`: Generation trigger changes from push (event-driven + polling) to pull (event-driven on-demand).
  The brief format, prompt, and quality are unchanged.

## Impact

- **Code**: `EnrichmentPoller` simplified (remove polling), `Signals` context gets `refresh_enrichment/1`,
  `SignalLive.Insights` gets `handle_event` + UI changes
- **Cost**: ~97% reduction (from ~$720/month to ~$15-25/month)
- **UX**: Users see a "Refresh Analysis" button with "Last updated X min ago" context. Admins also see
  the LLM cost of the last generation.
- **No new dependencies**: Uses existing `BriefGenerator`, `CoinGeckoClient`, and `Req`
- **No migrations**: `signal_enrichments` already has `llm_cost_usd`, `brief_generated_at`, and all
  needed fields
