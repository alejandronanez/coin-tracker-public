# Dev Logging Guide

This guide explains how logging works in CoinTracker development and how to
filter the output so you can actually find what you're looking for.

## How dev logs look

In development, every log line includes metadata tags before the message:

```
[info] module=signal_poller operation=ingest_top_10 Ingested 10 top-10 signals
[info] module=snapshot_poller operation=create_snapshots symbol=BTC Created snapshot for BTC
[error] module=price_poller operation=fetch_prices reason=timeout Binance API error: rate limited
```

The metadata fields you'll see:

| Tag | Meaning |
|-----|---------|
| `module=` | Which subsystem produced the log (e.g., `price_poller`, `signal_poller`) |
| `operation=` | What it was doing (e.g., `fetch_prices`, `ingest_top_10`) |
| `symbol=` | Which coin (e.g., `BTC`, `ETH`) |

## Filtering logs with grep

The metadata tags make it easy to filter the log stream. Run the server and
pipe through grep:

```bash
# Only signal poller logs
mix phx.server 2>&1 | grep module=signal_poller

# Logs for a specific coin
mix phx.server 2>&1 | grep symbol=BTC

# Only errors
mix phx.server 2>&1 | grep "\[error\]"

# Everything except debug noise
mix phx.server 2>&1 | grep -v "\[debug\]"

# Combine filters — signal-poller logs for a specific coin
mix phx.server 2>&1 | grep module=signal_poller | grep symbol=ETH
```

## Ecto SQL query filter

By default, Ecto SQL debug logs are **suppressed** in dev. These fire on every
database query and are the biggest source of noise (pollers run queries every
few seconds).

The filter is defined in `lib/coin_tracker/dev_log_filter.ex` and installed
via `config/dev.exs`. It only drops `[debug]`-level Ecto SQL logs — your own
debug logs from `CoinTracker.Log.debug/2` still come through.

To see SQL queries when you need them, use IEx (see next section).

## Interactive log control with IEx

Instead of `mix phx.server`, run with an interactive Elixir shell:

```bash
iex -S mix phx.server
```

This gives you a prompt where you can control logging at runtime:

```elixir
# Silence everything except errors (useful when you need to focus)
Logger.configure(level: :error)

# Back to normal (all log levels)
Logger.configure(level: :debug)

# Turn off the Ecto SQL filter (see database queries)
Logger.remove_handler_filter(:default, :suppress_ecto_debug)

# Turn the Ecto SQL filter back on
:logger.update_handler_config(:default, :filters, [
  suppress_ecto_debug: {&CoinTracker.DevLogFilter.filter/2, :suppress_ecto_debug}
])
```

These changes take effect immediately — no restart needed.

## Production logging

In production, logs are JSON-formatted via `LoggerJSON` and include all
metadata fields (not just the dev subset). These are queryable in Grafana/Loki:

```
# All logs from a specific module
{app="coin_tracker"} | json | module="signal_poller"

# All errors from a specific module
{app="coin_tracker"} | json | error_type="api_error" | module="price_poller"
```

## Adding new metadata fields

When you add a new metadata key to `CoinTracker.Log`, update these three places:

1. **`lib/coin_tracker/log.ex`** — add to `@allowed_metadata`
2. **`config/config.exs`** — add to the `metadata:` list in `:default_formatter`
3. **`config/prod.exs`** — add to the `metadata:` list in `LoggerJSON` formatter

If the field should also appear in dev logs, add it to `config/dev.exs` in the
`:default_formatter` metadata list. Keep this list small — only fields useful
for at-a-glance debugging.
