## 1. Balance Fetch API Layer

- [x] 1.1 Add `fetch_balance/2` callback to `TradingBehaviour` with typespec (`@callback fetch_balance(credential(), String.t(), keyword()) :: {:ok, %{free: Decimal.t(), asset: String.t()}} | {:error, error_reason()}`)
- [x] 1.2 Implement `fetch_balance/3` in `Exchanges.Binance.Trading` — call `GET /api/v3/account` (signed), extract the free balance for the requested asset from the `balances` array, return `{:ok, %{free: ..., asset: ...}}`
- [x] 1.3 Add `fetch_balance/4` dispatch in `TradingClient` — route `:binance_spot` to `Binance.Trading.fetch_balance/3`, return `:exchange_not_supported` for others

## 2. Balance Check in AutoBuy

- [x] 2.1 Add `@safety_margin Decimal.new("0.99")` and `@min_order_usdt Decimal.new("1")` constants to `AutoBuy`
- [x] 2.2 Insert balance check step in the `with` chain in `AutoBuy.execute/5` — after `fetch_credential` and before `market_buy`, call `TradingClient.fetch_balance/4` to get available USDT
- [x] 2.3 Implement amount capping logic: if `amount_usdt > available * @safety_margin`, cap to `available * @safety_margin`; if capped amount < `@min_order_usdt`, return `{:error, {:insufficient_balance, "Available balance too low..."}}`

## 3. OCO Failure Handling

- [x] 3.1 In `AutoBuy.execute/5`, change the OCO failure branch: remove position creation, return `{:error, {:oco_failed, %{buy_order: buy_result, reason: oco_reason}}}` instead of `{:partial, ...}`
- [x] 3.2 Remove the `{:partial, ...}` return type from `AutoBuy.execute/5` — update the `@doc` and callers
- [x] 3.3 Update `SignalLive.Trade` to handle `{:oco_failed, details}` in the error step — display a clear message that the buy succeeded but OCO failed, with instructions to manage manually on the exchange
- [x] 3.4 Remove the `:partial_failure` step and its template from `SignalLive.Trade`

## 4. Trade UI Balance Display

- [x] 4.1 In `SignalLive.Trade` mount, when `connected?/1` and user has credentials, start async balance fetch via `Task` + `send(self(), :fetch_balance)`
- [x] 4.2 Add `handle_info(:fetch_balance, socket)` that calls `TradingClient.fetch_balance/4` and assigns the result (`:available_balance` assign — `nil` = loading, `{:ok, Decimal.t()}` = loaded, `{:error, reason}` = failed)
- [x] 4.3 Display available balance near the amount input: loading spinner while fetching, formatted balance when loaded, subtle warning on error

## 5. Tests

- [x] 5.1 Add unit tests for `Binance.Trading.fetch_balance/3` — success with USDT found, asset not found (returns 0), auth error, network error
- [x] 5.2 Add unit tests for `AutoBuy.execute/5` balance capping — amount within balance (no cap), amount exceeds balance (capped), balance too low (error), balance fetch failure (propagated)
- [x] 5.3 Add unit tests for `AutoBuy.execute/5` OCO failure — verify no position is created, verify `{:error, {:oco_failed, ...}}` is returned, verify Telegram alert is sent
- [x] 5.4 Add LiveView tests for `SignalLive.Trade` — balance display on mount, loading state, error state, OCO failure error display
