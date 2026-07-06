# Signal Insights — Technical Design

## Architecture Overview

```
CoinGecko /coins/markets (top 500)
    │
    ▼
coin_gecko_mappings table ←── MappingRefresher (weekly GenServer)
    │
    │   For each active signal, look up CoinGecko ID
    ▼
CoinGecko /coins/{id} endpoint
    │
    ▼
EnrichmentPoller (hybrid GenServer)
    │
    ├─ EVENT-DRIVEN: subscribes to "signals:updated" PubSub
    │   → checks for signals WITHOUT enrichment
    │   → enriches only new signals immediately (~45s after appearing)
    │   → guarantees at least one insight per signal
    │
    ├─ POLLING: every 30 min refresh cycle
    │   → re-enriches all active signals WITH existing enrichment
    │   → keeps data fresh
    │
    ├──▶ signal_enrichments table (raw metrics)
    │
    ▼
BriefGenerator (triggered after enrichment)
    │
    ├──▶ req_llm → Anthropic API (Sonnet 4.6)
    │     - Prompt caching: system prompt cached across all calls
    │     - Sends structured signal + enrichment data per coin
    │     - Receives JSON with en + es briefs
    │
    ├──▶ signal_enrichments.brief_en / brief_es (stored)
    │
    ▼
PubSub broadcast: "signal_enrichments:updated"
    │
    ▼
SignalLive.Insights (LiveView page)
    - Loads pre-computed brief instantly
    - Shows freshness indicator
    - Mobile-first layout
```

### Why Hybrid Event-Driven + Polling?

Signals rotate every ~15 minutes. A pure 30-minute polling cycle would miss signals that
enter and exit between cycles. The event-driven component subscribes to the existing
`"signals:updated"` PubSub topic (fires every ~45 seconds after ingestion) and checks
for un-enriched signals. This guarantees every signal gets at least one insight,
even if it's only in the top 10 for 15 minutes.

## Data Model

### coin_gecko_mappings

Maps CoinScanX symbols to CoinGecko IDs. Populated from the top 500 coins.

| Column          | Type         | Notes                 |
|-----------------|--------------|-----------------------|
| id              | bigint       | PK                    |
| symbol          | string       | Uppercase, e.g. "ETH" |
| coingecko_id    | string       | e.g. "ethereum"       |
| name            | string       | Full name             |
| market_cap_rank | integer      | CoinGecko global rank |
| inserted_at     | utc_datetime |                       |
| updated_at      | utc_datetime |                       |

Unique index on `symbol`. When duplicates exist (rare in top 500), keep the higher-ranked coin.

### signal_enrichments

Stores CoinGecko metrics + generated briefs for each signal.

| Column                 | Type               | Notes                               |
|------------------------|--------------------|-------------------------------------|
| id                     | bigint             | PK                                  |
| signal_id              | references signals | FK, unique                          |
| coingecko_id           | string             | Cached from mapping                 |
| market_cap_usd         | decimal            |                                     |
| market_cap_rank        | integer            | Global rank                         |
| volume_24h_usd         | decimal            | CoinGecko 24h volume                |
| vol_mcap_ratio         | decimal            | Calculated: volume / mcap           |
| circulating_supply_pct | decimal            | circulating / total * 100           |
| fdv_mcap_ratio         | decimal            | FDV / market cap                    |
| total_supply           | decimal            | Total token supply                  |
| circulating_supply     | decimal            | Circulating token supply            |
| ath_usd                | decimal            | All-time high price                 |
| ath_distance_pct       | decimal            | % below ATH                         |
| ath_date               | date               | When ATH was reached                |
| exchange_count         | integer            | Number of exchanges listed          |
| category               | string             | Primary category (meme, defi, etc.) |
| price_change_1h_pct    | decimal            |                                     |
| price_change_24h_pct   | decimal            |                                     |
| price_change_7d_pct    | decimal            |                                     |
| brief_en               | text               | Generated English brief (JSON)      |
| brief_es               | text               | Generated Spanish brief (JSON)      |
| enriched_at            | utc_datetime       | When CoinGecko data was fetched     |
| brief_generated_at     | utc_datetime       | When Claude generated the brief     |
| inserted_at            | utc_datetime       |                                     |
| updated_at             | utc_datetime       |                                     |

Unique index on `signal_id` — one enrichment per signal.

## Components

### 1. CoinGeckoClient

HTTP client module following the existing `CoinscanApiClient` pattern:

- Uses `Req` with configurable retry
- Implements an `HTTPClient` behaviour for testability
- Two main functions:
    - `fetch_top_coins(page, per_page)` — calls `/coins/markets`, returns list of coin mappings
    - `fetch_coin_detail(coingecko_id)` — calls `/coins/{id}`, returns enrichment data

Configuration via `runtime.exs` (supports both free and paid tiers):

```elixir
# Free/Demo tier:
config :coin_tracker, CoinTracker.Signals.CoinGeckoClient,
  base_url: "https://api.coingecko.com/api/v3",
  api_key: System.get_env("COINGECKO_API_KEY"),
  auth_header: "x-cg-demo-api-key",
  retry: true

# Paid Analyst tier ($129/mo):
# config :coin_tracker, CoinTracker.Signals.CoinGeckoClient,
#   base_url: "https://pro-api.coingecko.com/api/v3",
#   api_key: System.get_env("COINGECKO_API_KEY"),
#   auth_header: "x-cg-pro-api-key",
#   retry: true
```

Rate limit awareness: Start with the free tier for development (10K calls/month, ~30 calls/min).
For production with ~10 active signals enriched every 30 min plus event-driven first-time
enrichments, the free tier should be sufficient initially. If we expand to all ~30 signals or
need more frequent refreshes, upgrade to the Analyst tier ($129/mo, 500K calls/month).

### 2. Anthropic Integration via req_llm

Uses the `req_llm` library (`{:req_llm, "~> 1.7"}`) instead of raw HTTP calls. `req_llm` is
built on Req (already in our deps), handles all Anthropic API wire format, and provides
built-in prompt caching support.

No GenServer needed — `req_llm` is stateless function calls, invoked from the EnrichmentPoller.

```elixir
# Brief generation call with prompt caching:
ReqLLM.generate_text(
  "anthropic:claude-sonnet-4-6",
  messages,
  max_tokens: 4096,
  temperature: 0.7,
  provider_options: [
    anthropic_prompt_cache: true
  ]
)
```

Configuration:

```elixir
config :req_llm,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")
```

### Prompt Caching Strategy

The system prompt (tone rules, output format, volume priority instructions) is identical
across all signal enrichments. With prompt caching enabled:

- **First call in a cycle**: Cache WRITE — system prompt cached at 1.25x input price
- **Subsequent calls (9 more)**: Cache READ — system prompt reused at 0.1x input price (90% discount)
- **Default TTL**: 5 minutes (free) — sufficient since all 10 calls in a cycle run back-to-back

This means the ~800-1000 token system prompt is only "paid for" once per enrichment cycle.

### 3. MappingRefresher (GenServer)

Refreshes the `coin_gecko_mappings` table from CoinGecko's top 500 coins.

- Runs on application start, then weekly
- Fetches 2 pages of 250 coins each from `/coins/markets`
- Upserts into `coin_gecko_mappings` (update rank + name on conflict)
- Logs count of mapped coins
- Disabled in test via config

### 4. EnrichmentPoller (Hybrid GenServer)

Combines event-driven first-time enrichment with periodic refresh.

**Event-driven (first-time enrichment):**
1. Subscribe to `"signals:updated"` PubSub topic on init
2. On each broadcast, query for active signals that have NO `signal_enrichment` record
3. For each un-enriched signal with a known CoinGecko mapping:
   a. Fetch coin detail from CoinGecko
   b. Upsert `signal_enrichments` record
   c. Generate brief via BriefGenerator
4. Broadcast `"signal_enrichments:updated"` on PubSub

**Polling (refresh, every 30 min):**
1. Get all active signals that HAVE an existing enrichment
2. For each, re-fetch CoinGecko data and update enrichment
3. Re-generate briefs
4. Broadcast `"signal_enrichments:updated"` on PubSub

**Priority:** Top 10 (`in_top: true`) signals are enriched first in both modes.

Guard: only runs if `:signal_insights` feature flag is enabled globally.

### 5. BriefGenerator

Pure module (not a GenServer) responsible for:

- Building the prompt from signal + enrichment data
- Calling `ReqLLM.generate_text/3` with prompt caching enabled
- Parsing the response JSON into brief structures

The prompt includes:

- System prompt with `cache_control` — defining tone (bold), volume priority, bilingual output, disclaimer requirement. This is the cached portion.
- User message with structured JSON of all metrics (CoinScanX + CoinGecko) — unique per signal.

Brief JSON structure stored in `brief_en` / `brief_es`:

```json
{
  "tldr": "Looks promising. ...",
  "volume_analysis": "Volume is building. When this signal appeared...",
  "full_analysis": "PEPE is a large meme token ranked #24...",
  "disclaimer": "This analysis is informational only..."
}
```

### 6. SignalLive.Insights (LiveView)

New LiveView page at `/signals/:id/insights`.

Mount:

- Load signal with preloaded enrichment
- Subscribe to `"signal_enrichments:updated"` for live refresh

Template sections:

1. Header: coin symbol, name, current price, CoinScanX rank
2. Freshness bar: "Last updated X min ago / Next update in ~Y min" (with stale warning if > 1 hour)
3. TL;DR card (prominent, colored based on verdict sentiment)
4. Volume analysis section
5. Full analysis section
6. Quick facts grid with static inline explanations
7. Disclaimer footer

Language: determined by user locale preference (default English, Spanish if configured).

Mobile-first: single column, readable typography, no horizontal scrolling.

## Configuration Summary

```elixir
# runtime.exs additions:
config :coin_tracker, CoinTracker.Signals.CoinGeckoClient,
  base_url: System.get_env("COINGECKO_BASE_URL", "https://api.coingecko.com/api/v3"),
  api_key: System.get_env("COINGECKO_API_KEY"),
  auth_header: System.get_env("COINGECKO_AUTH_HEADER", "x-cg-demo-api-key"),
  retry: true

config :req_llm,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")

config :coin_tracker, CoinTracker.Signals.EnrichmentPoller,
  enabled: true,
  interval: :timer.minutes(30)

config :coin_tracker, CoinTracker.Signals.MappingRefresher,
  enabled: true,
  interval: :timer.hours(168)  # weekly

# test.exs additions:
config :coin_tracker, CoinTracker.Signals.CoinGeckoClient,
  retry: false
config :req_llm,
  anthropic_api_key: "test-key"
config :coin_tracker, CoinTracker.Signals.EnrichmentPoller,
  enabled: false
config :coin_tracker, CoinTracker.Signals.MappingRefresher,
  enabled: false
```

## Feature Flag

Flag name: `:signal_insights`

Guards:

- `EnrichmentPoller` checks flag before each cycle and before event-driven enrichment (skip if disabled)
- `MappingRefresher` checks flag before each cycle
- "Insights" link on signal list only shown when flag is enabled
- `/signals/:id/insights` route shows fallback message when flag is disabled

## Error Handling

| Failure                          | Behavior                                                                                     |
|----------------------------------|----------------------------------------------------------------------------------------------|
| CoinGecko API down               | Skip enrichment cycle, log warning, retry next interval. Stale data shown with warning in UI |
| Unknown symbol (no mapping)      | Skip that signal's enrichment, log info. No insights link shown for that signal              |
| Anthropic API down               | Keep raw metrics, skip brief generation. UI shows "Brief unavailable" with raw quick facts   |
| Anthropic returns malformed JSON | Log error, keep previous brief. Retry next cycle                                             |
| CoinGecko rate limited (429)     | Back off, log warning. Enrichment resumes next cycle                                         |
| Signal exits before enrichment   | Event-driven mode catches it within ~45s. If it exits before even that, it wasn't enrichable |
