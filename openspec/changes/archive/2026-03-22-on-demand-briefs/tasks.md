## 1. Extract enrichment logic to Signals context

- [x] 1.1 Add `Signals.refresh_enrichment/1` public function that takes a signal struct: fetches CoinGecko data via `CoinGeckoClient.fetch_coin_detail/1`, upserts enrichment via `upsert_signal_enrichment/2`, generates brief via `BriefGenerator.generate/2`, saves brief via `update_enrichment_brief/2`, and broadcasts `signal_enrichments:updated`. Returns `{:ok, enrichment}` or `{:error, reason}`
- [x] 1.2 Refactor `EnrichmentPoller.enrich_signal/1` to call `Signals.refresh_enrichment/1` instead of duplicating the logic inline

## 2. Remove polling from EnrichmentPoller

- [x] 2.1 Remove `handle_info(:enrich_all, ...)` clauses, `handle_cast(:enrich_all, ...)`, `perform_full_enrichment/0`, and the `enrich_now/0` public function
- [x] 2.2 Remove `Process.send_after(self(), :enrich_all, interval)` from init and the enrich_all handler
- [x] 2.3 Remove `:interval` from GenServer state and `get_config/0`
- [x] 2.4 Remove `send(self(), :enrich_all)` from init — the poller no longer fires on startup, it only reacts to PubSub events
- [x] 2.5 Clean up runtime.exs config: remove `:interval` option from `EnrichmentPoller` config (keep `:enabled`)

## 3. Add on-demand refresh to Insights LiveView

- [x] 3.1 Add `:refreshing?` (boolean, default false) and `:last_refresh_requested_at` (DateTime or nil) assigns in `handle_params`
- [x] 3.2 Add `handle_event("refresh_analysis", ...)` that checks throttle (20 min), spawns a `Task.Supervisor` task calling `Signals.refresh_enrichment/1`, sets `:refreshing?` to true, and stores `last_refresh_requested_at`
- [x] 3.3 Add a `Task.Supervisor` to the application supervision tree (e.g. `CoinTracker.TaskSupervisor`) if one doesn't already exist
- [x] 3.4 Handle task completion: the existing `handle_info(:enrichments_updated, ...)` already refreshes the data — add reset of `:refreshing?` to false in that handler
- [x] 3.5 Add a `Process.send_after(self(), :refresh_timeout, 30_000)` when spawning the task, and handle `:refresh_timeout` to reset `:refreshing?` and show error flash if still refreshing

## 4. Update Insights template

- [x] 4.1 Add "Refresh Analysis" button in the freshness bar area (after the timestamp text). Use `phx-click="refresh_analysis"`, disable when `@refreshing?` is true, show spinner icon when refreshing. Give the button a unique DOM id like `id="refresh-analysis-btn"`
- [x] 4.2 Add admin cost display in the freshness bar: when `User.admin?(@current_scope.user)` and `@enrichment.llm_cost_usd` is not nil, show cost formatted as "$X.XXXX" in small muted text next to the timestamp

## 5. Testing

- [x] 5.1 Unit test for `Signals.refresh_enrichment/1`: mock CoinGecko and BriefGenerator responses, verify enrichment upsert, brief save, and PubSub broadcast
- [x] 5.2 LiveView test: verify "Refresh Analysis" button appears, verify throttling (second click within 20 min shows flash), verify admin cost display is visible for admin users and hidden for non-admin
- [x] 5.3 LiveView test: verify the refreshing state resets after enrichment update arrives via PubSub
- [x] 5.4 EnrichmentPoller test: verify no polling timer fires, verify event-driven path still works
