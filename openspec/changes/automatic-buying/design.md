## Context

The app currently integrates with Binance, Bitget, and MEXC as **read-only price oracles** via a `Behaviour`-based
adapter pattern (`Exchanges.Binance`, `Exchanges.Bitget`, `Exchanges.Mexc`). All HTTP calls go through
`Coins.HTTPClient.ReqAdapter` using unauthenticated public endpoints. The `Trading` context manages positions
manually — users enter a symbol, the app fetches the current price, and creates a position record. The `PricePoller`
then tracks it every 5 seconds with Telegram alerts.

There is no exchange authentication, no order placement, and no encrypted credential storage anywhere in the codebase.
User secrets are limited to `api_token_hash` (SHA-256, one-way) in `UserSettings` and env vars in `runtime.exs`.

Signals live in a separate context (`Signals`) and have no direct relationship to positions — the only link is
temporal matching via `Signals.find_signal_at_time/2` in the closed positions view.

## Goals / Non-Goals

**Goals:**

- Place market buy orders and OCO sell orders on Binance from the signal detail page
- Encrypt and store per-user exchange API credentials using field-level encryption (AES-256-GCM)
- Auto-create app positions from executed trades for tracking on `/positions`
- Handle partial failures gracefully (buy succeeds, OCO fails → create position + urgent alert)
- Gate everything behind `:automatic_buying` feature flag (admin-only initially)

**Non-Goals:**

- Syncing OCO order status back to the app (V1 — positions are closed manually)
- Trading on Bitget or MEXC (Binance only for V1)
- Limit orders, trailing stops, or any order type beyond market buy + OCO sell
- Portfolio risk limits (max position size, daily spend caps)
- Paper trading / simulation mode

## Decisions

### 1. Cloak + Cloak Ecto for field-level encryption

Cloak is the standard Elixir library for transparent field-level encryption. It defines custom Ecto types
(`Cloak.Ecto.Binary`, `Cloak.Ecto.SHA256`) that encrypt on write and decrypt on read, invisible to
application code. The encryption key derives from `SECRET_KEY_BASE` (already a secret in `runtime.exs`).

A `CoinTracker.Vault` GenServer handles key management and is added to the supervision tree.

**Why not raw `:crypto`?** The app already uses `:crypto` for token hashing, but Cloak provides key rotation,
multiple cipher support, and Ecto integration out of the box. Rolling our own would duplicate what Cloak does.

**Why not a separate encryption key?** `SECRET_KEY_BASE` is already the highest-value secret in the system.
Deriving a sub-key from it (via `Cloak.Ciphers.AES.GCM` key config) avoids introducing another secret to manage.
If the app later needs key rotation independent of Phoenix, Cloak supports adding a second cipher and
migrating — but that's a V2 concern.

### 2. Separate `exchange_credentials` table (not in `user_settings`)

Exchange credentials get their own schema and table because:

- A user may have credentials for multiple exchanges (Binance now, Bitget later)
- Each credential has its own lifecycle (added, tested, revoked)
- The table stores encrypted binary blobs which don't belong alongside locale preferences
- Easier to audit, index, and query independently

Schema: `user_id`, `exchange` (enum), `api_key_encrypted`, `api_secret_encrypted`, `api_key_hash`
(for lookups without decryption), `label`, `last_used_at`, timestamps.

**Alternative considered:** Adding encrypted columns to `user_settings` — rejected because it conflates
concerns and doesn't scale to multiple exchanges.

### 3. TradingBehaviour + TradingClient strategy pattern (mirrors PriceClient)

The existing price-fetching layer uses a clean strategy pattern: `Exchanges.Behaviour` defines
`fetch_prices/2`, three exchange modules implement it, and `PriceClient` dispatches by exchange atom.
Trading follows the exact same pattern with a separate behaviour.

**`Exchanges.TradingBehaviour`** defines the contract:

- `market_buy(credential, symbol, quote_qty, opts)` → `{:ok, buy_result}` | `{:error, reason}`
- `place_oco_sell(credential, symbol, qty, tp_price, sl_price, opts)` → `{:ok, oco_result}` | `{:error, reason}`

**`Exchanges.Binance.Trading`** implements `TradingBehaviour` for Binance (V1, the only implementation):

- Accepts credentials as a parameter (never reads from DB — the caller provides them)
- Signs requests using HMAC-SHA256 via `Binance.AuthPlugin` (Req request step)
- Adds `X-MBX-APIKEY` header and `timestamp` parameter
- Uses the same `Req`-based HTTP client pattern (with DI for testing via `opts`)

**`Coins.TradingClient`** is the facade (mirrors `PriceClient`):

- Dispatches `market_buy/5` and `place_oco_sell/7` by exchange atom
- `:binance_spot` → `Exchanges.Binance.Trading`
- `:bitget_spot` / `:mexc_spot` → raise or return `{:error, :exchange_not_supported}` for now

**Why a separate behaviour from `Exchanges.Behaviour`?** Trading has completely different inputs
(credentials, order params) and outputs (order fills, order lists) from price fetching. Forcing them
into the same behaviour would weaken the type contracts. Each exchange also has different authentication
mechanisms (Binance uses HMAC-SHA256, Bitget uses a different signing scheme).

**Why pass credentials as params?** Keeps the trading modules stateless and testable. The orchestration
layer (`Trading.AutoBuy`) is responsible for fetching credentials from the DB.

### 4. Trading.AutoBuy as an orchestration module in the Trading context

The three-step flow (buy → OCO → create position) lives in `CoinTracker.Trading.AutoBuy`. This follows
the project's existing context-vs-orchestration pattern: the `Trading` context owns position CRUD, and
`AutoBuy` orchestrates cross-concern operations (exchange API + position creation + Telegram alerts).

`AutoBuy` is **exchange-agnostic** — it calls `TradingClient` (the facade), never a specific exchange
module directly. The exchange is determined by the signal's `symbol_price.exchange` field.

```
Trading.AutoBuy.execute/4
│
├─ 1. Accounts.get_exchange_credential(user, signal.symbol_price.exchange)
│     → decrypts credentials via Cloak
│
├─ 2. TradingClient.market_buy(exchange, credential, symbol, quote_qty, opts)
│     → dispatches to Binance.Trading (or future Bitget.Trading, etc.)
│     → returns {:ok, %{fill_price, filled_qty, order_id}}
│
├─ 3. TradingClient.place_oco_sell(exchange, credential, symbol, filled_qty, tp_price, sl_price, opts)
│     → returns {:ok, %{order_list_id}} or {:error, reason}
│     → on failure: log, send urgent Telegram, continue to step 4
│
├─ 4. Trading.create_position(user_id, %{
│       entry_price: fill_price,
│       amount_invested: quote_qty,
│       take_profit_percent: tp,
│       stop_loss_percent: sl (negative),
│       source: :auto_buy
│     })
│
└─ 5. Return {:ok, result} or {:partial, result} or {:error, reason}
```

Return types:
- `{:ok, %{position: position, buy_order: order, oco_order: oco}}` — full success
- `{:partial, %{position: position, buy_order: order, oco_error: reason}}` — buy ok, OCO failed
- `{:error, reason}` — buy failed, nothing happened

### 5. Dedicated `/signals/:id/trade` LiveView page

A separate page rather than inline form on the signal show page because:

- The signal show page is already dense (charts, insights, metrics) on mobile
- Trading involves real money — a dedicated page creates intentional friction
- The form → preview → executing → result state machine is cleaner in its own LiveView
- Easy to feature-gate the entire route

The LiveView manages state via an `@step` assign (`:form` | `:preview` | `:executing` | `:success` | `:error`).
The trade is executed in a `Task.Supervisor`-supervised task to avoid blocking the LiveView process, with
results sent back via `send(self(), {:trade_result, result})`.

### 6. Position `source` field for distinguishing auto-created positions

Add a `source` string field to positions (default `"manual"`, also `"auto_buy"`). This enables:

- Visual distinction on `/positions` (badge or icon)
- Future filtering (show only auto-traded positions)
- Analytics (auto vs manual performance comparison)

Stored as a string rather than enum to allow future sources without migrations (e.g., `"copy_trade"`,
`"bot"`).

### 7. Binance request signing via Req plugin

Rather than building signing into each function, create a `CoinTracker.Exchanges.Binance.AuthPlugin` module
that works as a Req request step. It:

- Adds `timestamp` to query params (current time in ms)
- Sorts and encodes all query params
- Computes HMAC-SHA256 signature using the API secret
- Appends `signature` to query params
- Adds `X-MBX-APIKEY` header

This keeps the trading functions clean — they just build params and call `Req.post!/2` with the plugin
attached.

## Risks / Trade-offs

**[API key security]** → Storing exchange API keys is the highest-security addition to the app. Mitigation:
AES-256-GCM encryption via Cloak, derived from `SECRET_KEY_BASE`. Keys only decrypted in-memory when placing
orders. Users should be guided to create Binance keys with **spot trading only** permissions (no withdrawals,
no futures).

**[Partial failure — buy succeeds, OCO fails]** → The user owns coins without a safety net. Mitigation: create
the position anyway (so it's tracked), send urgent Telegram alert with clear instructions to place stop-loss
manually. The LiveView shows the failure state with a "Retry OCO" button.

**[Binance API rate limits]** → Trading endpoints have separate rate limits from market data (1200 request
weight/minute for orders). A single trade is 2 API calls (buy + OCO). Mitigation: this is a manual action,
not automated — unlikely to hit limits. Add rate limit headers to response logging for monitoring.

**[Price slippage between preview and execution]** → Market buy fills at market price, which may differ from
the preview price. The preview should show "estimated" amounts and include a note about slippage. The OCO
prices are calculated from the actual fill price, not the preview price.

**[App position diverges from exchange OCO]** → After the OCO fills on Binance, the app position remains
active until manually closed. Mitigation: clear UX warning on the trade page and on the position card. The
existing PricePoller alerts will tell the user when TP/SL thresholds are hit (a signal that the OCO probably
fired).

**[Binance OCO price rules]** → Binance has specific rules: for a SELL OCO, the limit price (TP) must be above
last price, and the stop price (SL) must be below last price. If the market moves between buy fill and OCO
placement, the OCO could be rejected. Mitigation: validate prices against current market before placing OCO.
On rejection, fall back to the partial failure flow.

## Migration Plan

1. Add `cloak` and `cloak_ecto` dependencies
2. Create `Vault` module and add to supervision tree
3. Create `exchange_credentials` migration and schema
4. Add `source` field migration to `positions`
5. Build `Binance.Trading` and `Binance.AuthPlugin` modules
6. Build `Trading.AutoBuy` orchestration
7. Build credential management UI (settings page)
8. Build `SignalLive.Trade` LiveView
9. Add "Trade this signal" button to `SignalLive.Show` (feature-gated)
10. Create `:automatic_buying` feature flag

Each step is independently deployable. The feature flag ensures nothing is visible until the full chain works.

## Open Questions

1. **Credential management page location** — `/settings/exchange-keys`? Or a new tab within an existing
   settings page? (The app currently has minimal user settings UI beyond locale.)
2. **Should we validate Binance credentials on save?** — A test API call (e.g., `GET /api/v3/account`) would
   confirm the key works and has the right permissions. Adds latency to the save flow but catches bad keys
   early.
3. **Minimum trade amount** — Binance has minimum notional value per pair (usually 5-10 USDT). Should we
   enforce a floor in the form validation, or let Binance reject it and show the error?
