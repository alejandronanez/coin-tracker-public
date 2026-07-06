# Automatic Buying & OCO Orders

## Problem

When a signal looks promising on `/signals/:id`, executing on it requires leaving the app entirely: open Binance, find the pair, place a market buy, calculate take-profit and stop-loss prices from percentages, then place an OCO sell order — all by hand. Finally, come back to the app and manually create a position entry on `/positions` to track it.

This friction means good signals get missed or acted on too late. The manual OCO math is error-prone (especially on mobile), and forgetting to create the position in the app means no PnL tracking or Telegram alerts.

The app already tracks positions with live PnL, threshold alerts, and Telegram notifications. The missing piece is the **execution layer** — placing the actual orders on the exchange.

## Solution

Add a "Quick Trade" flow accessible from the signal detail page (`/signals/:id`). The user specifies how much USDT to spend and their take-profit/stop-loss percentages (defaulting to 15% / 20%). The app then:

1. Places a **market buy** on Binance for the specified USDT amount
2. Uses the fill price and quantity to place a **native OCO sell order** on Binance (exchange-managed take-profit + stop-loss)
3. Auto-creates a **position** in the app for tracking on `/positions`

The exchange manages the exit entirely — no sync needed between the app and Binance for V1. The existing position tracking (PnL, threshold alerts, Telegram) continues to work as-is. Users close the app-side position manually when the OCO fills.

A two-step **preview → confirm** flow prevents accidental trades. The preview shows estimated quantities, target prices with percentages, and potential profit/loss in USDT.

### Key Design Decisions

1. **Exchange-native OCO** — Binance manages the take-profit/stop-loss pair. More reliable than app-managed exits (survives server downtime). No sync needed for V1.
2. **Binance only for V1** — Simplifies the trading adapter. Bitget and MEXC support can follow the same pattern later.
3. **Dedicated trade page** (`/signals/:id/trade`) — Clean, focused mobile UX. The signal show page is already dense with charts and insights.
4. **Cloak + Cloak Ecto for key encryption** — The standard Elixir solution for field-level encryption. Transparent at the Ecto layer (read/write plaintext in code, encrypted at rest). Derives encryption key from the existing `SECRET_KEY_BASE`.
5. **Separate `exchange_credentials` table** — Not embedded in `user_settings`. Users may have credentials for multiple exchanges, each with its own lifecycle.
6. **Graceful partial failure** — If the buy succeeds but OCO placement fails, the position is still created and an urgent Telegram alert fires. The user can place the stop-loss manually on Binance.
7. **Position `source` field** — Distinguishes `:manual` vs `:auto_buy` positions for display and future filtering.
8. **Defaults: TP 15%, SL 20%** — Pre-filled in the form to reduce friction. Based on typical trading patterns.

## Capabilities

### New Capabilities

- `exchange-credential-management`: Encrypted storage of per-user exchange API keys (Cloak Ecto). CRUD operations, scoped to the Accounts context. Supports multiple exchanges per user.
- `binance-trading`: Authenticated Binance API client for placing market buy orders and OCO sell orders. HMAC-SHA256 signed requests via Req middleware. Separate from the existing read-only price adapter.
- `auto-buy-orchestration`: Three-step orchestration (market buy → OCO sell → create position) with error recovery. Lives in the Trading context as `Trading.AutoBuy`.
- `quick-trade-ui`: LiveView at `/signals/:id/trade` with form → preview → executing → result state machine. Feature-flagged behind `:automatic_buying`.

### Modified Capabilities

- `signal-detail`: Add a "Trade this signal" button on `/signals/:id`, gated by `:automatic_buying` feature flag and presence of exchange credentials.
- `position-tracking`: Add `:source` field (`:manual` | `:auto_buy`) to positions. Display a badge on `/positions` to distinguish auto-created positions.

## Impact

- **New dependencies**: `cloak` (~> 1.1) and `cloak_ecto` (~> 1.3) for field-level encryption
- **New database tables**: `exchange_credentials` (encrypted api_key, api_secret, exchange, user_id)
- **Schema changes**: `positions` table gets a `source` field (string, default "manual")
- **New modules**: ~6 new modules (Vault, ExchangeCredential, Binance.Trading, Trading.AutoBuy, SignalLive.Trade, credential management UI)
- **Modified modules**: SignalLive.Show (trade button), PositionLive.Index (source badge), Trading context (source field in creation)
- **Security surface**: Storing exchange API keys is a significant responsibility. Keys are encrypted at rest with AES-256-GCM via Cloak, derived from `SECRET_KEY_BASE`. Keys are only decrypted in-memory when placing orders.
- **Feature flag**: `:automatic_buying` — admin-only initially. Prevents any non-admin user from seeing the trade button or accessing the trade page.
- **External API**: New authenticated calls to Binance's `POST /api/v3/order` and `POST /api/v3/orderList/oco` endpoints. Subject to Binance rate limits (separate from market data limits).

## Non-Goals

- **Syncing OCO status back to the app** — For V1, the exchange manages exits independently. The app position is closed manually. A future iteration could poll order status or use Binance WebSocket user data streams.
- **Multi-exchange trading** — V1 is Binance only. The architecture supports adding Bitget/MEXC later via the same behaviour pattern.
- **Limit orders or advanced order types** — Only market buy + OCO sell. No limit buys, trailing stops, or other order types.
- **Portfolio management or risk limits** — No maximum position size, no daily spend limits, no portfolio-level stop. These are future concerns.
- **Automatic position closure on OCO fill** — Requires WebSocket integration or polling. Out of scope for V1.
- **Paper trading / simulation mode** — Would be nice but adds complexity. Users can test with small amounts.

## UX Flow

### Trade Page (`/signals/:id/trade`)

A single LiveView with four states managed via assigns:

1. **Form** — Amount (USDT), Take Profit (%), Stop Loss (%) with defaults pre-filled. "Preview Order" button.
2. **Preview** — Shows estimated quantity, target prices with percentages, potential profit/loss in USDT. Warning about manual position closure. "Edit" and "Confirm & Buy" buttons.
3. **Executing** — Progress indicators for each step (buy, OCO, position creation). No user interaction.
4. **Result** — Success redirects to `/positions` with flash. Partial failure (buy ok, OCO failed) shows urgent warning with "Go to Positions" and "Retry OCO" options.

### Credential Management

A settings page (path TBD, likely `/settings/exchange-keys`) where users can:
- Add a Binance API key + secret (with guidance on required permissions)
- See existing keys (masked, showing only prefix)
- Remove keys
- Test connectivity (optional, call Binance account endpoint)

### Prerequisites Check

The "Trade this signal" button on `/signals/:id` only appears when:
- `:automatic_buying` feature flag is enabled (for the user)
- User has at least one Binance credential stored

If the flag is on but no credentials exist, show a prompt linking to the credentials settings page.

## Architecture

```
SignalLive.Show                    SignalLive.Trade
(existing)                         (new)
┌─────────────┐   navigate    ┌──────────────────────┐
│ [Trade btn] │──────────────▶│ Form/Preview/Execute │
└─────────────┘               └──────────┬───────────┘
                                         │
                                         │ execute_signal/4
                                         ▼
                              ┌──────────────────────┐
                              │  Trading.AutoBuy     │
                              │                      │
                              │  1. market_buy ──────┼──▶ Binance.Trading
                              │  2. place_oco  ──────┼──▶ Binance.Trading
                              │  3. create_position ─┼──▶ Trading (existing)
                              │  4. error? telegram ─┼──▶ TelegramService
                              └──────────────────────┘
                                         │
                              uses credentials from
                                         │
                                         ▼
                              ┌──────────────────────┐
                              │ Accounts context     │
                              │ ExchangeCredential   │
                              │ (Cloak encrypted)    │
                              └──────────────────────┘
```
