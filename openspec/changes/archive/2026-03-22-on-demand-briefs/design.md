## Context

The EnrichmentPoller currently runs two paths:

1. **Event-driven** (`enrich_new_signals/0`): Subscribes to `"signals:updated"`, enriches signals
   without a `signal_enrichment` record. This produces the first brief within 45s. Low cost, high value.

2. **Polling** (`perform_full_enrichment/0`): Every 30 minutes, re-fetches CoinGecko data and
   regenerates briefs for ALL active signals. This is the dominant cost driver (80% of LLM spend).

The polling path regenerates briefs nobody asked for. At $0.014/brief × 10 signals × 48 cycles/day,
it burns 720/month. The fix is to delete the polling path entirely and let users trigger refreshes
when they want them.

**Current private function `enrich_signal/1`** in EnrichmentPoller handles the full flow:
CoinGecko fetch → upsert enrichment → generate brief → save brief. This logic needs to be
extractable so the LiveView can call it on demand.

## Goals / Non-Goals

**Goals:**

- Remove the polling timer and `perform_full_enrichment/0` from EnrichmentPoller
- Extract single-signal enrichment into a public `Signals.refresh_enrichment/1` function
- Add "Refresh Analysis" CTA to the Insights LiveView with per-signal throttling
- Show `llm_cost_usd` to admin users in the freshness bar
- Keep event-driven enrichment for new signals unchanged

**Non-Goals:**

- Changing the brief format, prompt, or LLM model
- Adding background refresh on any schedule
- Building a queuing system for refresh requests
- Showing cost to non-admin users

## Decisions

### 1. Extract enrichment logic to `Signals.refresh_enrichment/1`

Move the CoinGecko fetch → upsert → brief generate → save flow from `EnrichmentPoller.enrich_signal/1`
(currently private) into a public `Signals.refresh_enrichment/1` in the context module. Both the
EnrichmentPoller's event-driven path and the LiveView's on-demand refresh call this same function.

**Why?** The enrichment logic belongs in the context, not in a GenServer. The poller's `enrich_signal/1`
currently mixes orchestration concerns (CoinGecko → upsert → brief → save) with GenServer lifecycle.
Extracting it makes the logic testable without GenServer overhead and callable from any process.

**Alternative considered:** Making `EnrichmentPoller.enrich_signal/1` public. Rejected because LiveView
processes shouldn't depend on a GenServer module for business logic — that couples UI to infrastructure.

### 2. Run on-demand enrichment in a Task, not in the LiveView process

When the user clicks "Refresh Analysis," spawn a `Task` to run `Signals.refresh_enrichment/1`.
The LiveView immediately shows a "Refreshing..." state and receives the update via the existing
PubSub broadcast (`signal_enrichments:updated`) when the task completes.

**Why?** CoinGecko fetch (1-2s) + LLM generation (3-5s) = 5-7s total. Blocking the LiveView
process for that long would freeze the UI. The PubSub pattern already handles async updates — the
LiveView already subscribes to `signal_enrichments:updated` and refreshes on broadcast.

**Alternative considered:** Synchronous call with loading spinner. Rejected because the LiveView
process would be unresponsive to price updates and other events during the 5-7s enrichment.

### 3. Throttle via assign, not database

Track `last_refresh_requested_at` as a socket assign in the LiveView. Reject refresh requests within
20 minutes of the last one. No database field needed — throttling is per-session, not global.

**Why?** This is a UI concern, not a data concern. If two admins both refresh the same signal, that's
fine — the second refresh just overwrites the first with slightly newer data. The throttle prevents
accidental double-clicks and rapid repeated refreshes from a single session.

### 4. Cost display in the freshness bar for admins only

Add the `llm_cost_usd` from the enrichment record to the existing freshness bar. Format as a small
secondary text like "· Cost: $0.014". Only render when `User.admin?(@current_scope.user)`.

**Why the freshness bar?** The cost is contextual to "when was this generated" — it belongs next to the
timestamp. No new UI section needed.

### 5. Simplify EnrichmentPoller to event-driven only

Remove:

- `handle_info(:enrich_all, ...)` clause
- `handle_cast(:enrich_all, ...)` clause
- `perform_full_enrichment/0`
- `enrich_now/0` public function
- `Process.send_after(self(), :enrich_all, interval)` timer
- `:interval` from state and config

Keep:

- `handle_info({:signals_updated, _}, ...)` clause
- `enrich_new_signals/0` (calls `Signals.refresh_enrichment/1` for each)

The GenServer becomes a thin PubSub subscriber that triggers first-time enrichment for new signals.

## Risks / Trade-offs

**[Briefs can become stale]** → If nobody refreshes, a brief stays at its initial generation forever.
Mitigation: the freshness bar already shows staleness (amber when >60min). Users see "Data is X
minutes old" and can click "Refresh Analysis" if they want fresh data. The initial brief is still
valid — it covered the buy/not-buy decision at signal entry.

**[CoinGecko rate limits on user-triggered refreshes]** → Multiple users refreshing multiple signals
could hit CoinGecko's API rate limit. Mitigation: 20-minute per-signal throttle in UI, plus CoinGecko
rate limits are generous (30 calls/min on free tier). With 10 signals and throttling, this won't be
an issue.

**[Task process failure]** → If the spawned Task crashes during refresh, the user sees "Refreshing..."
indefinitely. Mitigation: use `Task.Supervisor` with a timeout. On timeout or crash, the LiveView
can reset the refreshing state. The PubSub broadcast won't arrive, so after a reasonable timeout
(30s), reset the UI state.

## Open Questions

None — this change is straightforward and well-scoped.
