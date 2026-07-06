## Context

The Binance trading module (`binance/trading.ex`) makes HTTP requests via Req to place market buy and OCO sell orders. Currently it uses Req's default configuration: no explicit timeouts, automatic retry on connection errors, and no client-side order IDs. On 03/23, this caused an OCO sell to appear as failed when it actually succeeded — Req retried after a lost response, Binance returned a conflict error on the retry, and the app classified it as a failure.

The module has two trading endpoints (`market_buy`, `place_oco_sell`) and one public endpoint (`fetch_symbol_filters`). All signed requests go through `post_signed/4`.

## Goals / Non-Goals

**Goals:**
- Prevent duplicate orders from automatic retries
- Make each trading request identifiable via idempotency keys
- Set appropriate HTTP timeouts per endpoint complexity
- Disable automatic retry for all order-creating requests

**Non-Goals:**
- Order verification after failure (querying open orders to confirm state) — valuable but separate concern
- Persisting order IDs to the database
- Retry-with-verification logic at the application level
- Changes to `fetch_symbol_filters` (public, read-only, safe to retry)

## Decisions

### 1. Idempotency key generation: `:crypto.strong_rand_bytes/1` → hex

Generate a 32-character hex string per request via `:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)`. Binance accepts up to 36 characters for client order IDs.

**Alternative considered:** UUID v4 via a library — adds a dependency for no benefit. Raw random bytes encoded as hex are sufficient and already available in OTP.

### 2. Per-request timeout configuration via opts

Each caller passes its timeout values through the existing `opts` keyword list as `:req_opts`. `post_signed` merges these into the `Req.post` call. This keeps the interface simple — no new function signatures, no shared config module.

**Alternative considered:** Centralized trading Req builder function — unnecessary with only two callers. Would add indirection without reducing duplication.

### 3. Retry disabled at `Req.new` level

Set `retry: false` on `Req.new(url: url, retry: false)` inside `post_signed`. This applies to all signed trading requests uniformly.

**Alternative considered:** Per-request retry config — no trading request should ever be retried, so a blanket disable is correct and simpler.

## Risks / Trade-offs

- **[Genuine transient failures won't be retried]** → Acceptable. A failed order that truly failed is safe (no money spent). The user can retry manually. False-success (current bug) is far worse than false-failure.
- **[Idempotency keys are not persisted]** → If the response is lost, we can't use the same key to re-query. This is a future improvement (order verification), explicitly out of scope.
- **[60s OCO timeout may still be too short in extreme conditions]** → Unlikely. Binance processes OCO orders in 1-3s under normal load. 60s is a generous upper bound that protects against edge cases without leaving users waiting indefinitely.
