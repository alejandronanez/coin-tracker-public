## Why

When a user triggers an automatic buy, the system currently sends the order to Binance without checking if the account has enough USDT. If the balance is insufficient, Binance rejects the order with error `-2010` — but only after the request is made. This wastes an API call and creates a poor user experience. More importantly, the user has no way to know their available balance upfront or have the system automatically cap the spend to what they can afford.

By proactively fetching the account balance before placing orders, we can: (1) prevent doomed API calls, (2) automatically cap the buy amount to the available balance minus a safety margin (~1%), and (3) surface the available balance in the trade UI so users can make informed decisions.

## What Changes

- Add a new Binance API function to query the account's USDT balance (`GET /api/v3/account`)
- Add balance-checking to the `TradingClient` facade and `TradingBehaviour`
- Integrate balance validation into `AutoBuy.execute/5` — before placing the market buy, fetch the available USDT balance, and if the requested amount exceeds what's available, automatically cap it to `available_balance * 0.99` (1% safety margin)
- Show the user's available USDT balance on the trade form so they know their spending limit
- Return a clear error if the available balance (after the 1% margin) is too low to place any meaningful order
- Change OCO failure behavior: if the OCO sell order fails after a successful market buy, do **not** create a position in the app — return a full error instead of a partial success. Creating a position without exchange-side protection gives users a false sense of safety

## Capabilities

### New Capabilities
- `balance-check`: Pre-trade balance validation — fetching account balance from Binance, capping order amounts to available funds with a safety margin, and surfacing balance information in the trade UI
- `oco-failure-handling`: When OCO placement fails after a successful buy, do not create a position — treat it as a full error and alert the user to manage the open buy manually

## Impact

- **Behavior change**: `AutoBuy.execute/5` no longer returns `{:partial, ...}` — OCO failure is now a full `{:error, ...}`. The Telegram alert for OCO failure remains (user still needs to manage the open buy on the exchange)
- **Code**: `Exchanges.Binance.Trading`, `TradingClient`, `TradingBehaviour`, `AutoBuy`, `SignalLive.Trade`
- **APIs**: New call to Binance `GET /api/v3/account` (authenticated, weight 20)
- **Dependencies**: None — uses existing `Req` HTTP client and Binance auth plugin
- **Security**: The `/api/v3/account` endpoint requires the same API key + signature auth already in use; no new permissions needed
