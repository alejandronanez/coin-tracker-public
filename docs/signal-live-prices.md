# Signal Live Prices

This document explains how real-time price fetching works for signals on the signals page.

## Overview

Signals come from the CoinScanX API and are **exchange-agnostic** - they contain a symbol (e.g., "ETH") but no exchange information. To display current prices, we need to fetch prices from crypto exchanges. The `SignalPricePoller` GenServer handles this by trying multiple exchanges in priority order until it finds a price.

## The Challenge

Unlike positions (which have a specific exchange association), signals don't know which exchange lists them. A symbol might:
- Be available on Binance but not Bitget
- Be available on MEXC but not Binance
- Not be available on any exchange (rare, but possible)

## Architecture

```
SignalPricePoller (GenServer)
    ↓ Every 5 seconds (configurable)
get_unique_symbols_for_active_signals()
    ↓ Returns ["ETH", "BTC", "SOL", ...]
    ↓
For each symbol:
    ↓
try_exchanges([:binance_spot, :bitget_spot, :mexc_spot], "ETH/USDT")
    ↓ Try Binance first
    ↓ If not found, try Bitget
    ↓ If not found, try MEXC
    ↓ If all fail, return :not_found
    ↓
If price found:
    ↓
Coins.upsert_symbol_price()
    ↓ Creates/updates SymbolPrice record
    ↓ Broadcasts on PubSub: "price_updates"
    ↓
Signals.link_signals_to_symbol_price(symbol, symbol_price_id)
    ↓ Updates all active signals with that symbol to point to the SymbolPrice
    ↓
LiveView receives {:price_updated, symbol_price}
    ↓ Updates UI in real-time
```

## Exchange Fallback Strategy

The poller tries exchanges in this priority order:

1. **Binance** (`:binance_spot`) - Largest exchange, most likely to have the symbol
2. **Bitget** (`:bitget_spot`) - Second attempt
3. **MEXC** (`:mexc_spot`) - Third attempt, often has newer/smaller coins

```elixir
@exchange_priority [:binance_spot, :bitget_spot, :mexc_spot]

defp try_exchanges([], _symbol_pair), do: :not_found

defp try_exchanges([exchange | rest], symbol_pair) do
  case PriceClient.fetch_current_prices(exchange, [symbol_pair]) do
    {:ok, [price_data | _]} ->
      {:ok, exchange, price_data.price}

    {:ok, []} ->
      # No price returned, try next exchange
      try_exchanges(rest, symbol_pair)

    {:error, _} ->
      # API/network error, try next exchange
      try_exchanges(rest, symbol_pair)
  end
end
```

**Behavior:**
- Stops at the first exchange that returns a valid price
- "Symbol not found" errors are expected and logged at debug level (not error)
- Network errors cause fallback to next exchange
- Returns `:not_found` if all exchanges fail

## Configuration

```elixir
# config/dev.exs or config/runtime.exs
config :coin_tracker, CoinTracker.Signals.SignalPricePoller,
  enabled: true,
  interval: :timer.seconds(5)

# config/test.exs - disabled for tests
config :coin_tracker, CoinTracker.Signals.SignalPricePoller,
  enabled: false
```

**Options:**
- `:enabled` - Whether polling is active (default: `true`)
- `:interval` - Polling interval in milliseconds (default: `5_000` = 5 seconds)

## Key Files

| File | Purpose |
|------|---------|
| `lib/coin_tracker/signals/signal_price_poller.ex` | GenServer that polls for prices |
| `lib/coin_tracker/signals/signal.ex` | Signal schema with `belongs_to :symbol_price` |
| `lib/coin_tracker/signals.ex` | Context functions for price linking |
| `lib/coin_tracker/coins/exchanges/binance.ex` | Binance API adapter |
| `lib/coin_tracker/coins/exchanges/bitget.ex` | Bitget API adapter |
| `lib/coin_tracker/coins/exchanges/mexc.ex` | MEXC API adapter |
| `lib/coin_tracker_web/live/signal_live/index.ex` | LiveView that displays prices |

## Database Schema

### Signal Association

```elixir
# lib/coin_tracker/signals/signal.ex
schema "signals" do
  # ... existing fields ...
  belongs_to :symbol_price, CoinTracker.Coins.SymbolPrice
end
```

### Migration

```elixir
# priv/repo/migrations/20251225230734_add_symbol_price_id_to_signals.exs
def change do
  alter table(:signals) do
    add :symbol_price_id, references(:symbol_prices, on_delete: :nilify_all)
  end

  create index(:signals, [:symbol_price_id])
end
```

**Key points:**
- `on_delete: :nilify_all` - If a SymbolPrice is deleted, signals keep their data but lose the price link
- Index on `symbol_price_id` for efficient joins

## GenServer Lifecycle

```
Application starts
    ↓
SignalPricePoller.start_link/1
    ↓
init/1: Check if enabled via config
    ↓
If enabled: send(self(), :poll) - immediate first poll
    ↓
handle_info(:poll, state)
    ↓
perform_poll() → For each unique symbol, try exchanges
    ↓
Process.send_after(self(), :poll, interval)
    ↓
Loop continues every interval
```

## API

### SignalPricePoller Functions

```elixir
# Start the GenServer (called by Application supervisor)
SignalPricePoller.start_link(opts)

# Manually trigger a poll immediately (async)
SignalPricePoller.poll_now()
```

### Signals Context Functions

```elixir
# Get unique symbols from active signals
Signals.get_unique_symbols_for_active_signals()
# => ["ETH", "BTC", "SOL"]

# Link all active signals with symbol to a symbol_price
Signals.link_signals_to_symbol_price("ETH", 123)
# => {2, nil}  # Returns {count_updated, nil}

# List signals with preloaded symbol_price (for UI)
Signals.list_signals_with_prices(active: true)
# => [%Signal{symbol_price: %SymbolPrice{current_price: #Decimal<2000.00>}}, ...]
```

## PubSub Broadcasting

The `Coins.upsert_symbol_price/1` function automatically broadcasts price updates:

```elixir
Phoenix.PubSub.broadcast(
  CoinTracker.PubSub,
  "price_updates",
  {:price_updated, symbol_price}
)
```

**Subscribers:**
- `SignalLive.Index` - Updates signal prices in real-time
- `PositionLive.Index` - Updates position prices (existing functionality)

## LiveView Integration

### Subscription

```elixir
# lib/coin_tracker_web/live/signal_live/index.ex
def mount(_params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(CoinTracker.PubSub, "signals:updated")
    Phoenix.PubSub.subscribe(CoinTracker.PubSub, "price_updates")
  end
  # ...
end
```

### Handling Price Updates

```elixir
@impl true
def handle_info({:price_updated, symbol_price}, socket) do
  # Update signals that match this symbol_price
  updated_signals =
    Enum.map(socket.assigns.signals, fn signal ->
      if signal.symbol_price_id == symbol_price.id do
        %{signal | symbol_price: symbol_price}
      else
        signal
      end
    end)

  # Re-sort and re-assign
  {:noreply,
   socket
   |> assign(:signals, updated_signals)
   |> assign(:top_performers, sort_top_performers(updated_signals, socket.assigns.sort_by))
   |> assign(:grace_period, sort_grace_period(updated_signals, socket.assigns.grace_sort_by))}
end
```

### Loading Signals with Prices

```elixir
defp load_signals(socket) do
  # Use list_signals_with_prices instead of list_signals
  signals = Signals.list_signals_with_prices(active: true)
  # ... sort and assign ...
end
```

## UI Display

### Desktop View

```heex
<!-- Current Price column -->
<div class="text-right">
  <%= if coin.symbol_price do %>
    <div class="font-mono text-sm font-medium text-zinc-900 dark:text-white">
      ${format_price.(coin.symbol_price.current_price)}
    </div>
    <div class="text-[10px] text-green-500 dark:text-green-400">
      <span class="inline-flex items-center gap-1">
        <!-- Pulsing green dot indicator -->
        <span class="relative flex h-1.5 w-1.5">
          <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
          <span class="relative inline-flex rounded-full h-1.5 w-1.5 bg-green-500"></span>
        </span>
        {gettext("Live")}
      </span>
    </div>
  <% else %>
    <span class="text-xs text-zinc-400 dark:text-zinc-500">
      {gettext("N/A")}
    </span>
  <% end %>
</div>
```

**Display logic:**
- If `symbol_price` exists: Show price with pulsing green "Live" indicator
- If `symbol_price` is nil: Show "N/A" in muted text

## Error Handling and Logging

### Log Levels

The exchange modules differentiate between expected "symbol not found" errors and actual errors:

```elixir
# Expected: Symbol doesn't exist on this exchange
# Log level: DEBUG (won't clutter browser console)
if message == "Invalid symbol." do
  Log.debug("Binance: symbol not found", ...)
else
  # Unexpected: Rate limiting, network issues, etc.
  # Log level: ERROR
  Log.api_error("Binance API error: #{message}", ...)
end
```

**Why this matters:**
- In development, Phoenix sends server-side error logs to browser console
- "Invalid symbol" is expected during exchange fallback, not a real error
- Using debug level keeps the console clean while still logging for debugging

### Error Patterns by Exchange

| Exchange | "Not Found" Response | Detection |
|----------|---------------------|-----------|
| Binance | HTTP 400, `"msg": "Invalid symbol."` | Exact match on message |
| Bitget | HTTP 200, `"code": != "00000"` | Message contains "symbol", "not exist", or "invalid" |
| MEXC | HTTP 200, `"code": != success` | Message contains "symbol", "not exist", or "invalid" |

## Price Isolation Between Positions and Signals

A common concern: "If I create a position on MEXC, but the SignalPricePoller finds the price on Binance, will my position show the wrong price?"

**No.** Prices are correctly isolated due to the composite unique constraint on `SymbolPrice`.

### How It Works

The `SymbolPrice` schema has a unique constraint on `[:exchange, :symbol_pair]`:

```elixir
# lib/coin_tracker/coins/symbol_price.ex
|> unique_constraint([:exchange, :symbol_pair])
```

This means each exchange/symbol combination is a **separate record**:

| Exchange | Symbol Pair | SymbolPrice ID |
|----------|-------------|----------------|
| `mexc_spot` | `ETH/USDT` | 123 |
| `binance_spot` | `ETH/USDT` | 456 |
| `bitget_spot` | `ETH/USDT` | 789 |

### Data Flow

**Positions** (exchange is known at creation):
1. User creates position on MEXC for ETH
2. `Trading.create_position/3` fetches price **from MEXC specifically**
3. Creates/updates SymbolPrice for `mexc_spot + ETH/USDT` (ID 123)
4. Position links to ID 123

**Signals** (exchange is unknown):
1. SignalPricePoller gets symbol "ETH" from active signals
2. Tries Binance first, finds price
3. Creates/updates SymbolPrice for `binance_spot + ETH/USDT` (ID 456)
4. Signal links to ID 456

**Result:** Position uses MEXC prices (ID 123), Signal uses Binance prices (ID 456). They never cross-contaminate.

### Price Updates

The Position PricePoller knows which exchange to query because it reads from the position's linked SymbolPrice:

```elixir
# lib/coin_tracker/trading.ex
def get_symbol_prices_by_exchange_for_active_positions do
  # Returns: %{mexc_spot: ["ETH/USDT"], binance_spot: ["BTC/USDT"]}
  # Each position's exchange is preserved
end
```

Each poller updates only its specific SymbolPrice record. The PubSub broadcast includes the full `symbol_price` struct, and LiveViews only update entities that match `symbol_price.id`.

## Relationship to Position PricePoller

| Aspect | Position PricePoller | Signal PricePoller |
|--------|---------------------|-------------------|
| Data source | Position has `symbol_price_id` FK | Signal gets linked after price fetch |
| Exchange | Known from position's symbol_price | Unknown, tries fallback |
| Purpose | P&L calculation, alerts | Display current price |
| Interval | 5 seconds | 5 seconds |
| PubSub topic | `"price_updates"` | `"price_updates"` (shared) |

Both pollers write to the same `SymbolPrice` **table** but to **different records** (keyed by exchange + symbol_pair). They broadcast on the same PubSub topic, and each LiveView filters updates by `symbol_price.id` to update only matching entities.

## Testing

The poller is disabled in test environment. Test the context functions directly:

```elixir
# test/coin_tracker/signals/signal_price_poller_test.exs

describe "get_unique_symbols_for_active_signals/0" do
  test "returns unique symbols from active signals" do
    signal_fixture(%{symbol: "ETH", active: true, in_top_since: ~U[2025-01-01 00:00:00Z]})
    signal_fixture(%{symbol: "BTC", active: true, in_top_since: ~U[2025-01-02 00:00:00Z]})
    signal_fixture(%{symbol: "ETH", active: true, in_top_since: ~U[2025-01-03 00:00:00Z]})

    symbols = Signals.get_unique_symbols_for_active_signals()

    assert length(symbols) == 2
    assert "ETH" in symbols
    assert "BTC" in symbols
  end
end

describe "link_signals_to_symbol_price/2" do
  test "links all active signals with matching symbol to symbol_price" do
    signal1 = signal_fixture(%{symbol: "ETH", active: true})
    signal2 = signal_fixture(%{symbol: "ETH", active: true})

    {:ok, symbol_price} = Coins.upsert_symbol_price(%{
      exchange: :binance_spot,
      symbol_pair: "ETH/USDT",
      current_price: Decimal.new("2000.00")
    })

    {count, _} = Signals.link_signals_to_symbol_price("ETH", symbol_price.id)

    assert count == 2
  end
end

describe "list_signals_with_prices/1" do
  test "returns signals with preloaded symbol_price" do
    {:ok, symbol_price} = Coins.upsert_symbol_price(%{...})
    signal = signal_fixture(%{symbol: "ETH", active: true})
    Signals.link_signals_to_symbol_price("ETH", symbol_price.id)

    [loaded_signal] = Signals.list_signals_with_prices(active: true)

    assert loaded_signal.symbol_price != nil
    assert loaded_signal.symbol_price.id == symbol_price.id
  end
end
```

## Programmatic Usage

```elixir
# Trigger immediate poll (async)
CoinTracker.Signals.SignalPricePoller.poll_now()

# Get signals with current prices
signals = CoinTracker.Signals.list_signals_with_prices(active: true)

for signal <- signals do
  if signal.symbol_price do
    IO.puts("#{signal.symbol}: $#{signal.symbol_price.current_price}")
  else
    IO.puts("#{signal.symbol}: N/A")
  end
end

# Manually link a signal to a price (usually done by poller)
{:ok, symbol_price} = CoinTracker.Coins.upsert_symbol_price(%{
  exchange: :binance_spot,
  symbol_pair: "ETH/USDT",
  current_price: Decimal.new("2000.00")
})
CoinTracker.Signals.link_signals_to_symbol_price("ETH", symbol_price.id)
```

## Related Documentation

- [Contexts Reference](contexts.md) - Overview of all Phoenix contexts
- [Market Status Poller](market-status-poller.md) - Similar GenServer pattern
- [Signal Snapshots](signal-snapshots.md) - Snapshot polling pattern
- [Context vs Orchestration](context-vs-orchestration.md) - Architecture philosophy
