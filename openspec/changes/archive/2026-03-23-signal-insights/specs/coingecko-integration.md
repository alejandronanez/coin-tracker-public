# Spec: CoinGecko Integration

## Capability

Fetch fundamental coin data from CoinGecko API and maintain a symbol-to-ID mapping for the top 500 coins.

## Requirements

### Symbol Mapping

- Fetch top 500 coins from CoinGecko `/coins/markets` endpoint (2 pages of 250)
- Store mapping of uppercase symbol → CoinGecko ID, name, and market cap rank
- Handle duplicate symbols by keeping the higher-ranked coin
- Refresh weekly via `MappingRefresher` GenServer
- Mapping must be queryable by symbol for fast lookups during enrichment

### Coin Detail Fetching

- For a given CoinGecko ID, fetch from `/coins/{id}` with these data points:
    - `market_data.market_cap.usd`
    - `market_data.market_cap_rank`
    - `market_data.total_volume.usd` (24h)
    - `market_data.circulating_supply`
    - `market_data.total_supply`
    - `market_data.fully_diluted_valuation.usd`
    - `market_data.ath.usd`
    - `market_data.ath_change_percentage.usd`
    - `market_data.ath_date.usd`
    - `market_data.price_change_percentage_1h_in_currency.usd`
    - `market_data.price_change_percentage_24h_in_currency.usd`
    - `market_data.price_change_percentage_7d_in_currency.usd`
    - `tickers` (count unique exchanges)
    - `categories` (first category as primary)

- Calculate derived metrics:
    - `vol_mcap_ratio` = total_volume / market_cap
    - `circulating_supply_pct` = circulating_supply / total_supply * 100
    - `fdv_mcap_ratio` = fully_diluted_valuation / market_cap

### API Client

- Use `Req` library following the `CoinscanApiClient` pattern
- Implement `HTTPClient` behaviour for test mockability
- Configuration: `base_url`, `api_key` (optional for free tier), `auth_header`, `retry`
- Support both tiers via config:
  - Free/Demo: `https://api.coingecko.com/api/v3` with `x-cg-demo-api-key` header
  - Paid Analyst+: `https://pro-api.coingecko.com/api/v3` with `x-cg-pro-api-key` header
- Handle rate limiting gracefully (CoinGecko returns 429)
- Parse decimal values using `Decimal` for financial precision

### Rate Limits & Cost

Starting with top 10 active signals (in_top: true) for enrichment. Event-driven first-time
enrichment guarantees coverage even for signals that rotate out quickly (~15 min cycles).

**Free tier (development):**
- 10K calls/month, ~30 calls/min
- Top 10 enrichment: ~12 calls per 30-min cycle (10 coins + 2 mapping pages)
- 48 cycles/day × 12 calls = 576 calls/day + ~10 event-driven/day ≈ 586 calls/day
- Monthly: ~17,580 calls — exceeds free tier (10K/month)
- Free tier works for development and testing, but production will need paid tier

**Analyst tier (production, $129/month):**
- 500K calls/month, 500 calls/min
- At ~17,580 calls/month: uses only ~3.5% of monthly allowance
- Plenty of headroom to expand to all ~30 signals later

Design for sequential calls with small delays between them to stay within per-minute limits.

## Constraints

- Never call CoinGecko from LiveView processes (always pre-fetched)
- All CoinGecko data stored in DB, never served directly from API response
- API key and auth header configurable via environment variables to support tier switching
- Top 10 signals (in_top: true) enriched with priority in every cycle
