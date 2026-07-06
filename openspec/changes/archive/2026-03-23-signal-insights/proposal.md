# Signal Insights

## Problem

The `/signals` page shows up to 10 active signals from CoinScanX, but there isn't enough context to decide which coins are worth buying or how they compare to each other. Users leave the app to manually check CoinMarketCap or CoinGecko for volume, market cap, and other fundamentals. Even then, the raw numbers are hard to interpret for non-crypto-expert users.

The result: picking a coin from the list feels like guessing.

## Solution

Enrich each signal with fundamental data from CoinGecko (market cap, supply, exchanges, ATH, category, volume) and generate a plain-English "Coin Brief" using Claude Sonnet 4.6 that explains what the data means and whether the signal looks strong or weak.

The brief is:
- **Pre-computed** on a 30-minute cycle (no user-facing latency)
- **Bilingual** (English and Spanish in one API call)
- **Bold in tone** — opinionated, conditional, actionable ("This looks strong because X, but watch Y")
- **Volume-first** — volume is the most important indicator, always analyzed first and most prominently
- **Backed by facts** — no technical analysis, no pattern matching, only current real data

## Key Design Decisions

1. **CoinGecko as data source** — generous free tier, all needed endpoints, willing to upgrade to paid if needed
2. **Top 500 coin mapping** — hardcoded/cached symbol-to-CoinGecko-ID mapping from top 500 coins. CoinScanX signals rarely fall outside this range
3. **Two volume stories** — CoinScanX entry volume vs current (is the signal still valid?) + CoinGecko absolute volume and vol/mcap ratio (is the market real?)
4. **Sonnet 4.6** — capable enough for nuanced natural language, affordable at ~720K tokens/day worst case
5. **Pre-computed briefs** — generated when enrichment data updates, not on user request. Stored in DB, served instantly
6. **Feature flagged** — behind `:signal_insights` feature flag

## Non-Goals

- Technical analysis or historical pattern matching — we consider this unreliable
- Real-time brief generation on every page view
- Price predictions or specific buy/sell recommendations
- On-chain analytics (may explore later)
- Social sentiment analysis (may explore later)

## User Experience

From the signals list, users tap an "Insights" link on any signal. This opens a new mobile-first page (`/signals/:id/insights`) showing:

1. **TL;DR** — Bold verdict with 2-3 sentence justification
2. **Volume Analysis** — Most prominent section, weaves CoinScanX delta + CoinGecko absolute
3. **Full Analysis** — Supply risk, exchange liquidity, ATH context, category
4. **Quick Facts** — Key metrics with static plain-English explanations
5. **Freshness indicator** — "Last updated X minutes ago, next update in ~Y minutes"
6. **Disclaimer** — "Not financial advice" in clear language
