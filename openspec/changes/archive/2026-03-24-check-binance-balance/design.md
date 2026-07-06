## Context

The `AutoBuy.execute/5` orchestrates market buy + OCO sell on Binance. Currently, it goes straight to placing the order without checking if the account has sufficient USDT. If the balance is too low, Binance rejects the order (error `-2010`), wasting an API call and providing a poor experience.

The existing architecture is well-layered: `AutoBuy` → `TradingClient` (facade) → `Exchanges.Binance.Trading` (implementation), with `TradingBehaviour` defining the contract. Authentication uses `AuthPlugin` with HMAC-SHA256 signing. The trade UI (`SignalLive.Trade`) renders a form → preview → execution flow.

## Goals / Non-Goals

**Goals:**
- Fetch available USDT balance from Binance before placing a market buy
- Automatically cap the buy amount to `available_balance * 0.99` when the requested amount exceeds available funds
- Return a clear error when the available balance (after margin) is below a minimum threshold
- Display the available USDT balance in the trade form UI so users know their spending limit
- Follow existing patterns: add to `TradingBehaviour`, implement in `Binance.Trading`, dispatch through `TradingClient`

**Non-Goals:**
- Checking balances for non-USDT quote assets
- Supporting exchanges other than Binance (follows existing pattern — other exchanges return `:exchange_not_supported`)
- Real-time balance streaming or polling (single fetch at trade time is sufficient)
- Caching balances across requests
- Checking balance for OCO sell (the base asset is already held after the buy)

## Decisions

### 1. Balance fetch goes through the existing layer stack

**Decision:** Add `fetch_balance/3` to `TradingBehaviour` → `Binance.Trading` → `TradingClient`, mirroring how `market_buy`, `place_oco_sell`, and `fetch_symbol_filters` work.

**Why:** Keeps the architecture consistent. The facade pattern means `AutoBuy` never talks to Binance directly, and testing with mock HTTP clients works identically.

**Alternative considered:** Putting the balance check directly in the LiveView mount. Rejected because the LiveView shouldn't call exchange APIs directly — that's the trading layer's responsibility.

### 2. Use Binance `GET /api/v3/account` endpoint

**Decision:** Call `GET /api/v3/account` (signed request, weight 20) and extract the free USDT balance from the `balances` array.

**Why:** This is Binance's standard endpoint for account info. It returns all asset balances in a single call. We only need to extract the `free` amount for `USDT`.

**Alternative considered:** `GET /api/v3/account` returns all balances which is more data than needed, but there's no lighter endpoint for a single asset's balance. The response is small enough (a few KB) that this is fine.

### 3. Balance check + amount capping in `AutoBuy.execute/5`

**Decision:** Insert a balance check step in the `with` chain, after fetching credentials and symbol filters but before placing the market buy. If `requested_amount > available * 0.99`, cap to `available * 0.99`. If `available * 0.99 < minimum_order` (e.g., $1 USDT), return `{:error, :insufficient_balance}`.

**Why:** The orchestrator (`AutoBuy`) is the right place to make spend decisions — it already controls the order flow. The 1% safety margin accounts for rounding, fees, and price movement between the balance check and order execution.

**Alternative considered:** Having the Binance Trading module auto-cap internally. Rejected because amount capping is a business decision (the 1% margin, the minimum threshold) that belongs in the orchestrator, not the exchange adapter.

### 4. Fetch balance in LiveView mount for UI display

**Decision:** When the trade form mounts and the user has credentials, fetch their USDT balance asynchronously (in `connected?/1` phase) and display it above the amount field. Use `assign_async/3` or a simple `Task` + `handle_info` pattern.

**Why:** Users should see how much they can spend before entering an amount. Fetching in `connected?/1` means it loads after the initial render (no blocking mount) and works well with LiveView's async patterns.

**Alternative considered:** Fetching balance only on form submission. Rejected because the goal is to inform the user upfront.

### 5. Safety margin as a module constant

**Decision:** Define `@safety_margin Decimal.new("0.99")` in `AutoBuy`, making the effective spend `min(requested, available * 0.99)`.

**Why:** A constant is simple, easy to find, and easy to change. No need for runtime configuration — this is an internal safety buffer, not a user preference.

### 6. OCO failure = full error, no position created

**Decision:** If the OCO sell order fails after a successful market buy, `AutoBuy.execute/5` returns `{:error, {:oco_failed, reason}}` instead of `{:partial, ...}`. No position is created in the app. The existing Telegram alert is still sent so the user knows they have an unprotected buy on the exchange.

**Why:** Creating a position without exchange-side TP/SL gives users a false sense of protection. They see a position with stop-loss values in the app, but nothing is actually protecting them on Binance. It's better to surface this as a clear failure and let the user handle the open buy manually, than to create a phantom position.

**Alternative considered:** Keep the partial success pattern but add a visual warning on the position. Rejected because the position would still show up in lists, potentially trigger app-side alerts, and generally behave as if it's protected when it's not.

## Risks / Trade-offs

- **Race condition:** Balance may change between the check and the order placement (another order, a withdrawal). → Mitigation: The 1% margin provides a buffer. If the order still fails with `-2010`, the existing error handling catches it.
- **Extra API call:** Every auto-buy now makes one additional Binance request (weight 20). → Mitigation: Binance's rate limit is 1200 weight/minute. A single extra call per trade is negligible.
- **Balance fetch on mount:** Adds latency to the trade page load. → Mitigation: Fetch async after connection. The form is usable immediately; balance info appears when ready.
- **Stale balance in UI:** If user leaves the page open, the displayed balance may become stale. → Mitigation: Acceptable — the balance is re-checked in `AutoBuy.execute/5` before ordering. The UI value is informational only.
