# Signal Insights — Implementation Tasks

## Phase 1: Data Foundation

- [x] **Task 1.1: Create database tables** — Create migrations for `coin_gecko_mappings` and `signal_enrichments` tables with all fields from design doc. Add unique indexes (symbol for mappings, signal_id for enrichments).
- [x] **Task 1.2: Create Ecto schemas** — Create `CoinGeckoMapping` and `SignalEnrichment` schemas with changesets. SignalEnrichment belongs_to Signal. Signal has_one SignalEnrichment.
- [x] **Task 1.3: Add context functions** — Add functions to the Signals context for upserting mappings, upserting enrichments, querying enrichments by signal, looking up CoinGecko IDs by symbol, and querying signals without enrichments.

## Phase 2: CoinGecko Integration

- [x] **Task 2.1: CoinGecko HTTP client** — Create the CoinGecko API client following the CoinscanApiClient pattern. HTTPClient behaviour for testability. Two functions: `fetch_top_coins/2` and `fetch_coin_detail/1`. Parse responses into maps with Decimal values. Support both free and paid tier URLs via config.
- [x] **Task 2.2: MappingRefresher GenServer** — GenServer that fetches top 500 coins from CoinGecko and upserts into coin_gecko_mappings. Runs on startup then weekly. Follows existing poller pattern. Guards on `:signal_insights` feature flag.
- [x] **Task 2.3: EnrichmentPoller GenServer (hybrid)** — Hybrid GenServer combining event-driven and polling enrichment. Subscribes to `"signals:updated"` PubSub, enriches new signals immediately, refreshes all active signals every 30 min. Guards on `:signal_insights` feature flag. Broadcasts `"signal_enrichments:updated"` on PubSub.

## Phase 3: Brief Generation

- [x] **Task 3.1: Add req_llm dependency** — Add `{:req_llm, "~> 1.7"}` to mix.exs. Configure Anthropic API key via runtime.exs and test.exs.
- [x] **Task 3.2: BriefGenerator module** — Pure module that builds the prompt from signal + enrichment data and calls `ReqLLM.generate_text/3` with prompt caching enabled. Contains the system prompt, parses response into brief structures.
- [x] **Task 3.3: Integrate brief generation into EnrichmentPoller** — After enrichment data is fetched, trigger BriefGenerator for each updated signal. Store briefs and brief_generated_at timestamp.

## Phase 4: UI

- [x] **Task 4.1: Feature flag setup** — Create the `:signal_insights` feature flag. Add conditional "Insights" link to signal list (desktop and mobile). Link only visible when flag is enabled AND enrichment exists.
- [x] **Task 4.2: Insights LiveView page** — Create LiveView at `/signals/:id/insights`. Load signal with preloaded enrichment. Subscribe to PubSub for live updates. Implement mount, handle_params, handle_info. EN/ES language toggle.
- [x] **Task 4.3: Insights template** — Build mobile-first template with all sections: header, freshness bar, TL;DR card, volume analysis, full analysis, quick facts grid, disclaimer. Empty/error states.

## Phase 5: Testing

- [x] **Task 5.1: CoinGecko client tests** — Test response parsing, error handling, rate limit (429) handling, tier switching. Mock HTTP responses.
- [x] **Task 5.2: BriefGenerator tests** — Test prompt building, response parsing, handling of missing/partial data. Mock req_llm calls.
- [x] **Task 5.3: Context function tests** — Test enrichment upsert, mapping upsert/lookup, query for signals without enrichments.
- [x] **Task 5.4: LiveView tests** — Test page load with/without enrichment, feature flag gating, empty states, language toggle, freshness display.

## Phase 6: Configuration & Deployment

- [x] **Task 6.1: Environment variables** — Document required env vars and add to deployment config.
- [x] **Task 6.2: Seed mapping data** — Run initial mapping refresh to populate coin_gecko_mappings.
