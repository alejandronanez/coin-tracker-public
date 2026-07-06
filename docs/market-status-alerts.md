# Market Status Telegram Alerts

This document explains how market status alerts work - automatic Telegram notifications when the market reaches or leaves full capacity (10/10 active signals).

## Overview

The system monitors the number of active signals in the top 10 and sends Telegram alerts to pro/admin users when:
- **Recovery**: Market reaches 10/10 active signals (full capacity)
- **Drop**: Market drops from 10/10 to any lower number

## Alert Messages

| Transition | Message |
|------------|---------|
| X → 10 (recovery) | `🟢 Market: 10/10` |
| 10 → X (drop) | `🔴 Market: 7/10` |

The messages are intentionally short for instant recognition on mobile.

## Architecture

The alert system follows clean separation of concerns:

```
MarketStatusPoller (Signals context)
    ↓ Owns: WHEN to alert (transition detection)
    ↓ Owns: WHO to alert (pro users query)
    ↓
Accounts.list_pro_users_with_telegram/0
    ↓ Returns: List of eligible user IDs
    ↓
TelegramService.broadcast_message/2
    ↓ Just sends messages (no business logic)
    ↓
ExGram → Telegram API
```

**Key principle**: `TelegramService` is a generic messaging service. It doesn't know about market status, user segments, or business logic. The caller decides who gets the message.

## Data Flow

```
1. MarketStatusPoller.perform_capture/0 runs whenever Signals.Poller
   broadcasts a fingerprint change (plus once at boot)
    ↓
2. Gets previous market status from database
    ↓
3. Creates new market status (counts active signals in top 10)
    ↓
4. Calls maybe_send_market_alert(previous, current)
    ↓
5. Detects transition (to/from 10)
    ↓
6. If transition detected:
   - Fetches pro/admin users with Telegram: Accounts.list_pro_users_with_telegram()
   - Maps to user IDs
   - Broadcasts via TelegramService.broadcast_message(user_ids, message)
```

## Who Receives Alerts

Only users who meet ALL of these criteria:
- Have an **active pro or admin subscription**
- Have **Telegram linked** to their account

The query in `Accounts.list_pro_users_with_telegram/0`:
```elixir
from(u in User,
  join: tu in TelegramUser,
  on: tu.user_id == u.id,
  where:
    u.subscription_tier == :admin or
      (u.subscription_tier == :pro and
         (is_nil(u.subscription_expires_at) or u.subscription_expires_at > ^now)),
  select: u
)
```

## Key Files

| File | Purpose |
|------|---------|
| `lib/coin_tracker/signals/market_status_poller.ex` | GenServer that polls and detects transitions |
| `lib/coin_tracker/telegram_client/telegram_service.ex` | Generic `broadcast_message/2` function |
| `lib/coin_tracker/accounts.ex` | `list_pro_users_with_telegram/0` query |

## Code References

### Transition Detection (market_status_poller.ex)

```elixir
defp maybe_send_market_alert(nil, _current), do: :ok

defp maybe_send_market_alert(previous, current) do
  prev_count = previous.active_signals_count
  curr_count = current.active_signals_count

  message =
    cond do
      prev_count != 10 and curr_count == 10 -> "🟢 Market: 10/10"
      prev_count == 10 and curr_count != 10 -> "🔴 Market: #{curr_count}/10"
      true -> nil
    end

  if message do
    user_ids = Accounts.list_pro_users_with_telegram() |> Enum.map(& &1.id)
    TelegramService.broadcast_message(user_ids, message)
  else
    :ok
  end
end
```

### Broadcasting (telegram_service.ex)

```elixir
def broadcast_message(user_ids, message) when is_list(user_ids) and is_binary(message) do
  results = Enum.map(user_ids, &send_message(&1, message))
  success_count = Enum.count(results, &match?({:ok, :sent}, &1))
  {:ok, success_count}
end
```

## Testing

Tests are in `test/coin_tracker/signals/market_status_alert_test.exs`:
- Recovery scenario (7 → 10 triggers alert)
- Drop scenario (10 → 7 triggers alert)
- No alert when staying at 10
- No alert when staying below 10
- Broadcast to user IDs
- Graceful handling of users without Telegram

## Triggering Alerts Programmatically

```elixir
# Send a market alert to all pro users
user_ids = Accounts.list_pro_users_with_telegram() |> Enum.map(& &1.id)
TelegramService.broadcast_message(user_ids, "🟢 Market: 10/10")

# Or manually trigger market status capture (which may trigger alert)
CoinTracker.Signals.MarketStatusPoller.capture_now()
```

## Related Documentation

- [Telegram Integration](telegram-integration.md) - General Telegram setup and architecture
- [Market Status Poller](market-status-poller.md) - How market status is captured
- [Position Alerts](telegram-alerts.md) - Threshold-based position alerts
