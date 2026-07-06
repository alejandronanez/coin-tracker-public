# Phoenix Contexts Reference

This document catalogs all Phoenix contexts in the CoinTracker application, their schemas, public functions, and relationships.

## Quick Reference

| Context | Purpose | Schemas |
|---------|---------|---------|
| `Accounts` | User authentication, subscriptions, Telegram linking | User, UserToken, TelegramUser, UserSettings, Scope |
| `Coins` | Real-time cryptocurrency prices | SymbolPrice |
| `Trading` | Position management and P&L tracking | Position |
| `Signals` | CoinScanX signal ingestion and snapshots | Signal, SignalSnapshot, MarketStatus, CoingeckoSnapshot |

> **Note:** The manual USDT TRC-20 `Payments` context is no longer shipped with this public release. `Accounts.activate_pro_subscription/2` still exists so fork operators can wire their own payment system to upgrade users; tier-based gating (`require_pro_subscription`, `User.active_subscription?/1`, etc.) continues to work unchanged.

---

## Accounts Context

**Location:** `lib/coin_tracker/accounts.ex` and `lib/coin_tracker/accounts/`

Handles user authentication, session management, subscription tiers, and Telegram integration.

### Schemas

#### User
Core user entity with authentication and subscription state.

```elixir
field :email, :string
field :hashed_password, :string
field :confirmed_at, :utc_datetime
field :subscription_tier, Ecto.Enum, values: [:free, :pro, :admin]
field :subscription_expires_at, :utc_datetime
```

#### TelegramUser
Links a Telegram chat to a user account (one-to-one relationship).

```elixir
field :chat_id, :integer
field :registration_token, :string  # One-time token for linking
belongs_to :user, User
```

#### UserSettings
User preferences (currently locale).

```elixir
field :locale, :string, default: "en"
belongs_to :user, User
```

#### UserToken
Session and magic link tokens for authentication.

```elixir
field :token, :binary
field :context, :string  # "session" or "confirm"
field :sent_to, :string
belongs_to :user, User
```

### Public Functions

#### User Management
| Function | Description |
|----------|-------------|
| `get_user_by_email/1` | Fetch user by email |
| `get_user_by_email_and_password/2` | Authenticate with email/password |
| `get_user!/1` | Fetch user by ID (raises on not found) |
| `register_user/1` | Register new user account |
| `change_user_email/3` | Create changeset for email change |
| `update_user_email/2` | Update email with token verification |
| `change_user_password/3` | Create changeset for password change |
| `update_user_password/2` | Update password and invalidate all tokens |

#### Subscription Management
| Function | Description |
|----------|-------------|
| `activate_pro_subscription/2` | Activate pro tier with expiry date |
| `activate_admin_subscription/1` | Activate admin tier (no expiry) |
| `downgrade_to_free/1` | Downgrade to free tier, removes Telegram link |
| `check_and_expire_subscription/1` | Check if pro subscription expired, downgrade if needed |

#### Session & Auth
| Function | Description |
|----------|-------------|
| `generate_user_session_token/1` | Create session token |
| `get_user_by_session_token/1` | Retrieve user from session token |
| `get_user_by_magic_link_token/1` | Retrieve user from magic link token |
| `login_user_by_magic_link/1` | Magic link login (handles confirmation) |
| `deliver_user_update_email_instructions/3` | Send email change confirmation |
| `deliver_login_instructions/2` | Send magic link login email |
| `delete_user_session_token/1` | Logout by invalidating token |

#### Telegram Integration
| Function | Description |
|----------|-------------|
| `generate_telegram_token/1` | Create one-time registration token |
| `get_user_by_telegram_token/1` | Fetch user by registration token |
| `invalidate_telegram_token/1` | Prevent token reuse after registration |
| `get_telegram_user/1` | Get TelegramUser record by user_id |
| `get_telegram_chat_id/1` | Get Telegram chat_id for user |
| `create_telegram_user/1` | Link Telegram chat to user |
| `get_user_by_telegram_chat_id/1` | Reverse lookup: get user by chat_id |
| `list_pro_users_with_telegram/0` | List all pro/admin users with Telegram linked |

#### User Settings
| Function | Description |
|----------|-------------|
| `get_user_settings/1` | Fetch user settings by user_id |
| `get_or_create_user_settings/1` | Get or create default settings |
| `update_user_settings/2` | Update locale preferences |
| `get_user_locale/1` | Get user's locale (defaults to "en") |

### Key Behaviors
- Magic link auth requires email confirmation on first use
- Subscription expiry checks happen automatically during login
- Downgrading to free tier removes Telegram integration
- 20-minute sudo mode for sensitive operations

---

## Coins Context

**Location:** `lib/coin_tracker/coins.ex` and `lib/coin_tracker/coins/`

Manages real-time cryptocurrency prices from multiple exchanges.

### Schemas

#### SymbolPrice
Represents current price for a trading pair on a specific exchange.

```elixir
field :exchange, Ecto.Enum, values: [:binance_spot, :bitget_spot, :mexc_spot]
field :symbol_pair, :string  # e.g., "BTCUSDT"
field :current_price, :decimal
```

### Public Functions

| Function | Description |
|----------|-------------|
| `upsert_symbol_price/1` | Create or update symbol price, broadcasts via PubSub |

### Related Modules

| Module | Purpose |
|--------|---------|
| `PriceClient` | Client for fetching prices from exchange APIs |
| `PricePoller` | GenServer polling prices every 5 seconds |
| `HttpClient` | HTTP abstraction using Req library |
| Exchange adapters | `Binance`, `Bitget`, `MEXC` |

### PubSub Topics
- `"price_updates"` - Broadcast on every price update

### Key Behaviors
- Uses upsert with `on_conflict: :replace_all` for idempotent updates
- Unique constraint on `[:exchange, :symbol_pair]`

---

## Trading Context

**Location:** `lib/coin_tracker/trading.ex` and `lib/coin_tracker/trading/`

Manages trading positions with profit/loss tracking and alert systems.

### Schemas

#### Position
Represents an active or closed trading position.

```elixir
field :entry_price, :decimal
field :stop_loss_percent, :decimal
field :take_profit_percent, :decimal
field :status, Ecto.Enum, values: [:active, :closed]
field :closed_reason, Ecto.Enum, values: [:take_profit, :stop_loss, :manual]
field :closed_at, :utc_datetime

# Alert tracking
field :last_pnl_percent, :decimal      # For recovery alerts
field :alert_sent_negative_30, :boolean
field :alert_sent_negative_40, :boolean
field :alert_sent_negative_50, :boolean
field :current_threshold, :integer      # For re-crossing detection

# Virtual fields (from form input)
field :symbol, :string, virtual: true
field :exchange, :string, virtual: true

belongs_to :user, User
belongs_to :symbol_price, SymbolPrice
```

### Public Functions

#### Position Management
| Function | Description |
|----------|-------------|
| `create_position/3` | Create position with exchange API price validation |
| `update_position/3` | Update entry price and thresholds |
| `list_active_positions_for_user/1` | Get all active positions for user |
| `list_active_positions_for_symbol_price/1` | Get positions by symbol price |
| `get_position_for_user/2` | Fetch position with authorization check |
| `close_position/2` | Close position with reason |

#### P&L Tracking
| Function | Description |
|----------|-------------|
| `calculate_pnl_percent/2` | Calculate profit/loss percentage |
| `update_position_pnl/2` | Track P&L for recovery alerts |
| `update_position_alert_state/4` | Track which alerts have been sent |
| `update_position_threshold/2` | Track current threshold for re-crossing detection |

#### Batch Operations
| Function | Description |
|----------|-------------|
| `get_symbol_prices_by_exchange_for_active_positions/0` | Group symbol pairs by exchange for batch price requests |

### Related Modules

| Module | Purpose |
|--------|---------|
| `PositionAlert` | Pure functions for alert logic |
| `AlertZone` | Alert configuration boundaries |

### PubSub Topics
- Position closures broadcast to user-specific topics

### Key Behaviors
- Position creation validates entry price via exchange API before saving
- Uses `Decimal` for all price calculations
- Tracks P&L thresholds: 10%, 20%, 30% for positive milestone alerts
- Tracks negative proximity: -30%, -40%, -50% approaching stop-loss
- Recovery alerts when bouncing back from negative thresholds

---

## Signals Context

**Location:** `lib/coin_tracker/signals.ex` and `lib/coin_tracker/signals/`

Ingests cryptocurrency signals from CoinScanX API and tracks state changes.

### Schemas

#### Signal
Cryptocurrency signal from CoinScanX (top 10 coins by volume change).

```elixir
# Immutable fields (set on creation)
field :symbol, :string
field :name, :string
field :in_top_since, :utc_datetime       # When first entered top 10
field :initial_price_usd, :decimal
field :initial_volume_24h, :decimal

# Real-time fields (updated by pollers)
field :current_price_usd, :decimal       # Live price
field :current_volume_24h, :decimal      # Current 24h volume
field :max_price_usd, :decimal           # Peak price since entry
field :max_increase_percentage, :decimal # Peak % gain
field :position, :integer                # 1-10 ranking (or nil)
field :in_top, :boolean                  # Currently in top 10?
field :active, :boolean                  # Still being tracked?
field :exit_date, :utc_datetime          # When exited top 10 (if out)

# Associations
belongs_to :symbol_price, SymbolPrice    # For live price display
has_many :snapshots, SignalSnapshot
```

**Important:** For UI display of current state, always use Signal fields directly (updated in real-time by pollers). Use SignalSnapshot records only for historical charts and trend analysis. See `docs/signal-snapshots.md` for details.

#### SignalSnapshot
Historical snapshot of signal state at a point in time.

```elixir
field :snapshot_at, :utc_datetime
field :current_price, :decimal
field :current_volume_24h, :decimal
field :current_volume_change_24h, :decimal
field :in_top, :boolean
field :position, :integer

belongs_to :signal, Signal
```

#### MarketStatus
Aggregated market data (count of active signals in top 10).

```elixir
field :active_signals_count, :integer
field :recorded_at, :utc_datetime
```

### Public Functions

#### Signal Ingestion
| Function | Description |
|----------|-------------|
| `ingest_top_10/0` | Fetch and ingest top 10 signals |
| `ingest_grace_period/0` | Fetch grace period signals (recently exited) |
| `ingest_all/0` | Fetch both with partial success handling |
| `deactivate_expired_signals/0` | Mark signals inactive after 24h grace period |

#### Signal Queries
| Function | Description |
|----------|-------------|
| `list_signals/1` | Query with filters (active, in_top, symbol, ordering) |
| `get_signal/1` | Fetch single signal by ID |
| `delete_all_signals/0` | Clear all signals (dev/test only) |

#### Snapshots
| Function | Description |
|----------|-------------|
| `create_snapshots/0` | Create snapshots for all active signals if changed |
| `create_snapshot_if_changed/1` | Smart deduplication - only create if state changed |
| `get_last_snapshot/1` | Get most recent snapshot for signal |
| `list_snapshots/1` | List snapshots with time range filtering |
| `get_snapshot_history/1` | Get complete snapshot history |

#### Market Status
| Function | Description |
|----------|-------------|
| `create_market_status/0` | Record current active signal count |
| `count_active_signals/0` | Count signals in top 10 |
| `get_latest_market_status/0` | Get most recent status |
| `list_market_statuses/1` | Query with time range and ordering |
| `list_market_statuses_aggregated/1` | Time-bucketed aggregation |

#### Notifications
| Function | Description |
|----------|-------------|
| `notify_new_signals/0` | Send Telegram notifications to pro/admin users |

#### Signal Prices
| Function | Description |
|----------|-------------|
| `get_unique_symbols_for_active_signals/0` | Get unique symbols from active signals for price polling |
| `link_signals_to_symbol_price/2` | Link active signals with symbol to a symbol_price record |
| `list_signals_with_prices/1` | List signals with preloaded symbol_price + CoinGecko enrichment (`cg_price_change_24h_pct`, `cg_volume_change_24h_pct`) |

#### CoinGecko Snapshots
| Function | Description |
|----------|-------------|
| `create_coingecko_snapshot/1` | Insert a point-in-time CoinGecko market row (idempotent via unique index) |
| `get_latest_coingecko_snapshot/1` | Get the most-recent snapshot for a coingecko_id |
| `get_coingecko_snapshot_at_or_before/2` | Get the most-recent snapshot at or before a given timestamp |
| `prune_coingecko_snapshots/1` | Delete snapshot rows older than the given cutoff (used by CoinGeckoPoller) |

### Related Modules

| Module | Purpose |
|--------|---------|
| `CoinscanApiClient` | CoinScanX API integration |
| `CoinGeckoApiClient` | CoinGecko `/coins/markets` integration (paged top-500 fetch) |
| `SnapshotPoller` | GenServer that snapshots reactively on Poller fingerprint changes |
| `MarketStatusPoller` | GenServer for market status polling |
| `SignalPricePoller` | GenServer fetching live prices for signals |
| `CoinGeckoPoller` | GenServer with own 15-min timer: refreshes `coingecko_snapshots`, maintains symbol→coingecko_id cache, prunes 48h+ rows, broadcasts on `signals:updated` |

### PubSub Topics
- `"signals:updated"` - Broadcast on signal changes
- `"signal_snapshots:{signal_id}"` - Broadcast on new snapshots
- `"market_status:updated"` - Broadcast on status changes

### Key Behaviors
- **Upsert strategy**: Immutable fields preserved, mutable fields updated
- **Reactive snapshots**: `SnapshotPoller` writes rows in response to `Signals.Poller`'s `{:poller_status_updated, _}` broadcast, not on a timer. No broadcast = no rows.
- **Grace period**: Signals remain active 24 hours after exiting top 10
- **Upstream fingerprint fields** (driven by `Signals.Poller.@fingerprint_fields`): `symbol`, `position`, `in_top`, `in_top_since`, `exit_date`, `max_price_usd`, `max_increase_percentage`, `current_volume_24h`

---

## Telegram Client

**Location:** `lib/coin_tracker/telegram_client/`

Generic Telegram bot integration (message delivery only).

### Modules

#### TelegramService
High-level service for Telegram operations.

| Function | Description |
|----------|-------------|
| `generate_deeplink/1` | Generate registration deeplink with one-time token |
| `register_chat/2` | Link Telegram chat to user account |
| `list_positions/1` | Get formatted position list by chat_id |
| `get_market_status/1` | Get market status message by chat_id |
| `get_top_coins/0` | Get top 10 coins with entry time |
| `broadcast_message/2` | Send message to multiple users |

#### Telegram
Low-level HTTP client for Telegram Bot API.

### Key Architectural Decision
TelegramService is **generic** - it only sends messages. Business logic for "who to notify, when" belongs in the caller (Signals, Trading contexts). See `docs/context-vs-orchestration.md` for details.

---

## Data Model Diagram

```
User
├── has_one: TelegramUser (chat_id)
├── has_one: UserSettings (locale)
└── has_many: Positions

SymbolPrice (exchange + symbol_pair)
└── has_many: Positions

Position
├── belongs_to: User
├── belongs_to: SymbolPrice
└── tracks: P&L, alert thresholds, closure history

Signal (independent, no user association)
├── belongs_to: SymbolPrice (optional, for live prices)
└── has_many: SignalSnapshots

MarketStatus (independent aggregate)
```

---

## Background Processes

| Process | Interval | Purpose |
|---------|----------|---------|
| `PricePoller` | 5 seconds | Fetch prices for positions, check alerts, auto-close |
| `SignalPricePoller` | 5 seconds | Fetch live prices for signals (exchange fallback) |
| `SnapshotPoller` | Reactive (Poller fingerprint flips) | Create signal snapshots when ingestion has moved data |
| `MarketStatusPoller` | Reactive (Poller fingerprint flips) | Record active signal counts when ingestion has moved data |
| `CoinGeckoPoller` | 15 minutes | Refresh top-500 CoinGecko snapshots, maintain symbol cache for ingestion, prune 48h+ rows |

See `docs/context-vs-orchestration.md` for the philosophy on separating business logic (contexts) from infrastructure orchestration (pollers).

---

## Common Patterns

### PubSub Broadcasting
All contexts broadcast changes via Phoenix.PubSub:
```elixir
Phoenix.PubSub.broadcast(CoinTracker.PubSub, "topic", {:event, payload})
```

### Decimal Arithmetic
All monetary/price values use `Decimal`:
```elixir
Decimal.sub(current_price, entry_price)
|> Decimal.div(entry_price)
|> Decimal.mult(100)
```

### Authorization via Scope
User-scoped queries always filter by user_id:
```elixir
def get_position_for_user(%Scope{user: user}, position_id) do
  Position
  |> where(user_id: ^user.id, id: ^position_id)
  |> Repo.one()
end
```
