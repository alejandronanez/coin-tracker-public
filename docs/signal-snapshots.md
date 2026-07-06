# Signal Snapshots

This document explains how signal snapshots work - automatic historical tracking of signal state for analysis and auditing.

## Overview

The `SnapshotPoller` GenServer writes a fresh round of snapshots reactively, the moment the upstream `Signals.Poller` reports a new top-10 fingerprint. There is no internal timer — the row count on `signal_snapshots` grows in lockstep with real ingestion changes, and never otherwise. Unlike market status (which captures aggregate counts), signal snapshots track individual signal metrics over time, including the current price from the exchange.

## Snapshots vs Real-Time Signal Data

**Important distinction:** Snapshots are historical records captured at upstream-change time. They are NOT suitable for displaying "current" state in the UI.

| Use Case | Data Source | Why |
|----------|-------------|-----|
| **Current stats (position, price, volume)** | `Signal` struct fields | Updated in real-time by pollers |
| **Historical charts & trends** | `SignalSnapshot` records | Point-in-time captures for analysis |
| **"In Top Since" / "Exit Date"** | `Signal.in_top_since`, `Signal.exit_date` | Authoritative timestamps on the signal |

### Signal Real-Time Fields

The `Signal` schema has these fields updated in real-time:

```elixir
# Updated by SignalPricePoller and signal ingestion
field :current_price_usd, :decimal
field :current_volume_24h, :decimal
field :position, :integer
field :in_top, :boolean
field :in_top_since, :utc_datetime  # When first entered top 10
field :exit_date, :utc_datetime      # When exited top 10 (if out)
```

### When to Use Each

```elixir
# For displaying current state in LiveView:
@signal.position           # Current ranking
@signal.current_price_usd  # Live price
@signal.in_top_since       # Entry timestamp
Signal.volume_increase_percentage(@signal)  # Current volume %

# For charts and historical analysis:
Signals.get_snapshot_history(signal.id)  # Returns list of snapshots
```

The signal detail page (`SignalLive.Show`) uses:
- **Signal fields** for the "Current Stats" section (real-time)
- **Snapshots** for historical charts (price, volume, position over time)

## What Gets Captured

Each snapshot records the state of a single signal at a point in time:

| Field | Description |
|-------|-------------|
| `signal_id` | Foreign key to the parent signal |
| `snapshot_at` | UTC timestamp when captured |
| `symbol` | Cryptocurrency symbol (e.g., "BTC", "ETH") |
| `current_volume_24h` | 24-hour trading volume |
| `initial_volume_24h` | Volume when signal was first detected |
| `max_price_usd` | Highest price reached |
| `current_price_usd` | Live price at snapshot time (from exchange) |
| `in_top` | Whether signal is in top 10 |
| `position` | Ranking position (1-10 or null) |

## Reactive trigger

Snapshots are driven entirely by the fingerprint that `Signals.Poller`
introduced in PR #206 to skip redundant ingestion. The chain:

1. `Signals.Poller` polls CoinScanX every ~45s. When the top-10 fingerprint
   changes, it ingests data and broadcasts `{:poller_status_updated, status}`
   on the `"poller:status"` PubSub topic.
2. `SnapshotPoller` subscribes to that topic on `init/1` and writes one
   snapshot per active signal **inside the broadcast handler** — there is no
   internal timer, no `dirty?` flag, no batching.

The Poller's own contract holds: *"if the top 10 didn't move, the grace
period didn't either."* So when the Poller is silent, no signal data has
moved and there is nothing to capture. When the Poller broadcasts, ingestion
has just rewritten data and the snapshot fires immediately.

`SnapshotPoller` is started **before** `Signals.Poller` in
`lib/coin_tracker/application.ex` so its subscription is in place before the
Poller's first poll can broadcast.

## Architecture

```
Signals.Poller (every ~45s)
    ↓ fingerprint changed?
    ├─ no  → skip ingestion, stay silent
    └─ yes → ingest, then broadcast {:poller_status_updated, _}
                                     on "poller:status"
                                            ↓
                              SnapshotPoller.handle_info/2
                                            ↓
                              Signals.create_snapshots()
                                ↓ For each active signal:
                              Signals.create_snapshot_for_signal(signal)
                                ↓ Create new SignalSnapshot
                                ↓ Broadcast on PubSub: "signal_snapshots:{signal_id}"
```

## Configuration

```elixir
# config/dev.exs and config/prod.exs
config :coin_tracker, CoinTracker.Signals.SnapshotPoller, enabled: true

# config/test.exs - disabled
config :coin_tracker, CoinTracker.Signals.SnapshotPoller, enabled: false
```

The `:enabled` flag is kept for config compatibility but is effectively a
no-op now that there is no timer to disable. To stop snapshots in tests,
configure `Signals.Poller, enabled: false` so no broadcasts fire (this is
already the case in `config/test.exs`).

## Key Files

| File | Purpose |
|------|---------|
| `lib/coin_tracker/signals/snapshot_poller.ex` | GenServer that triggers snapshots |
| `lib/coin_tracker/signals/signal_snapshot.ex` | Ecto schema |
| `lib/coin_tracker/signals.ex` | Context functions |

## Database Schema

```elixir
schema "signal_snapshots" do
  belongs_to :signal, Signal

  field :snapshot_at, :utc_datetime
  field :symbol, :string
  field :current_volume_24h, :decimal
  field :initial_volume_24h, :decimal
  field :max_price_usd, :decimal
  field :current_price_usd, :decimal
  field :in_top, :boolean
  field :position, :integer

  timestamps(type: :utc_datetime)
end
```

**Indexes:**
- `signal_id`
- `snapshot_at`
- Composite `(signal_id, snapshot_at)`

**Foreign Key:** `signal_id → signals.id` with `on_delete: :delete_all`

## API

### GenServer API

```elixir
# Start the poller (called by Application supervisor)
SnapshotPoller.start_link(opts)

# Manually trigger snapshot for all active signals
SnapshotPoller.snapshot_now()
```

### Context Functions (Signals)

```elixir
# Create snapshots for all active signals
Signals.create_snapshots()
# => {:ok, 5}  # 5 snapshots created

# Create snapshot for single signal
Signals.create_snapshot_for_signal(signal)
# => {:ok, snapshot} | {:error, changeset}

# Get the most recent snapshot for a signal
Signals.get_last_snapshot(signal_id)
# => %SignalSnapshot{} or nil

# Get all snapshots for a signal (ordered by time)
Signals.get_snapshot_history(signal_id)
# => [%SignalSnapshot{}, ...]

# List snapshots with filtering
Signals.list_snapshots(signal_id: 1, from: ~U[...], to: ~U[...])
```

## PubSub Broadcasting

On every snapshot creation, broadcasts:

```elixir
Phoenix.PubSub.broadcast(
  CoinTracker.PubSub,
  "signal_snapshots:#{snapshot.signal_id}",
  {:snapshot_created, snapshot}
)
```

**Topic pattern:** `"signal_snapshots:{signal_id}"` (signal-specific)

**Subscribers:**
- `SignalLive.Show` - Updates signal detail page in real-time

## Programmatic Usage

```elixir
# Trigger snapshot for all signals (async)
CoinTracker.Signals.SnapshotPoller.snapshot_now()

# Create snapshots directly (sync)
{:ok, count} = CoinTracker.Signals.create_snapshots()

# Get signal with its snapshots
signal = CoinTracker.Signals.get_signal(1)
history = CoinTracker.Signals.get_snapshot_history(signal.id)

# Query snapshots in time range
CoinTracker.Signals.list_snapshots(
  signal_id: 1,
  from: DateTime.add(DateTime.utc_now(), -24, :hour)
)
```

## Test Fixtures

```elixir
import CoinTracker.SignalsFixtures

# Create a signal
signal = signal_fixture(%{symbol: "BTC", in_top: true, active: true})

# Create a snapshot for that signal
snapshot = snapshot_fixture(signal, %{position: 1})

# Create signal with multiple snapshots
{signal, snapshots} = signal_with_snapshots_fixture(5)  # 5 snapshots
```

## Comparison with Market Status Poller

| Aspect | Signal Snapshots | Market Status |
|--------|------------------|---------------|
| **Granularity** | Per-signal | Aggregate count |
| **Frequency** | Reactive (on Poller fingerprint change) | Every 10 minutes |
| **PubSub Topic** | `signal_snapshots:{id}` | `market_status:updated` |
| **Use Case** | Signal history & price tracking | Market health dashboard |

## Related Documentation

- [Market Status Poller](market-status-poller.md) - Similar polling pattern for aggregate data
- [Market Status Alerts](market-status-alerts.md) - Alerts based on market status changes
