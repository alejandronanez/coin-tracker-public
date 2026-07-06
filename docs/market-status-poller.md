# Market Status Poller

This document explains how the `MarketStatusPoller` GenServer works — capturing market activity reactively when CoinScanX data has actually changed.

## Overview

The `MarketStatusPoller` is a GenServer that captures the count of active signals in the top 10 and persists it as a `MarketStatus` row. This data powers the `/market-status` page and triggers Telegram alerts when the market reaches or leaves full capacity.

It is **reactive, not periodic**: captures fire when `CoinTracker.Signals.Poller` broadcasts a top-10 fingerprint change, plus once at boot for an initial baseline. Between fingerprint changes the underlying counts cannot move, so no capture would add information.

## What It Captures

On every fire, the poller records:
- `active_signals_count` — Number of signals that are both `active: true` AND `in_top: true` (0-10)
- `recorded_at` — UTC timestamp when the capture was taken

## Architecture

```
Signals.Poller (every 45s, fingerprint-dedup)
    ↓ Broadcasts {:poller_status_updated, status} on Poller.status_topic()
    ↓ only when top-10 fingerprint changes
MarketStatusPoller (subscribed)
    ↓ Signals.create_market_status()
    ↓ Counts: from(s in Signal, where: s.active == true and s.in_top == true)
    ↓ Creates MarketStatus record
    ↓ Broadcasts on PubSub: "market_status:updated"
    ↓
maybe_send_market_alert(previous, current)
    ↓ Detects transitions to/from 10
    ↓ Sends Telegram alerts if transition detected
```

The same trigger drives `SnapshotPoller`. Both pollers consume the same `Poller.status_topic()` broadcast.

## Configuration

```elixir
# config/dev.exs and config/prod.exs
config :coin_tracker, CoinTracker.Signals.MarketStatusPoller, enabled: true

# config/test.exs - disabled for tests
config :coin_tracker, CoinTracker.Signals.MarketStatusPoller, enabled: false
```

**Options:**
- `:enabled` — Whether the poller subscribes and captures (default: `true`)

There is no `:interval` option. The cadence is dictated by upstream CoinScanX changes, surfaced through `Signals.Poller`. To stop captures in tests, disable this poller (or `Signals.Poller`, which stops broadcasts).

## Key Files

| File | Purpose |
|------|---------|
| `lib/coin_tracker/signals/market_status_poller.ex` | GenServer implementation |
| `lib/coin_tracker/signals/market_status.ex` | Ecto schema |
| `lib/coin_tracker/signals.ex` | Context functions (`create_market_status/0`, `list_market_statuses/1`) |
| `lib/coin_tracker/signals/poller.ex` | Source of the `:poller_status_updated` broadcast |

## Database Schema

```elixir
schema "market_statuses" do
  field :active_signals_count, :integer  # 0-10
  field :recorded_at, :utc_datetime
  timestamps(type: :utc_datetime)
end
```

**Indexes:**
- `recorded_at` — For time-based queries
- Composite index for efficient range queries

## GenServer Lifecycle

```
Application starts
    ↓
MarketStatusPoller.start_link/1
    ↓
init/1: Check if enabled via config
    ↓
If enabled:
    Phoenix.PubSub.subscribe(CoinTracker.PubSub, Poller.status_topic())
    perform_capture()   # initial baseline
    ↓
handle_info({:poller_status_updated, _status}, state)
    ↓
perform_capture() → Signals.create_market_status() + maybe alert
    ↓
Wait for next broadcast (no timer)
```

## API

### Public Functions

```elixir
# Start the GenServer (called by Application supervisor)
MarketStatusPoller.start_link(opts)

# Manually trigger a capture immediately (bypasses subscription)
MarketStatusPoller.capture_now()
```

### Context Functions (Signals)

```elixir
# Create a new market status record
Signals.create_market_status()
# => {:ok, %MarketStatus{active_signals_count: 7, recorded_at: ~U[...]}}

# Get the latest market status
Signals.get_latest_market_status()
# => %MarketStatus{} or nil

# List market statuses with optional filtering
Signals.list_market_statuses(from: ~U[2025-01-01 00:00:00Z], order_by: [desc: :recorded_at])

# Get aggregated data for UI
Signals.list_market_statuses_aggregated("today")   # Raw intervals (24h)
Signals.list_market_statuses_aggregated("week")    # Hourly averages (7d)
Signals.list_market_statuses_aggregated("month")   # 4-hour averages (30d)
```

## PubSub Broadcasting

On every successful capture, `Signals.create_market_status/0` broadcasts:

```elixir
Phoenix.PubSub.broadcast(
  CoinTracker.PubSub,
  "market_status:updated",
  {:market_status_created, market_status}
)
```

**Subscribers:**
- `MarketStatusLive.Index` — Updates the market status page in real-time

## Alert Integration

After capturing, the poller checks for market transitions and sends alerts:

```elixir
defp perform_capture do
  previous_status = Signals.get_latest_market_status()

  case Signals.create_market_status() do
    {:ok, market_status} ->
      maybe_send_market_alert(previous_status, market_status)
    {:error, changeset} ->
      Log.db_error("Failed to capture market status", ...)
  end
end
```

See [Market Status Alerts](market-status-alerts.md) for details on alert triggering.

## Programmatic Usage

```elixir
# Trigger immediate capture (async)
CoinTracker.Signals.MarketStatusPoller.capture_now()

# Create market status directly (sync)
{:ok, status} = CoinTracker.Signals.create_market_status()

# Query recent history
CoinTracker.Signals.list_market_statuses(
  from: DateTime.add(DateTime.utc_now(), -24, :hour),
  order_by: [desc: :recorded_at]
)
```

## UI Integration

The `/market-status` page (pro users only) displays:
1. **Current Status Card** — Real-time active signal count with health indicator
2. **Historical Trend Chart** — ApexCharts line chart with configurable time ranges
3. **Time Period Selector** — Today (raw), Week (hourly avg), Month (4-hour avg)

The page subscribes to PubSub and updates automatically when new data arrives.

## Testing

The poller is disabled in test environment. To test:

```elixir
# Create market status fixtures
import CoinTracker.SignalsFixtures
market_status_fixture(%{active_signals_count: 7})

# Test aggregation
statuses = Signals.list_market_statuses_aggregated("today")
```

## Related Documentation

- [Market Status Alerts](market-status-alerts.md) — Telegram alerts for market transitions
- [Signal Snapshots](signal-snapshots.md) — Same reactive trigger, different payload
