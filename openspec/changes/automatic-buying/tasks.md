## 1. Encryption Foundation

- [x] 1.1 Add `cloak` (~> 1.1) and `cloak_ecto` (~> 1.3) dependencies to `mix.exs` and fetch
- [x] 1.2 Create `CoinTracker.Vault` GenServer module — configure AES-256-GCM cipher with key derived from `SECRET_KEY_BASE`, add to application supervision tree
- [x] 1.3 Define `CoinTracker.Vault.Encrypted.Binary` and `Cloak.Ecto.SHA256` custom Ecto types
- [x] 1.4 Write tests verifying Vault encrypts/decrypts values and SHA256 type produces consistent hashes

## 2. Exchange Credentials

- [x] 2.1 Create `exchange_credentials` migration — `user_id` (FK), `exchange` (string), `api_key_encrypted` (binary), `api_secret_encrypted` (binary), `api_key_hash` (binary), `label` (string), `last_used_at` (utc_datetime), timestamps. Unique index on `[user_id, exchange]`
- [x] 2.2 Create `CoinTracker.Accounts.ExchangeCredential` Ecto schema with Cloak encrypted field types and changeset with validations
- [x] 2.3 Add credential CRUD functions to `Accounts` context — `create_exchange_credential/2`, `list_exchange_credentials/1`, `get_exchange_credential/2` (by user_id + exchange), `delete_exchange_credential/2`, `update_credential_last_used/1`
- [x] 2.4 Write context-level tests for credential CRUD — creation, uniqueness constraint, listing (masks keys), deletion, last_used_at update

## 3. Trading Strategy Pattern

- [x] 3.1 Create `CoinTracker.Coins.Exchanges.TradingBehaviour` — define `@callback market_buy/4` and `@callback place_oco_sell/6` with typespecs, mirroring how `Exchanges.Behaviour` defines `fetch_prices/2`
- [x] 3.2 Create `CoinTracker.Coins.TradingClient` facade — dispatch `market_buy/5` and `place_oco_sell/7` by exchange atom (`:binance_spot` → `Binance.Trading`, others → `{:error, :exchange_not_supported}`), mirroring `PriceClient`
- [x] 3.3 Create `CoinTracker.Exchanges.Binance.AuthPlugin` — Req request step that adds timestamp, computes HMAC-SHA256 signature, appends signature param, sets `X-MBX-APIKEY` header
- [x] 3.4 Create `CoinTracker.Exchanges.Binance.Trading` module implementing `TradingBehaviour` — `market_buy/4` function: normalizes symbol, sends `POST /api/v3/order` with `type: MARKET`, `side: BUY`, `quoteOrderQty: amount`, parses fill response into `%{order_id, fill_price, filled_qty, quote_qty}`
- [x] 3.5 Add `place_oco_sell/6` to `Binance.Trading` — sends `POST /api/v3/orderList/oco` with computed TP price, SL stop price, SL stop-limit price (×0.995 buffer), `stopLimitTimeInForce: GTC`. Parses response into `%{order_list_id, tp_order_id, sl_order_id}`
- [x] 3.6 Add error classification to `Binance.Trading` — map Binance error codes to tagged tuples: `-2010` → `{:error, {:insufficient_balance, msg}}`, `-1121` → `{:error, {:invalid_symbol, msg}}`, `-2021` → `{:error, {:price_rule_violation, msg}}`, auth errors → `{:error, {:auth_error, msg}}`
- [x] 3.7 Write tests for `TradingBehaviour`, `TradingClient`, and `Binance.Trading` — mock HTTP client for: successful buy, successful OCO, insufficient balance, invalid symbol, auth failure, network error, unsupported exchange dispatch. Verify request signing produces correct signature format

## 4. Auto-Buy Orchestration

- [x] 4.1 Create `positions` migration to add `source` column (string, default "manual")
- [x] 4.2 Update `Position` schema — add `source` field, update `create_changeset` to accept source
- [x] 4.3 Create `CoinTracker.Trading.AutoBuy` module — `execute/4` function implementing the three-step orchestration: fetch credentials → call `TradingClient.market_buy` → call `TradingClient.place_oco_sell` → create position. Exchange-agnostic (determined by signal's symbol_price.exchange). Return `{:ok, result}`, `{:partial, result}`, or `{:error, reason}`
- [x] 4.4 Add partial failure Telegram alert — on OCO failure, send urgent message via `TelegramService` with symbol, quantity, fill price, error, and manual action instructions
- [x] 4.5 Add feature flag check to `execute/4` — verify `:automatic_buying` is enabled for user before proceeding, return `{:error, :feature_disabled}` if not
- [x] 4.6 Write tests for `AutoBuy.execute/4` — full success path, partial failure path (buy ok + OCO fail), buy failure path, no credentials path, feature flag disabled path, unsupported exchange path. Mock `TradingClient` and `TelegramService`

## 5. Credential Management UI

- [x] 5.1 Create `SettingsLive.ExchangeKeys` LiveView at `/settings/exchange-keys` — list existing credentials (masked), form to add new credential, delete with confirmation
- [x] 5.2 Add guidance text to credential form — explain required Binance permissions (spot trading only, no withdrawals), recommend IP restriction
- [x] 5.3 Add route and navigation — add route under authenticated live_session, add link from user settings or dropdown menu
- [x] 5.4 Write LiveView tests — render with/without credentials, add credential flow, delete credential flow, validation errors

## 6. Quick Trade LiveView

- [x] 6.1 Create `SignalLive.Trade` LiveView at `/signals/:id/trade` — mount loads signal + checks feature flag + checks credentials. State machine with `@step` assign (`:form`, `:preview`, `:executing`, `:result`)
- [x] 6.2 Implement form state — amount (USDT), take profit (%, default 15), stop loss (%, default 20, displayed positive). Inline validation via `phx-change`. Live price subscription via PubSub `"price_updates"`
- [x] 6.3 Implement preview state — calculate estimated quantity, TP/SL target prices with percentages, estimated profit/loss in USDT. Show sync warning about manual position closure. "Edit" and "Confirm & Buy" buttons
- [x] 6.4 Implement executing state — spawn trade via `Task.Supervisor`, show step-by-step progress. Handle `{:trade_result, result}` and `{:DOWN, ...}` messages
- [x] 6.5 Implement result states — success: redirect to `/positions` with flash. Partial failure: show error with "Go to Positions" and "Retry OCO" buttons. Full failure: show error with "Go back" button
- [x] 6.6 Add route for `/signals/:id/trade` — under the `require_pro_subscription` live_session (same as signals), gated by feature flag in mount
- [x] 6.7 Write LiveView tests — form rendering with defaults, preview calculations, feature flag redirect, no-credentials state, success redirect, error states

## 7. Signal Detail Integration

- [x] 7.1 Add trade button to `SignalLive.Show` — check `:automatic_buying` flag and credential existence in mount. Render "Trade this signal" button or setup prompt conditionally
- [x] 7.2 Add "Auto" badge to `PositionLive.Index` — show small badge on positions with `source: "auto_buy"`, no badge on `source: "manual"`
- [x] 7.3 Create `:automatic_buying` feature flag — add to FunWithFlags via admin UI or seeds

## 8. Testing & Verification

- [x] 8.1 Run full test suite — verify no regressions on existing position and signal tests (758 tests, 1 pre-existing failure unrelated to this change)
- [ ] 8.2 Manual end-to-end test with small amount — use real Binance testnet or small mainnet trade to verify full flow: credential storage → trade from signal → OCO placed → position created
