# Alert Tracking System Implementation Plan

## Overview

Implement a sophisticated alert system that triggers notifications based on price movements, with configurable thresholds per position and a 30-second global throttle to prevent alert fatigue. The system will send Telegram alerts for:
- Positive threshold crossings (milestone-based)
- Negative proximity alerts (stop-loss warning levels)
- Recovery alerts (negative to positive transition)
- Critical alerts (take-profit/stop-loss hits)

---

## System Architecture

### Current State
- **PricePoller**: Runs every 5 seconds, fetches prices, updates DB, checks for position closure
- **AlertZone**: Pure functions calculating zones and closure conditions
- **TelegramService**: Already has `send_message(user_id, message)` function
- **Database**: Positions table has `current_threshold_zone`, `highest_alert_zone_reached`, `entry_price`, `stop_loss_percent`, `take_profit_percent`

### New State
- **PricePoller**: Will additionally trigger alert checking on every price update
- **PositionAlert** (new module): Pure functions handling all alert logic
- **Trading.update_position_alerts** (new function): Updates alert tracking fields in DB
- **Position schema**: New fields for tracking alert state

---

## Database Schema Changes

### Migration: `add_alert_tracking_to_positions`

Add three new fields to `positions` table:

```elixir
add :last_alerted_threshold_positive, :decimal, precision: 5, scale: 2
  # Tracks the last positive threshold we alerted on (e.g., 2.0, 4.0, 6.0)
  # Used to detect when price crosses a new threshold upward
  # NULL = no alert sent yet

add :last_alerted_negative_proximity, :integer
  # Tracks the proximity level we last alerted on: 80, 85, 90, or 95
  # Used to detect when price enters deeper proximity to stop-loss
  # NULL = not in any proximity zone yet

add :last_alerted_at, :utc_datetime
  # Global throttle timestamp
  # Ensures max 1 alert per position per 30 seconds
  # Used for all alert types
```

### Position Schema Updates

Add fields to `Position` Ecto schema:
```elixir
field :last_alerted_threshold_positive, :decimal
field :last_alerted_negative_proximity, :integer
field :last_alerted_at, :utc_datetime
```

---

## Alert Logic Specification

### 1. Positive Threshold Alerts (Upward Price Movement)

**Purpose**: Alert user on every significant upward price movement based on configurable thresholds

**Configuration**: `current_threshold_zone` field per position (e.g., 2%, 4%, 50%)

**Algorithm**:
```
current_profit_pct = (current_price - entry_price) / entry_price * 100

# Find the highest complete threshold crossed
current_threshold = floor(current_profit_pct / step_size) * step_size

# Should alert if:
# 1. current_threshold > last_alerted_threshold_positive (new higher threshold)
# 2. OR price dropped below last threshold and came back up
# 3. AND 30 seconds have passed since last_alerted_at

should_alert =
  (current_threshold > last_alerted_threshold_positive OR
   (current_threshold >= step_size AND
    current_profit_pct > last_alerted_threshold_positive AND
    seconds_since_last_alert >= 30))
```

**Alert Message**: `"🚀 Crossed {current_threshold}% profit"`

**Examples**:
```
Position: Entry $100, Step 2%

Tick 1: Price $102 (2% profit)
  ✓ Alert: "Crossed 2% profit"
  Update: last_alerted_threshold_positive = 2.0, last_alerted_at = now

Tick 2: Price $103 (3% profit)
  ✗ No alert (still in 2% zone)
  No update

Tick 3: Price $101 (1% profit)
  ✗ No alert (price dropped)
  No update

Tick 4: Price $105 (5% profit)
  ✓ Alert: "Crossed 4% profit" (re-crossed from below, 30s passed)
  Update: last_alerted_threshold_positive = 4.0, last_alerted_at = now
```

---

### 2. Recovery Alerts (Negative → Positive Transition)

**Purpose**: Alert when position recovers from loss to profit

**Condition**: When crossing from negative profit to positive (0% crossing)

**Alert Message**: `"🔄 Position recovered to positive!"`

**Logic**:
- Trigger when `previous_pnl < 0` AND `current_pnl >= 0`
- Subject to 30-second throttle
- Can be combined with positive threshold alert if hitting 2%+ at recovery

**Implementation Note**:
- Track `last_known_pnl` (from previous tick) in PricePoller
- Detect crossing of 0% threshold
- Send recovery alert separately from threshold alert

---

### 3. Negative Proximity Alerts (Stop-Loss Warning Zones)

**Purpose**: Warn user as position approaches stop-loss level

**Configuration**: Fixed at 80%, 85%, 90%, 95% of stop_loss_percent distance

**Example with stop_loss_percent = -20%**:
```
80% proximity: -20% * 0.80 = -16%
85% proximity: -20% * 0.85 = -17%
90% proximity: -20% * 0.90 = -18%
95% proximity: -20% * 0.95 = -19%
```

**Algorithm**:
```
# Check which proximity zones current_pnl has entered
proximity_zones = [
  {80, stop_loss * 0.80},
  {85, stop_loss * 0.85},
  {90, stop_loss * 0.90},
  {95, stop_loss * 0.95}
]

crossed = Enum.filter(proximity_zones, fn {_level, threshold} ->
  current_pnl <= threshold
end)

# Get the worst (most negative) threshold
if crossed != [] do
  {worst_proximity, worst_threshold} = Enum.min_by(crossed, fn {_l, t} -> t end)

  should_alert =
    worst_threshold < last_alerted_negative_proximity AND
    seconds_since_last_alert >= 30
end
```

**Alert Message**: `"⚠️ Warning: {proximity}% toward stop-loss ({current_pnl}%)"`

**Examples**:
```
Position: Entry $100, Stop-loss -20%

Tick 1: Price $85 (-15% loss)
  ✗ No alert (not in any proximity zone)
  Update: last_alerted_negative_proximity = NULL

Tick 2: Price $83 (-17% loss)
  ✓ Alert: "⚠️ Warning: 85% toward stop-loss (-17%)"
  Update: last_alerted_negative_proximity = 85, last_alerted_at = now

Tick 3: Price $84 (-16% loss)
  ✗ No alert (recovering, less negative)
  Update: last_alerted_negative_proximity = 80 (back to 80% zone)

Tick 4: Price $82 (-18% loss)
  ✓ Alert: "⚠️ Warning: 90% toward stop-loss (-18%)" (if 30s passed)
  Update: last_alerted_negative_proximity = 90, last_alerted_at = now
```

---

### 4. Critical Alerts (Position Closure)

**Purpose**: Immediate notification when take-profit or stop-loss is hit

**Configuration**: Automatic when `current_pnl >= take_profit_percent` or `current_pnl <= stop_loss_percent`

**Special Behavior**:
- **NO 30-second throttle** - alert immediately
- **Always send** - even if one just sent
- Sent simultaneously with position closure

**Alert Messages**:
- Take-profit: `"🎯 Take-profit hit at {current_price}! Position closed."`
- Stop-loss: `"🛑 Stop-loss hit at {current_price}! Position closed."`

---

## Module Structure

### New Module: `CoinTracker.Trading.PositionAlert`

**Purpose**: Pure functions for alert checking logic. No database calls, no side effects.

**Functions**:

```elixir
# Positive threshold alerts
def check_positive_alert(position, current_pnl, now)
  -> {:alert, message, threshold} | :no_alert

# Recovery alerts
def check_recovery_alert(last_pnl, current_pnl, now, last_alerted_at)
  -> {:alert, message} | :no_alert

# Negative proximity alerts
def check_negative_proximity_alert(position, current_pnl, now)
  -> {:alert, message, proximity} | :no_alert

# Critical alerts (closure)
def check_closure_alerts(current_pnl, alert_zones)
  -> {:close, :take_profit, message} | {:close, :stop_loss, message} | :no_close

# Helper: Seconds since last alert
def seconds_since_alert(last_alerted_at)
  -> integer

# Helper: Calculate current threshold
def calculate_current_threshold(current_pnl, step_size)
  -> Decimal
```

### Updated Module: `CoinTracker.Trading`

Add functions to update position alert state:

```elixir
def update_position_last_alert(position, threshold_positive, proximity_negative, now)
  -> {:ok, Position} | {:error, Changeset}

def update_position_recovery_alert(position, now)
  -> {:ok, Position} | {:error, Changeset}
```

### Updated Module: `CoinTracker.Coins.PricePoller`

In `check_single_position_alerts/2`:
1. Calculate current PnL
2. Check closure conditions (existing logic)
3. If no closure, check alert conditions (new logic):
   - Positive threshold alerts
   - Recovery alerts
   - Negative proximity alerts
4. Send Telegram alerts if triggered
5. Update position alert tracking fields

---

## Implementation Steps

### Step 1: Database Migration
- Create migration file with three new fields
- Fields: `last_alerted_threshold_positive`, `last_alerted_negative_proximity`, `last_alerted_at`
- All fields are nullable (NULL = no alert sent yet)

### Step 2: Update Position Schema
- Add three fields to `Position` Ecto schema
- Update `changeset/2` if needed (probably not, these are auto-updated)

### Step 3: Create PositionAlert Module
- Implement pure alert checking functions
- No database calls, no side effects
- Thoroughly tested with unit tests
- Handle all edge cases (NULL values, first alert, re-crossing, etc.)

### Step 4: Update Trading Context
- Add `update_position_last_alert/4` function
- Handles updating all three tracking fields atomically
- Add `update_position_recovery_alert/2` function

### Step 5: Update PricePoller
- In `check_single_position_alerts/2`:
  - Keep existing closure checking logic
  - Add new alert checking before closure check
  - Send Telegram alerts using `TelegramService.send_message/2`
  - Update position tracking fields
- Track `last_known_pnl` for recovery alert detection

### Step 6: Test
- Unit tests for `PositionAlert` module
- Integration tests for full flow in PricePoller
- Manual testing with real positions

---

## Key Implementation Details

### 30-Second Throttle Logic

The throttle applies to all alerts EXCEPT critical closure alerts:

```elixir
def should_throttle?(last_alerted_at) do
  case last_alerted_at do
    nil -> false  # Never alerted, don't throttle
    timestamp -> DateTime.diff(DateTime.utc_now(), timestamp, :second) < 30
  end
end
```

### Handling NULL Values

All alert tracking fields start as NULL:
- `last_alerted_threshold_positive = nil` → First positive alert has no threshold to compare against
- `last_alerted_negative_proximity = nil` → Not in any negative zone yet
- `last_alerted_at = nil` → Never alerted, skip throttle check

### Alert Message Sending

Use existing `TelegramService.send_message/2`:
```elixir
TelegramService.send_message(position.user_id, "Your alert message here")
```

Returns `:ok` even if user has no Telegram linked (safe to call)

### Order of Operations in PricePoller

```
For each position:
  1. Calculate current_pnl
  2. Check closure conditions (PRIORITY)
     ├─ If take-profit hit: Close position, send critical alert, STOP
     └─ If stop-loss hit: Close position, send critical alert, STOP
  3. Check positive threshold alerts
     ├─ If triggered: Send alert, update last_alerted_threshold_positive
  4. Check recovery alerts
     ├─ If triggered: Send alert, update last_alerted_at
  5. Check negative proximity alerts
     ├─ If triggered: Send alert, update last_alerted_negative_proximity
```

---

## Edge Cases to Handle

1. **First price check with high initial profit**: Only alert on current threshold, not all thresholds below it
2. **Rapid oscillation**: 30-second throttle prevents spam
3. **Price drops below 0% then recovers**: Recovery alert should trigger once
4. **Multiple alerts in same check**: Handle ordering (closure > recovery > positive > negative)
5. **NULL tracking fields**: Treat as "first time" for that alert type
6. **Position with no stop-loss**: Skip negative proximity alerts
7. **User with no Telegram**: TelegramService returns :ok silently

---

## Testing Strategy

### Unit Tests: `test/coin_tracker/trading/position_alert_test.exs`
- Test each alert checking function independently
- Test edge cases (NULL values, threshold calculations, oscillation)
- Test 30-second throttle logic
- No database calls needed

### Integration Tests: `test/coin_tracker/coins/price_poller_test.exs`
- Test full flow: price update → alert check → Telegram send
- Test position closure with alerts
- Test multiple positions with different configurations

### Manual Testing
- Create test positions with various thresholds
- Update prices and verify alerts in Telegram
- Verify DB fields are updated correctly

---

## File Changes Summary

| File | Change | Type |
|------|--------|------|
| `priv/repo/migrations/20251106023029_add_alert_tracking_to_positions.exs` | New migration with three fields | Create |
| `lib/coin_tracker/trading/position.ex` | Add three fields to schema | Update |
| `lib/coin_tracker/trading/position_alert.ex` | New module with pure alert logic | Create |
| `lib/coin_tracker/trading.ex` | Add alert update functions | Update |
| `lib/coin_tracker/coins/price_poller.ex` | Integrate alert checking | Update |
| `test/coin_tracker/trading/position_alert_test.exs` | Unit tests for PositionAlert | Create |
| `test/coin_tracker/coins/price_poller_test.exs` | Integration tests | Update |

---

## Success Criteria

- [ ] Migration created and runnable
- [ ] All three tracking fiewds appear in positions table
- [ ] PositionAlert module passes all unit tests
- [ ] PricePoller sends alerts via Telegram
- [ ] 30-second throttle prevents alert spam
- [ ] Recovery alerts work correctly
- [ ] Negative proximity alerts work correctly
- [ ] Critical closure alerts ignore throttle
- [ ] All edge cases handled
- [ ] Integration tests pass

---

## Notes

- Use Decimal for all price/percentage calculations (already in use)
- Telegram alerts use existing TelegramService infrastructure
- Alert checking happens every 5 seconds (same as price polling)
- No new external dependencies needed
- All changes are additive (no breaking changes to existing code)

---

## Logging & Observability

All alert sending operations are logged with structured metadata for Grafana/Loki querying.

### Log Metadata Fields

| Field | Description | Example |
|-------|-------------|---------|
| `module` | Source module | `:price_poller` |
| `operation` | Operation type | `:send_alert`, `:close_position` |
| `alert_type` | Type of alert | `:threshold`, `:recovery`, `:proximity`, `:closure` |
| `position_id` | Position identifier | `123` |
| `user_id` | User identifier | `456` |
| `reason` | Error reason (failures only) | `"timeout"` |

### Log Levels

- **Success**: `Log.info` - Alert sent successfully
- **Failure**: `Log.warn` with `:telegram_error` - Telegram delivery failed
- **Critical**: `Log.critical` - Position closed but user not notified

### Grafana/Loki Queries

```logql
# All successful alerts by type
{app="coin_tracker"} | json | operation="send_alert" | alert_type="recovery"

# Failed alerts
{app="coin_tracker"} | json | operation="send_alert" | severity="medium"

# Detect duplicate alerts (>1 per position in 30s)
sum by (position_id) (
  count_over_time(
    {app="coin_tracker"} | json
    | operation="send_alert"
    | alert_type="recovery"
    [30s]
  )
) > 1

# Alert rate by type (per 5 minutes)
sum by (alert_type) (
  rate({app="coin_tracker"} | json | operation="send_alert" [5m])
)

# Alerts for specific position
{app="coin_tracker"} | json | operation="send_alert" | position_id="123"
```

### Troubleshooting Duplicates

If you see duplicate alerts:

1. Query for the specific position's alert history
2. Check if `last_alerted_at` updates are failing (look for `db_error`)
3. Verify the 30-second throttle is working (compare timestamps)
