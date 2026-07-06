# Telegram Integration

This document describes how the Telegram integration works in CoinTracker, including the architecture, data flow, and implementation details.

## Overview

CoinTracker integrates with Telegram to allow users to:
- **Register their Telegram account** with a secure one-time token
- **View active positions** via the `/list` command
- **Receive real-time alerts** when their positions trigger alerts (profit milestones, stop loss warnings, closures, etc.)

## Architecture

The Telegram integration follows a **clean separation of concerns** with three main components:

### 1. Telegram Bot Handler (`TelegramClient.Telegram`)
- **Responsibility**: Handle incoming Telegram messages and commands
- **Commands**:
  - `/start TOKEN` - Register a Telegram chat with a user account
  - `/list` - Show the user's active trading positions
  - `/market` - Show the current market status (active signals count)

The handler is powered by ExGram, which polls Telegram for updates.

### 2. Telegram Service (`TelegramClient.TelegramService`)
- **Responsibility**: Core business logic for Telegram operations
- **Functions**:
  - `generate_deeplink(user)` - Create a registration token and deeplink
  - `register_chat(chat_id, token)` - Validate token and link Telegram chat to user
  - `list_positions(chat_id)` - Fetch and format user's active positions
  - `get_market_status(chat_id)` - Get current market status (active signals in top 10)
  - `send_message(user_id, message)` - Send message to linked Telegram chat

This module is independent of the bot handler, making it testable and reusable.

### 3. Alert Subscriber (`TelegramClient.TelegramAlertSubscriber`)
- **Responsibility**: Subscribe to trading alerts and deliver via Telegram
- **Behavior**:
  - Listens to Phoenix PubSub "alerts" topic
  - Receives alert events from AlertService
  - Delivers alerts to users who have linked Telegram
  - Gracefully skips users without Telegram linked

## Data Flow

### User Registration Flow

```
User clicks "Connect Telegram"
    ↓
Web UI calls Accounts.generate_telegram_token(user)
    ↓ Returns: https://t.me/bot_name?start=TOKEN
User clicks deeplink
    ↓
Telegram bot receives /start TOKEN
    ↓
TelegramService.register_chat(chat_id, TOKEN)
    ↓
Validates token exists and user owns it
    ↓
Creates TelegramUser record linking chat_id → user_id
    ↓
Invalidates token (sets to nil) to prevent reuse
    ↓
Returns: ✅ Welcome! Your Telegram account is now linked.
```

### Alert Delivery Flow

```
Price update from exchange
    ↓
PricePoller detects alert condition (threshold crossed, profit reached, etc.)
    ↓
AlertService.send_X_alert(position, ...)
    ↓
AlertService creates message + broadcasts PubSub event
    ↓
Phoenix.PubSub.broadcast("alerts", {:alert_type, position, params, message})
    ↓
TelegramAlertSubscriber receives event via handle_info/2
    ↓
Looks up user's chat_id via TelegramService.send_message(user_id, message)
    ↓
ExGram.send_message(chat_id, message) sends to Telegram
    ↓
User receives alert in Telegram
```

### Position List Flow

```
User sends /list command
    ↓
Telegram bot handler calls TelegramService.list_positions(chat_id)
    ↓
Looks up user by chat_id via Accounts.get_user_by_telegram_chat_id/1
    ↓
Fetches active positions: Trading.list_active_positions_for_user(user_id)
    ↓
Formats positions with current price, % change, stop loss, take profit
    ↓
Returns formatted message
    ↓
Bot sends message to Telegram
```

## Database Schema

### users table
- `telegram_token: string` - One-time registration token (nullable, invalidated after use)

### telegram_users table
- `chat_id: bigint` - Telegram chat ID (unique)
- `user_id: references(:users)` - Link to user account (unique, one chat per user)
- `inserted_at, updated_at: timestamps`

**Key constraint**: Each user can link only **one** Telegram chat, and each Telegram chat can link to only **one** user.

## Security Considerations

1. **Token Security**: Tokens are 32-character random strings generated using `:crypto.strong_rand_bytes/1`
2. **Token Invalidation**: After first use, tokens are immediately set to `nil` to prevent reuse
3. **One-Time Use**: Trying to use an already-used token returns an error
4. **One Chat Per User**: The unique constraint on `user_id` ensures users can't accidentally link multiple chats

## PubSub Architecture

The integration uses Phoenix PubSub for **decoupled alert delivery**:

### Why PubSub?
- **Decoupling**: AlertService doesn't know about Telegram; TelegramAlertSubscriber doesn't know about alerts
- **Scalability**: Easy to add other subscribers (EmailService, PushService, SMSService, etc.)
- **Real-time**: Natural fit for event-driven architecture

### Alert Events
All events follow the pattern: `{:alert_type, position, relevant_params..., formatted_message}`

**Event Types**:
- `:threshold_alert` - Position crossed a price threshold
- `:profit_alert` - Position reached a profit milestone
- `:stop_loss_warning` - Position approaching stop loss
- `:position_closed` - Position closed (take profit or stop loss)
- `:back_to_profit` - Position recovered from losses

### PubSub Topic
- **Topic**: `"alerts"`
- **Subscriber**: `TelegramAlertSubscriber` (runs as GenServer in non-test environments)

## Implementation Details

### AlertService Broadcasting
```elixir
# AlertService generates message and broadcasts event
{:ok, message} = AlertService.send_threshold_alert(position, zone, price)

# Internally:
Phoenix.PubSub.broadcast(
  CoinTracker.PubSub,
  "alerts",
  {:threshold_alert, position, zone, price, message}
)
```

### TelegramAlertSubscriber Processing
```elixir
# GenServer receives event
def handle_info({:threshold_alert, position, _zone, _price, message}, state) do
  send_alert_to_user(position.user_id, "📊 Threshold Alert\n\n#{message}")
  {:noreply, state}
end
```

### Error Handling
- **Missing PubSub in tests**: `broadcast_alert/1` catches `ArgumentError` and logs gracefully
- **User without Telegram**: `send_message/2` returns `:ok` silently if no chat_id found
- **Send failure**: Logs error but doesn't crash; Telegram service continues operating

## Commands Reference

### /start TOKEN
Registers a Telegram chat with a user account using a one-time token.

**Success Response**:
```
✅ Welcome! Your Telegram account is now linked.
```

**Error Responses**:
```
❌ Invalid or expired token
❌ This Telegram account is already linked to another account
❌ Failed to link Telegram account
```

### /list
Shows all active positions for the logged-in user with real-time prices and metrics.

**Response Format**:
```
📊 Your Active Positions:

1. ETH/USDT
   Entry: $2000.00
   Current: $2100.00 (+5.00%)
   SL: -10.0% | TP: +20.0%

2. BTC/USDT
   Entry: $50000.00
   Current: $52000.00 (+4.00%)
   SL: -5.0% | TP: +10.0%
```

**Error Response**:
```
❌ Telegram account not linked to any user
```

### /market
Shows the current market status - how many signals are active in the top 10.

**Response Format**:
```
🟢 Market: 10/10
```
or
```
🔴 Market: 7/10
```

The green indicator (🟢) appears when the market is at full capacity (10/10 active signals). The red indicator (🔴) appears when the market is below capacity.

**Error Response**:
```
❌ Telegram account not linked to any user
```

## Testing Considerations

- **TelegramAlertSubscriber**: Conditionally excluded from supervision tree in test environment to prevent PubSub initialization issues
- **PubSub Broadcasting**: Gracefully handles missing PubSub with try/rescue in AlertService
- **No External Calls**: Tests run without depending on actual Telegram API (mocking can be added if needed)

## Future Enhancements

### Feature Gating
Currently not implemented, but the architecture supports adding subscription-level restrictions:
```elixir
if user.subscription_level != :free do
  TelegramService.send_message(user_id, alert_message)
end
```

### Multi-Channel Alerts
The PubSub architecture makes it easy to add other notification channels:
- Email alerts
- Push notifications
- SMS alerts
- Discord/Slack integrations

### Telegram Enhancements
- Inline keyboards for quick actions (close position, adjust alerts)
- Rich formatting with Telegram's media capabilities
- Callback queries for interactive commands
- Deep links to positions in the web UI

## Troubleshooting

### "Telegram account not linked"
- User needs to complete the `/start TOKEN` flow
- Check that the token is valid and hasn't been used before
- Verify the TelegramUser record was created in the database

### No alerts received
- Ensure user has linked their Telegram account
- Check that feature gating isn't blocking alerts (if implemented)
- Verify the PricePoller is running and detecting alert conditions
- Check logs for PubSub broadcast failures

### Token already used
- Tokens are single-use only
- User needs to generate a new token via the web UI
- Each `/start TOKEN` command consumes the token

## Code References

**Key Files**:
- `lib/coin_tracker/telegram_client/telegram.ex` - Bot handler
- `lib/coin_tracker/telegram_client/telegram_service.ex` - Service logic
- `lib/coin_tracker/telegram_client/telegram_alert_subscriber.ex` - Alert subscription
- `lib/coin_tracker/accounts.ex` - Token and user management functions
- `lib/coin_tracker/trading/alert_service.ex` - Alert broadcasting
- `lib/coin_tracker/application.ex` - Supervision tree configuration
- `priv/repo/migrations/` - Database migrations

**Related Modules**:
- `CoinTracker.Accounts` - User and token management
- `CoinTracker.Trading` - Position and alert data
- `CoinTracker.Coins` - Price and symbol information
- `CoinTracker.PubSub` - Phoenix PubSub instance
