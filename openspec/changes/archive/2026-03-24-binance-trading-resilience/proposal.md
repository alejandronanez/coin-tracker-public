## Why

On 03/23, an auto-buy for TAO/USDT placed a market buy and OCO sell on Binance. The OCO was created on Binance, but the HTTP response was lost. Req's default retry then re-sent the request, Binance returned a duplicate/conflict error (~5s total), and the app classified it as a failure — showing "OCO order failed" when the OCO was real and hit take-profit 2 hours later. The app has no idempotency keys on trading requests, no explicit HTTP timeouts, and Req's automatic retry is dangerous for order creation.

## What Changes

- Add `newClientOrderId` (market buy) and `listClientOrderId` (OCO sell) idempotency keys to all Binance trading requests, generated as 32-char hex UUIDs
- Set explicit HTTP timeouts per trading endpoint: 10s connect / 30s receive for market buy, 10s connect / 60s receive for OCO sell
- Disable Req's automatic retry (`retry: false`) on all trading requests — order creation must never be retried automatically

## Capabilities

### New Capabilities
- `trading-request-resilience`: Idempotency keys, explicit timeouts, and retry disabling for Binance trading HTTP requests

### Modified Capabilities

(none — no existing spec-level behavior changes)

## Impact

- `lib/coin_tracker/coins/exchanges/binance/trading.ex` — all three changes land here (idempotency params, timeout opts, retry config)
- `test/coin_tracker/trading/auto_buy_test.exs` — verify idempotency keys are present in request params
- Mock HTTP modules in tests receive new params (`newClientOrderId`, `listClientOrderId`) which they should accept without breaking
