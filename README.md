# CoinTracker

> [!TIP]
> **Support the project — and get a free month.** CoinTracker is free and open
> source, but the app needs a [CoinScanX](https://coinscanx.com/?ref=WMG2XT) API
> key to fetch signals, so you'll need a CoinScanX account regardless. Sign up
> via this **referral link** and you get **one month free** — the maintainer gets
> one too. A zero-cost way to say thanks for the open-source release.

> **Docs:** **English** · [Español](README.es.md)

**Know when to buy. Know when to sell.** CoinTracker surfaces on-chain crypto
signals, tracks your positions, and pings you on Telegram when it's time to act —
so you can trade with conviction instead of FOMO.

> **Not financial advice.** CoinTracker is an open-source tool that aggregates and
> displays on-chain data and market indicators. Nothing here is investment
> advice. Do your own research; you are responsible for your own trades.

---

## Features

- **On-chain signals** — high-probability setups derived from blockchain data and
  market indicators, ingested from [CoinScanX](https://coinscanx.com/?ref=WMG2XT).
- **Position tracking** — log entries, targets, and stop-losses; see P&L at a
  glance on open and closed positions.
- **Telegram alerts** — get notified the moment a coin shows bullish activity, or
  when your positions hit thresholds/stop-loss. Market-status changes too.
- **Market status** — a rolling view of whether the market is bullish, bearish, or
  ranging, with a 30-day chart to time your strategy.
- **Historical signals** — browse every signal ever called, with entry/peak/exit
  prices. The track record is public, no signup required.
- **Exchange integration** — store your Binance API keys (encrypted at rest with
  [Cloak](https://github.com/danielberkompas/cloak)) to enable one-click trading
  from a signal.
- **Admin panel** — [Backpex](https://backpex.live)-powered dashboard for managing
  users, positions, and signals.

## Tech stack

[Elixir](https://elixir-lang.org) 1.15+ · [Phoenix](https://phoenixframework.org) 1.8 ·
[LiveView](https://hexdocs.pm/phoenix_live_view) · [Ecto](https://hexdocs.pm/ecto) /
PostgreSQL · [Tailwind CSS](https://tailwindcss.com) + [daisyUI](https://daisyui.com) ·
[Req](https://hexdocs.pm/req) (HTTP) · [ex_gram](https://hexdocs.pm/ex_gram) (Telegram) ·
[Swoosh](https://hexdocs.pm/swoosh) + [Resend](https://resend.com) (email) ·
[Bandit](https://github.com/mtrikel/bandit) webserver.

## Prerequisites

- **Elixir 1.15+** (verified on 1.19.5 / OTP 28) and **Erlang/OTP** — check with
  `elixir --version`
- **PostgreSQL 15+** — easiest via Docker (see Quick start)
- **Node.js 18+** (verified on v22) and npm (for JS asset deps like Chart.js)
- **Mix** (ships with Elixir)

## Quick start

```bash
# 1. Clone and enter the repo
git clone <your-fork-url> coin_tracker
cd coin_tracker

# 2. Start a Postgres instance (dev on :5432, test on :5433)
docker compose up -d

# 3. Copy the env template and generate the two crypto secrets
cp .env.example .env
mix phx.gen.secret            # -> paste into SECRET_KEY_BASE
mix phx.gen.secret 32         # -> paste into LIVE_VIEW_SIGNING_SALT

# 4. Load the env into your shell (do this in every new terminal)
set -a; source .env; set +a

# 5. Install deps, JS deps, create + migrate the DB, build assets
mix setup

# 6. Boot the server
mix phx.server
```

Now visit **http://localhost:4000**. You should see the landing page. Click
**Get Started** to register an account and start tracking positions.

> The `mix setup` alias runs `deps.get`, `npm install` (in `assets/`), `ecto.setup`
> (create + migrate + seed), and `assets.setup`/`assets.build`. The seeds populate
> 30 days of synthetic market-status data so the chart isn't empty.

### Don't have Docker?

Any PostgreSQL 15+ instance works. The dev config
(`config/dev.exs`) connects to `postgres:postgres@localhost:5432/coin_tracker_dev`,
and test uses `localhost:5433/coin_tracker_test`. Point those at your own server,
or override `DATABASE_URL` in `.env` and adjust `config/dev.exs` accordingly.

## New user walkthrough

The first-run experience has a few non-obvious steps. Here's what to expect,
verified by driving the app with browser automation on a fresh setup.

### 1. Registration is passwordless (magic link)

The signup form at `/users/register` asks for **email only** — no password.
After you click **Create an account**, you're redirected to the log-in page and
a confirmation email is sent. In development, Swoosh uses the local mailbox
adapter instead of a real SMTP server, so you pick up the email at
**http://localhost:4000/dev/mailbox**. Open the confirmation email, click the
magic link inside, then press **Confirm and stay logged in**. You're now
authenticated and redirected to `/upgrade`.

### 2. Most features are behind a Pro tier gate

After registering you start on the **free** tier. The router gates the two
headline features behind `require_pro_subscription`:

| Route | Access | What you see |
|-------|--------|--------------|
| `/signals`, `/signals/:id` | **Pro only** | Redirects to `/upgrade` |
| `/market-status` | **Pro only** | Redirects to `/upgrade` |
| `/admin`, `/admin/users`, `/admin/positions`, `/admin/signals` | **Admin only** (Backpex panel) | Manage users, positions, signals; flip subscription tiers |
| `/positions`, `/positions/new` | Free (auth required) | Open/closed position tracking |
| `/historical`, `/historical/:symbol` | Free (public) | Every signal ever called |
| `/tutorial` | Free (auth required) | Step-by-step getting started guide |
| `/users/settings`, `/settings/exchange-keys` | Free (auth required) | Account + Binance API key management |
| `/upgrade` | Free (public) | Pricing page (free) / subscription status (pro) |

### 3. Activating Pro for local development

The USDT TRC-20 payment system that originally upgraded users was removed for
this public release, so **there is no self-serve payment path in the UI**. Two
ways to unlock `/signals` and `/market-status` locally:

**Option A — promote yourself via the admin panel (recommended once seeded).**
The first admin must be promoted by hand (see Option B), but after that the
Backpex admin panel at `/admin/users` lets an admin flip any user's
**Subscription Tier** (Free/Pro/Admin) and **Subscription Expires At** directly
from the UI — no code needed.

**Option B — promote the first user by hand (Elixir eval).** Bootstrap the first
admin from an `iex`/`mix run` eval, then use the admin panel for everyone else:

```bash
set -a; source .env; set +a
mix run -e '
  user = CoinTracker.Repo.get_by!(CoinTracker.Accounts.User, email: "you@example.com")
  {:ok, user} = CoinTracker.Accounts.activate_admin_subscription(user)
  IO.puts("Activated #{user.subscription_tier} for #{user.email}")
'
```

For a non-admin Pro upgrade from code, use
`Accounts.activate_pro_subscription(user, expires_at)` instead. Fork operators
wiring a real payment provider should call it from their checkout handler — the
gating logic is unchanged and ready to receive a new payment source. See
`docs/contexts.md` for details.

### 4. Data provider keys are mandatory for signals

Even with Pro active, `/signals` will be **empty** without a valid
`COINSCANX_API_KEY`. The poller logs `Coinscan API request failed with status
401` on every fetch and skips ingestion. You can verify a key is valid before
wiring it in:

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $COINSCANX_API_KEY" \
  "https://api.coinscanx.com/v3/top10"
# 200 = valid, 401 = invalid/expired
```

Once a valid key is loaded, the poller ingests within ~45 seconds (the dev
interval) and `/signals` populates the Top 10 performers table with live
Binance prices and sparkline charts.

### 5. Dev mailbox for email-based flows

Any transactional email (confirmation, email change, password reset) lands in
the Swoosh dev mailbox at **http://localhost:4000/dev/mailbox**. Each email gets
its own page with the magic link inside. This is how you complete the
registration flow and any future email-confirming actions in development.

## Environment variables

This app uses **strict, environment-variable-based configuration** — there are no
secret or deployment-identity values committed to the repo, and the app
**refuses to boot** if a required variable is missing. Load `.env` into your shell
before any command that boots the app (`mix phx.server`, `mix test`, ecto tasks):

```bash
set -a; source .env; set +a
```

See [`.env.example`](.env.example) for the full list. Summary:

| Variable | Required in | Purpose |
|----------|-------------|---------|
| `SECRET_KEY_BASE` | all envs | Phoenix signing secret (`mix phx.gen.secret`) |
| `LIVE_VIEW_SIGNING_SALT` | all envs | LiveView signing salt (`mix phx.gen.secret 32`) |
| `APP_NAME` | all envs | Brand name shown in the UI and outgoing email |
| `SENDER_EMAIL` | all envs | From-address for transactional email |
| `SUPPORT_EMAIL` | all envs | Shown in the UI contact link |
| `ADMIN_NOTIFICATION_EMAIL` | all envs | Where admin alerts are sent |
| `DATABASE_URL` | prod only | Ecto repo URL (dev/test use `config/*.exs` defaults) |
| `PHX_HOST` | prod only | Public hostname for URLs/origins |
| `RESEND_API_KEY` | prod only | Resend API key for sending email |

### Required for the app to function (data providers)

> **These are not optional.** Without `COINSCANX_API_KEY` the signal poller
> errors on every fetch and `/signals` stays empty — the app boots but has no
> product. Without `COINGECKO_API_KEY` the CoinGecko client falls back to the
> anonymous endpoint, which 429s under real use and breaks live price enrichment.
> Get these set before you expect any data to flow.

| Variable | Where to get it | Notes |
|----------|-----------------|-------|
| `COINSCANX_API_KEY` | [CoinScanX](https://coinscanx.com/?ref=WMG2XT) account dashboard | Sent as a Bearer token; the whole signals pipeline depends on it |
| `COINGECKO_API_KEY` | [CoinGecko](https://www.coingecko.com) API dashboard | A free demo key works; sets the `x-cg-demo-api-key` header |

### Optional integrations (degrade gracefully if unset)

| Variable | Where to get it |
|----------|-----------------|
| `TELEGRAM_BOT_TOKEN` | Create a bot via [@BotFather](https://t.me/BotFather) on Telegram |

> **Note:** with `TELEGRAM_BOT_TOKEN` empty you'll see periodic `404` lines in the
> logs from the bot polling Telegram. That's expected — the app keeps running and
> all non-Telegram features work fine.

> **Security note (dev only):** the Tesla HTTP middleware logs full request URLs
> at `debug` level, which include the Telegram bot token in plaintext
> (`POST https://api.telegram.org/bot<TOKEN>/...`). This is dev-only
> (`config/dev.exs`) and never reaches production, but be mindful if you share
> terminal output or paste logs into issues. Lower the log level with
> `Logger.configure(level: :info)` in IEx to suppress it.

## Testing

```bash
set -a; source .env; set +a
mix test
```

The test DB lives on port **5433** (the `db-test` service in `docker-compose.yml`).
`mix test` auto-creates and migrates it. The suite runs ~940 tests.

> **Known issue:** two tests in `test/coin_tracker_web/live/upgrade_live_test.exs`
> reference a `/upgrade/payment` route that was removed when the USDT payments
> context was stripped for the public release. They fail with a
> `FunctionClauseError` rather than the expected `NoRouteError`. Safe to fix when
> you touch that area.

## Architecture

The codebase follows Phoenix **context modules** — each domain (`Accounts`,
`Coins`, `Trading`, `Signals`) owns its schemas and public API. Business logic
lives in contexts; `CoinTrackerWeb` only orchestrates and renders.

Key decisions worth reading before extending the app:

- [`docs/contexts.md`](docs/contexts.md) — full catalog of contexts, schemas, and public functions
- [`docs/context-vs-orchestration.md`](docs/context-vs-orchestration.md) — why `TelegramService` is generic and callers decide who/when
- [`docs/signal-snapshots.md`](docs/signal-snapshots.md) — signal vs snapshot data, and deduplication
- [`docs/market-status-poller.md`](docs/market-status-poller.md) — the reactive poller pattern (no internal timers)
- [`docs/telegram-alerts.md`](docs/telegram-alerts.md) — position-based threshold/stop-loss alerts
- [`docs/dev-logging.md`](docs/dev-logging.md) — structured logging conventions

The full list is in [`AGENTS.md`](AGENTS.md) under "Domain Documentation".

### Subscription tiers

There's a `free` / `pro` tier gate (`require_pro_subscription` mount, `User.active_subscription?/1`).
The USDT TRC-20 payment system that originally upgraded users was removed for this
public release. `Accounts.activate_pro_subscription/2` still exists, so fork
operators can wire their own payment provider to flip the tier — the gating logic
is unchanged. See `docs/contexts.md` for details.

## Deployment

The repo ships with a production-ready `Dockerfile` and a [`fly.toml`](fly.toml)
for [Fly.io](https://fly.io):

```bash
fly launch          # first time only, to create the app + a Postgres cluster
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret) \
                LIVE_VIEW_SIGNING_SALT=$(mix phx.gen.secret 32) \
                APP_NAME=CoinTracker \
                SENDER_EMAIL=noreply@yourdomain.com \
                SUPPORT_EMAIL=support@yourdomain.com \
                ADMIN_NOTIFICATION_EMAIL=admin@yourdomain.com \
                DATABASE_URL=... \
                PHX_HOST=yourdomain.com \
                RESEND_API_KEY=...
fly deploy
```

The release runs `/app/bin/migrate` on deploy (see `fly.toml`). For other targets,
build with `mix assets.deploy && mix release` and run `bin/coin_tracker start`.

## Contributing

- Run `mix precommit` before pushing — it compiles with `--warning-as-errors`,
  checks formatting, and runs the test suite.
- Set up the git hooks once on a fresh clone: `git config core.hooksPath .githooks`
  (this makes `git push` run `mix precommit` automatically).
- See [`AGENTS.md`](AGENTS.md) for project conventions, Elixir/Phoenix guidelines,
  and the OpenSpec change workflow used for feature proposals.

## License

Apache License 2.0 — see [`LICENSE`](LICENSE). You're free to use, modify,
distribute, and ship this commercially, with attribution. Includes an explicit
patent grant. See the license file for full terms.
