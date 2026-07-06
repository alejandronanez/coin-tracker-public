## 1. Idempotency Keys

- [x] 1.1 Add `generate_client_order_id/0` private function to `binance/trading.ex` using `:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)`
- [x] 1.2 Add `newClientOrderId: generate_client_order_id()` to `market_buy` params
- [x] 1.3 Add `listClientOrderId: generate_client_order_id()` to `place_oco_sell` params

## 2. Timeouts and Retry

- [x] 2.1 Update `post_signed/4` to accept `:req_opts` from opts and merge into `Req.post` call, and set `retry: false` on `Req.new`
- [x] 2.2 Pass `req_opts: [connect_timeout: 10_000, receive_timeout: 30_000]` from `market_buy`
- [x] 2.3 Pass `req_opts: [connect_timeout: 10_000, receive_timeout: 60_000]` from `place_oco_sell`

## 3. Tests

- [x] 3.1 Add assertion in success test that `newClientOrderId` is present in market buy params (32-char hex)
- [x] 3.2 Add assertion in success test that `listClientOrderId` is present in OCO sell params (32-char hex)
- [x] 3.3 Run `mix precommit` and fix any issues
