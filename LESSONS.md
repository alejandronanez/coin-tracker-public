# Learning Journal

This is an append-only log of lessons learned while building CoinTracker. Each entry captures insights from bugs, architectural decisions, and framework quirks that are worth remembering.

---

## 2026-03-25: Binance market buy `executedQty` is gross, not net of fees

Context: OCO sell orders were failing with "Insufficient balance" immediately after a successful market buy.

Binance's market buy response includes `executedQty` which is the **gross** quantity purchased. However, unless the user pays fees with BNB, the trading commission is deducted from the base asset (the tokens bought). So the user actually holds `executedQty - sum(commissions)` tokens. Trying to sell the full `executedQty` in the OCO order fails because those tokens don't exist in the account.

Additionally, after subtracting commissions, the resulting quantity may not be a valid multiple of the symbol's LOT_SIZE `step_size`. Quantities must be rounded down (floored) to step_size before placing any sell order.

**Fix:** Parse the `fills` array, sum commissions where `commissionAsset` matches the base asset, subtract from `executedQty`, and floor-round to `step_size` before OCO placement.

**Why this matters:** Always check whether exchange API quantities are gross or net of fees. The Binance `fills` array contains `commission` and `commissionAsset` fields that must be accounted for. This is a common gotcha when chaining buy -> sell orders.

---

## 2026-04-11: `<.button class="...">` cannot override default variant colors

Context: The History link on `/positions` rendered as an empty black box next to "Add Position". The template did `<.button class="bg-zinc-100 ... text-zinc-900 dark:text-white">History</.button>`, expecting a light-gray secondary button.

The `<.button>` core component (core_components.ex:105) always concatenates its default variant classes (`bg-zinc-900 text-white ... dark:bg-zinc-100 dark:text-zinc-900`) with the caller's `class`. Both ended up in the element's `class` attribute. The gotcha: **HTML class-attribute order does not determine CSS specificity — source order in the compiled Tailwind stylesheet does.** Tailwind emits utilities roughly sorted by shade within a color, so `bg-zinc-900` is defined after `bg-zinc-100` and `text-zinc-900` after `text-white`. Result in light mode: dark bg + dark text → an invisible black button. The "Add Position" button had the same conflict but kept `text-white` in both sets, so its label stayed legible and masked the bug.

**Fix:** Don't wrap `<.button>` for link-styled buttons with heavy custom styling. Use `<.link navigate={...} class="inline-flex ...">` directly (same pattern as the "Edit Position" link lower in the file). That bypasses the component's default variant entirely.

**Why this matters:** Whenever a component "merges" caller classes by concatenation, overriding colors/spacing relies entirely on Tailwind's CSS source order — which is an implementation detail, not an API. Either the component must strip conflicting defaults (an opinionated merge) or consumers should avoid the component when they need to override its variant. Prefer the latter unless you want to add a real class-merge utility. When debugging "my Tailwind override isn't winning", check the compiled CSS order, not the HTML class order.

---

## 2026-04-14: Pro/free data-source pairs must return identically shaped maps

Context: Adding a `has_recently_exited` field to `Signals.list_unique_symbols/0` (pro) for a new filter tab. The free user path uses `list_unique_symbols_public/0`, and the LiveView's `assign_counts/3` runs `Enum.count(all_symbols, & &1.has_recently_exited)` for every user — pro or free — because counts are used for the shared counter chrome.

The bug that almost shipped: `& &1.has_recently_exited` uses map dot-access, which raises `KeyError` when the key is missing. Since `list_unique_symbols_public/0` didn't include the new key, free users would have crashed on mount. Dot-access is stricter than `Map.get/2` (which returns `nil`), so adding a field to only one of the two functions is a latent bug.

**Fix:** Add the key to `list_unique_symbols_public/0` too, set to a sensible default (`false`, since public users never see recently-exited signals by construction — the `where: s.exit_date <= ^cutoff` clause already excludes them).

**Why this matters:** When a LiveView has a `fetch_x(true)` / `fetch_x(false)` pair for pro/free data, the two functions are effectively part of the same interface. Any field added to one must exist in the other (with a safe default), or every downstream consumer needs defensive `Map.get/3` access. Prefer keeping the shapes identical — it's a smaller change surface than auditing every consumer. Same principle applies to any paired query used in shared code paths (e.g. `get_all_occurrences/1` vs `get_all_occurrences_public/1`).

---

## 2026-04-14: `bool_or` aggregates don't mean "the group belongs to this bucket"

Context: The `/historical` "Recently Exited" tab was listing symbols that were still Active — e.g. "0G" showed up with a green Active badge right inside the Recently Exited filter.

The root cause was the aggregate used for the flag: `has_recently_exited: bool_or(active = false AND exit_date IS NOT NULL AND exit_date >= cutoff)`. That tells us "does this symbol have *at least one* recently-exited signal?" — which is true for any symbol that cycled in/out within the window, even if it's currently active again. The UI treated the flag as a mutually-exclusive bucket label, so Active symbols leaked into Recently Exited.

**Fix:** Keep the aggregate semantics, but narrow the filter to `has_recently_exited AND not has_active`. Also exposed `last_exit_date: max(exit_date)` to sort the bucket by most-recent exit (alphabetical was the default `order_by`, which made the freshest exits hard to find).

**Why this matters:** `bool_or` / `bool_and` aggregates answer a per-group *existential* question. If the consumer wants a *status* ("this symbol is currently in Recently Exited"), existential flags alone are not enough — they must be combined with a mutual-exclusion predicate (`and not has_active`). When adding tabs/buckets that look mutually exclusive in the UI, always model the mutual exclusion explicitly in the filter, not just in the per-row flag.


---

## 2026-04-18: Sunsetting the AI signal brief — when the prompt forbids the product

Context: We shipped a Claude-generated "signal insights" brief on the signal detail page (prompt in `lib/coin_tracker/signals/brief_generator.ex`, three-card UI on the show page, backed by a CoinGecko enrichment pipeline). The feature felt like padding — "AI-for-AI's-sake".

Root cause wasn't prompt quality. The system prompt explicitly said *"Frame as 'the data shows...' not 'you should buy...'"* and required a `disclaimer` field on every response. It also mandated three sections (tldr, volume_analysis, full_analysis) that each restated numbers already visible in the Quick Facts grid rendered directly below them. So the model was structurally forbidden from giving a directional call *and* asked to paraphrase data that was already on screen — the two things that could have justified an AI layer.

Decision: sunset the entire stack — BriefGenerator, EnrichmentPoller, MappingRefresher, CoinGeckoClient, CoinGeckoMapping schema, SignalEnrichment schema, `:signal_insights` feature flag, `req_llm` dep, plus the Insights/Quick-Facts UI. Kept the signal detail page's In Top Since card, Performance Metrics (Pro), Previous Occurrences, and charts.

**Why this matters:** Before adding an AI layer, sanity-check whether the prompt is allowed to produce the value the product promises. If the guardrails needed for legal/reputational safety cancel the reason users would read it ("should I buy or not?"), the feature is a wash — either accept the stance and commit to it, or don't ship the layer. Also: DB rows for the sunset feature (`signal_enrichments`, `coin_gecko_mappings`) were left in place intentionally; schema and code are gone, so they're orphan tables to be dropped with a dedicated migration when ready.


---

## 2026-04-26: A Repo.update doesn't update the struct you passed in

Context: Users reported duplicate Telegram alerts — getting both "🚀 Crossed X% profit" AND "🔄 Position recovered to positive!" for a single price tick. The `PositionAlert` module had a 30-second throttle keyed off `position.last_alerted_at` that was supposed to prevent exactly this.

Root cause was orchestration, not pure logic. In `PricePoller.check_non_critical_alerts/3`, the same in-memory `position` struct was passed through three sequential alert checks (positive → recovery → proximity). When the positive check fired, it called `Trading.update_position_alert_state(position, …, now)` — which writes `last_alerted_at = now` **to the database** but returns a *new* struct that the caller discarded. The recovery check then read `position.last_alerted_at` from the original (stale) struct, saw `nil`, and the throttle waved it through. Two Telegram messages went out, one observable price event.

**Fix:** rebind `position` to the freshly-returned struct after every DB update so downstream throttle reads see post-write state, AND short-circuit later alert checks once any alert has fired in the same tick (one observation = one notification).

**Why this matters:** Ecto's `Repo.update` returns `{:ok, updated_struct}` for a reason — the input struct is immutable, and `change/2 |> Repo.update/1` does not mutate it in place. Whenever a function does multiple writes that future reads in the same scope depend on, you must either (a) thread the returned struct through the pipeline or (b) re-fetch from the DB. Discarding the return value and re-reading from the original struct is silently buggy: the DB and your local view of "the same record" diverge for the rest of the function. This pattern is especially dangerous around throttle/dedup logic, where the bug only manifests when *two things happen close together* — exactly the scenario the throttle exists to handle, so the bug is invisible in the common case and only surfaces under the conditions the feature was designed for.

---

## 2026-04-26: Watchlist — symbol-matching beats foreign keys when the upstream identity is unstable

Context: Building the watchlist feature meant linking a `Trading.Position` (e.g. holding ETH/USDT) to the `Signals.Signal` row that describes ETH's current top-10 standing. The obvious move was an `entry_signal_id` FK on `Position` set at create time, plus a `current_signal_id` updated on each ingestion.

Why we didn't: `Signal` rows are not stable identities for a coin. The schema is unique on `[symbol, in_top_since]`, so every re-entry into the top 10 creates a *new* `Signal` row. An FK captured on Tuesday would point at the Tuesday occurrence; by Friday, that occurrence is exited and a fresh Friday occurrence has its own ID. Either we'd chase the FK forward on every re-entry (extra writes, locking, edge cases) or the watchlist would silently render stale "in top" status because it's still pointing at the previous, now-exited signal.

Decision: join by base symbol (`ETH`) at read time. The position stores `entry_rank :integer` (the rank-at-create-time, immutable) and nothing else from the signal. The new `CoinTracker.Watchlist` orchestration module batches `Signals.current_signals_for(symbols)` over the active position list. No FK, no triggers, no chasing.

The trade-off: a coverage metric becomes mandatory. With no FK, a typo or upstream symbol-format change ("ETH" vs "ETH-USD" vs "WETH") would silently render every position as `:never_in_top` with no error, no migration, no alarm. So `Watchlist.coverage_ratio/0` runs on every PubSub broadcast and logs `watchlist.coverage ratio=...`. A drop below ~0.7 in production logs is the early-warning signal that base-symbol parsing diverged from the signal feed — the only escape hatch we have without a feature flag.

Why this matters: when the upstream feed treats a logical entity as a series of episodes (signal occurrences), an FK on the local side bakes in episode-IDs as if they were entity-IDs. Match on the entity natural key (the symbol) at read time, and pay for it with a coverage metric instead of with FK chasing. The asymmetry of corrupted data (silent emptiness vs loud error) is the part to design around — bake observability into the join itself.

---

## 2026-04-26: Derive status from the timestamp, not the flag the cron flips

Context: Watchlist messaging follow-up to PR #207. We needed to distinguish three "out of top 10" states on a position card: in grace period (within 24h of `exit_date`), past grace, and never-in-top. Day-one approach was the obvious one: trust `signals.active` — `true` while in grace, `false` once `deactivate_expired_signals/0` flipped it after 24h.

The catch: that flag is owned by a periodic job. The job runs on an interval; if it's late, lagging, or wedged, signals stay `active: true` past their 24-hour deadline. The UI would then keep showing "Grace period — dropped 30h ago" until the cron caught up — a copy that's plainly wrong to a user reading a clock.

Fix: compute the status from `exit_date` directly. `grace_end = DateTime.add(exit_date, 24, :hour)`; if it's past `now`, the row is `:exited` regardless of what `active` says. The cron still does its job (it's what lets `current_signals_for/1` stay cheap by pruning the active set), but the watchlist's view of reality no longer waits on it.

Same shape showed up on the read side. To distinguish "never tracked" from "tracked, grace ended", the watchlist needs deactivated signals too, so we added a sibling `Signals.latest_signals_for/1` that doesn't filter on `active`. We deliberately did *not* repurpose `current_signals_for/1` — its other caller (`Watchlist.coverage_ratio/0`) genuinely cares about the active set. Two callers, two semantics, two functions.

Why this matters: any time a boolean is maintained by a scheduled process, it's an eventually-consistent cache of a derivable fact. If the user-visible truth is "more than 24h have passed", read the timestamp. Reserve the flag for the things it's actually authoritative on (cheap query filtering, write-side invariants). Bonus: the test for the "cron hasn't run yet" case is one of the most useful regressions to lock in, because the bug only surfaces under timing skew you don't usually see in dev.

---

## 2026-04-26: Two correlated IDs disambiguate "we sent it twice" from "we generated it twice"

Context: Telegram users kept seeing the same notification arrive twice. Logs showed two `Sent ... alert for position N` lines with no way to tell whether ExGram had retried our single send or whether two independent code paths had each produced and sent the alert. Same outward symptom; completely different root causes.

The trick: emit **two** correlated IDs at the single chokepoint (`TelegramService.send_message/3`):

- `fingerprint` — deterministic, derived from `sha256("#{user_id}|#{message_body}")`. Same `(user, body)` always hashes to the same value.
- `dispatch_id` — a fresh UUID generated **inside** the chokepoint on every invocation.

The two together make the duplicate's source legible without any extra instrumentation:

| Pattern | Diagnosis |
|---|---|
| Same `fingerprint` + same `dispatch_id` on >1 line | Wire-level / retry duplicate (one source send, multiple deliveries) |
| Same `fingerprint` + different `dispatch_id` | Two independent source generations (two code paths each generated and sent it) |
| Different `fingerprint` for an apparently-identical alert | Body drift (e.g. an embedded timestamp that shouldn't be there) |

To make the same disambiguation visible **inside Telegram itself** (the place where the user actually notices the duplicate), the same two IDs are appended to the outgoing message body as a small footer (`· fp:abc123 · id:9f3e2a`), gated by a feature flag so it can be turned off in production once debugging is done. This means a user reporting "I got this twice" can screenshot both messages and the diagnosis is right there.

Paired with an in-memory `DuplicateDetector` GenServer (ETS table keyed by `{user_id, fingerprint}` with a 60-second window), the same fingerprint observed twice in the window emits a `Log.warn` immediately — no grep session required, the duplicate alarm fires the instant it happens.

Why this matters: "is this the same event or two events?" is one of the most common debugging questions in any system that fans out (notifications, webhooks, cache invalidation, retries). A single ID can't answer it — you need one ID that's stable across logically-equivalent events plus one that's unique per call. The pattern generalizes far beyond Telegram. Cost is trivial (one hash, one UUID, four log fields), and the cost is paid in proportion to volume — pure debugging signal, no behavioral change to the success path.

---

---

## 2026-04-26: Expose change-detection as a broadcast and downstream consumers come for free

Context: PR #206 added a fingerprint to `Signals.Poller` so identical CoinScanX top-10 responses skip the ingestion pipeline. Crucially, when the fingerprint flips, the Poller broadcasts `{:poller_status_updated, _}` on `"poller:status"` — originally just so admin UIs could render the status. `SnapshotPoller` was still writing N rows per active signal every 5 minutes regardless of whether ingestion had moved anything.

Fix: `SnapshotPoller` subscribes to that same topic on init and keeps a `dirty?` flag. Every status broadcast flips it to `true`; every tick checks it — if dirty, snapshot and clear; if not, skip. Zero new fingerprint logic, no schema change, no per-row diffing. The Poller's existing contract — *"if the top 10 didn't move, the grace period didn't either"* — is the entire dedup mechanism for the snapshot table too.

Why this matters: when you build a change-detection primitive, the temptation is to keep it as an internal optimization (a `cond` in the producer). Exposing it as a broadcast costs almost nothing extra and turns it into a building block: any downstream "did anything change?" consumer (snapshot writers, cache invalidators, audit logs, alerters) can subscribe and gate its own work on the same signal, with no coupling to the producer's internals. Coalescing falls out for free — N broadcasts between two ticks still produces one round of work, because the flag is a flag, not a counter.

Two design notes worth remembering:
- **Subscribe regardless of `enabled`.** The `SnapshotPoller` subscribes in `init` even when `enabled: false` (test config). Otherwise the dedup signal is unreachable in the exact environment where you want to test the dedup. The sync-call alternative (`Poller.get_status/0`) couples test setup to the Poller's lifecycle and crashes when the Poller isn't started.
- **Initial flag = `true`.** First tick after BEAM start always writes a baseline. Without it, a fresh process would never snapshot until the first ingestion change, which on a quiet market might be many minutes.

---

## 2026-04-27: Drop the timer once you have a reactive trigger

Context: First pass at snapshot dedup (PR before this one) kept `SnapshotPoller`'s 5-minute timer and added a `dirty?` flag flipped by `{:poller_status_updated, _}` broadcasts. Tick fired → checked flag → snapshotted or skipped. Worked, but the design carried two unrelated concerns: *when to evaluate* (timer) and *whether the underlying data changed* (broadcast). The follow-up requirement — "snapshot the exact moment we know we have a new fingerprint" — exposed the seam.

Refactor: deleted the timer. `SnapshotPoller` now subscribes to `Poller.status_topic/0` in `init/1` and calls `Signals.create_snapshots/0` directly inside `handle_info({:poller_status_updated, _}, _)`. No `dirty?` flag, no `interval` config, no `Process.send_after`. The GenServer's whole job is "translate one PubSub event into one DB write round."

What that fix made obvious in retrospect:

- **Coalescing was an artifact, not a feature.** With a timer, three broadcasts between two ticks collapsed into one snapshot — that "coalescing" was sold as a benefit, but it was just a side-effect of evaluating on a fixed cadence. Pure-reactive produces three rounds for three broadcasts, which is correct: each broadcast is a real upstream change worth capturing.
- **Initial-state hacks evaporate.** The `dirty?: true` initial value existed solely so the first tick after BEAM start would write a baseline. Pure-reactive doesn't need it — `Signals.Poller`'s first poll always changes the fingerprint (`nil → x`), broadcasts, and the reactive handler writes the baseline. The startup-baseline concern moved from inside `SnapshotPoller` to "subscribe before the broadcast can fire," which is solved once in `application.ex` by ordering `SnapshotPoller` before `Signals.Poller`.
- **The `:enabled` flag stopped being load-bearing.** With a timer, `enabled: false` meant "don't start scheduling." Without one, there's nothing to disable — the flag is kept only for config-file backward compatibility. Tests that want to suppress snapshots configure `Signals.Poller, enabled: false` instead, so no broadcasts fire.
- **Sync barriers replace `Process.sleep`.** With ticks driving everything, tests had to `Process.sleep(200)` to wait for the next tick. With reactive handlers, every test's barrier is `:sys.get_state(SnapshotPoller)` — that sync call lands in the mailbox strictly after any `cast`/`info` we just sent, so when it returns the work is done. Faster, deterministic, no sleeps.

Why this matters: when you bolt a reactive trigger onto a timed loop, the loop becomes vestigial — keeping it adds two failure modes (early eval before the broadcast lands, late eval long after the broadcast) that don't exist in pure-reactive code. Whenever the producer of a "did anything change?" signal is reliable enough to drive the consumer directly (Phoenix.PubSub on a single node qualifies), prefer eliminating the consumer's clock entirely. The clock was load-bearing only as long as the change-detection wasn't.

---

## 2026-05-02: Adding a return shape to a public API requires a caller audit — pattern matches over open atom unions are not exhaustive

Context: PR #212 added `{:ok, :suppressed}` as a fourth return shape to `TelegramService.send_message/3` so the cluster-wide dispatch-claim could tell callers "another node already sent this." The service itself was fully tested for the new shape. But `PricePoller.send_alert_message/4` still pattern-matched on only the original three shapes (`{:ok, :sent}`, `{:error, _}`, `:ok`). On the very first clustered duplicate after the deploy, the unmatched return raised `CaseClauseError` and crashed the GenServer.

The crash itself wasn't the worst part. The top-level supervisor uses `:one_for_one` with the default `max_restarts: 3 / 5s`, and the crashing alert condition was deterministic — every restart re-hit the same suppressed dispatch in well under a second. Within ~1 second of the first crash, `max_restarts` tripped and **the entire supervisor died, taking the whole BEAM with it**. So a one-line missing-clause bug in a leaf callback became "production keeps cycling and the app halts."

The compiler can't catch this. Pattern matches over open atom/tuple unions like `{:ok, :sent} | {:ok, :suppressed} | {:error, _} | :ok` are exhaustive at compile-time only if the language can enumerate every constructor — and Elixir/Erlang can never close such a union, because any module can return any atom. So `case` blocks happily compile against a stale set of expected shapes and crash at runtime the first time a new one shows up.

Two practical defenses:

1. **Caller audit when you change a return contract.** Any time a function's return adds a new tag, do `grep -rn "Module\.fn_name(\|Module\.fn_name "` for every caller, and verify each `case`/`with` either matches the new tag or has a deliberate catch-all. Update the docstring to list every shape (the `TelegramService` docstring did list all four — the bug was a caller that didn't read it). Treat this as part of the change, not as follow-up.

2. **Prefer explicit clauses over catch-all `_ ->` in callers.** A catch-all silently absorbs *future* return shapes too, so the next API addition reaches production untested. Explicit clauses crash a single test instead of all of production. The "loud crash on unknown shape" property is a feature — the bug here was that the loud crash happened in the wrong layer (production GenServer) instead of the right one (CI test). Making clauses explicit moves it to CI.

Bonus observation about supervisor blast radius: a single buggy line is a nuisance when it crashes once a minute, and a catastrophe when it crashes every 200 ms because `max_restarts` (default `3 / 5s`) was designed for *transient* faults. Always reason about crash *cadence*, not just crash *existence*. If a crash is deterministic on the input that triggered it, the restart loop is tight by definition and will exhaust `max_restarts` near-instantly.

---

## 2026-05-05: Discriminator on an existing schema vs new schema — when "polluting" the table is the right call

Context: shipping a "watch this signal" feature so users get top-10 entry/exit and surge milestone Telegram alerts without holding a real position. Two designs were on the table: (A) a fresh `signal_watches` schema decoupled from positions, with its own surge detector and recipient query, or (C) `Position.kind = :tracked | :watched` plus a new `Trading.watch_signal/2` that sets `entry_price = signal.initial_price_usd` and leaves `amount_invested / stop_loss_percent / take_profit_percent` nil.

We chose (C). The reason is that the alert pipeline was already symbol-keyed end-to-end: the price poller fans out per `symbol_price`, and `Trading.list_user_ids_with_active_position_for_symbol/1` is the single recipient query for top-10 transitions. Reusing those paths cost one new field and three guards (`kind: :watched` early-return in the alert flow that needs `stop_loss_percent` / `take_profit_percent`). The clean (A) design would have required a parallel poller subscription, a parallel recipient query, and a duplicate of the milestone-step math — for behaviour that is already structurally identical (compare current price to a baseline, fire on each step crossed).

The cost we paid for sharing: every existing positions query needed an explicit `where: p.kind == :tracked` filter so that watches don't leak into "Active positions", "Closed positions", PnL aggregates, or the `/positions` Telegram listing. We deliberately *did not* filter `list_user_ids_with_active_position_for_symbol/1`, because that query exists precisely to feed the alert fan-out — the discriminator's whole point is that it's invisible there.

The general lesson: a discriminator on an existing schema is the right call when (1) the new variant's *behaviour* is a strict subset or strict superset of the existing variant's behaviour at the layers you're reusing, and (2) the queries that need to filter the discriminator are few and easy to enumerate. Both held here. The trap is when only condition (1) holds — e.g. you reuse the alert pipeline but the new variant has different visibility rules everywhere — and you end up sprinkling `where: kind == :tracked` across dozens of call sites with no single owner. At that point a separate schema is cheaper despite the pipeline duplication. The audit-cost of the filter-everywhere pattern grows linearly with caller count and silently; new code added later won't know it has to filter.

Concrete tactical note: when adding a discriminator, grep `from .* in <Schema>` and `Repo.all/Repo.one` calls in the relevant context and audit *every* one before merging. The compiler will not help you here. The PR description should list the queries you audited; future-you will thank present-you when adding a third `kind` value years later.

## 2026-05-17: Derived pollers should subscribe upstream, not run on independent timers

`MarketStatusPoller` was running every 10 minutes on its own `Process.send_after` loop, recording a `MarketStatus` row each tick. The count it records (`active: true AND in_top: true`) is derived entirely from data that `Signals.Poller` ingests from CoinScanX every 45s — and `Signals.Poller` already broadcasts `{:poller_status_updated, status}` on `Poller.status_topic()` **only when its top-10 fingerprint actually changes**. So the 10-minute timer was guaranteed to record duplicate counts between fingerprint changes: the only way the count can move is if the upstream fingerprint moved, and the upstream is already signalling that event.

The fix was to make `MarketStatusPoller` subscribe to `Poller.status_topic()` (mirroring what `SnapshotPoller` already does) and drop the timer. One initial capture at boot via `send(self(), :initial_capture)` preserves the baseline row used by the Telegram transition check on the very first real event.

The general lesson: when a poller's output is a pure function of another poller's input, it should not have its own clock. Inheriting the upstream's "data actually changed" signal is both more efficient and more correct — periodic re-records cause `updated_at` churn, redundant alert comparisons, and noise in downstream PubSub. The shape to look for is "this GenServer wakes up, reads from the DB, derives something the upstream already had information about." If that's true, subscribe instead of poll. `SnapshotPoller` was already the model; we just hadn't aligned `MarketStatusPoller` to it.

Watch out for the `init/1` blocking trap when adopting this pattern: the very first capture (the boot baseline) does a DB query and possibly a Telegram broadcast. Don't run it synchronously inside `init/1` — that blocks the supervisor. Defer it with `send(self(), :initial_capture)` and a corresponding `handle_info/2` clause so `init/1` returns immediately and supervision proceeds.

## 2026-05-17: Defensive shims become bugs when the upstream source improves; let nil propagate so COALESCE can guard the upsert

Context: grace-period signals (recently-exited top-10 coins) were showing stale `current_volume_24h` in the UI. The CoinScanX `/v3/periodo-gracia` endpoint started returning `volumen24h` for these signals, but our `Signals.upsert_signal/1` had an explicit `CASE WHEN EXCLUDED.in_top = true THEN EXCLUDED.current_volume_24h ELSE ?.current_volume_24h END` guard that *preserved* the existing value for any signal not in the top 10. That guard was correct when the grace endpoint didn't carry volume — preserving last-known-good was better than zeroing. Once the API started providing fresh volume, the guard was actively wrong: every grace-period signal was frozen at the value it had when it dropped out of top 10.

The first lesson: a defensive shim for a missing-data limitation rots into a bug the moment the underlying source gets richer. The code keeps doing exactly what it says, just no longer what you want. Whenever you write "preserve existing if upstream can't provide this," leave a marker (a `# TODO: revisit when API returns X`, or even just a comment naming the limitation) so a future reader knows the shim has an expiry condition tied to an external system.

The second lesson is about how to remove the shim safely. The naive fix — drop the CASE and always trust `EXCLUDED.current_volume_24h` — has a quiet failure mode: our parser was defaulting a missing `volumen24h` to `Decimal.new(0)`. A transient API regression that drops the field for one response would write `0` to every grace-period row, fingerprint as a real change (because `current_volume_24h` is in `Signals.Poller.@fingerprint_fields`), mint snapshots saying "volume = 0", and broadcast "−100% vol" through the UI. Irreversible noise.

The fix that respects both concerns: let `nil` propagate from the parser ("the API said nothing") rather than coercing to `0` ("the API said zero"), and use `COALESCE(EXCLUDED.current_volume_24h, ?.current_volume_24h)` in the upsert so a `nil` from EXCLUDED preserves the existing value while a real number (including a legitimate `0`) overwrites it. This is the same "first non-null wins" pattern used to keep `initial_volume_24h` immutable, applied here as a safety net rather than as immutability.

The general principle is wider than this one fix: let `nil` mean "no information" all the way through your pipeline. If the parser collapses missing/null into a sentinel real value at the boundary, every layer below loses the ability to distinguish "we have data" from "we have no data," and you end up writing defensive code at the wrong layer or, worse, writing wrong data. `COALESCE(EXCLUDED.x, table.x)` is the canonical Postgres idiom for "upsert that doesn't clobber with NULL" — keep it handy whenever an upstream source has partial schemas.

## 2026-05-22: Reusing a 24h-sliding metric as a short-window signal

Context: adding volume-surge watch-mode alerts. We wanted a "volume in the last hour" signal to catch pre-pump activity, but the only volume figure we ingest (CoinScanX `current_volume_24h`, refreshed ~45s) is a 24-hour sliding window — by construction, it integrates over the last day, not the last hour.

The seductive move would be to add a new field (call it `current_volume_1h`) and start ingesting/storing it: a second API call, a second column, a second baseline. That gives "true 1h volume" but at the cost of every layer touching it — schema, fingerprint, snapshot, UI. The cheaper move was to notice that `Δ(current_volume_24h)` over an hour already correlates strongly with the last hour's activity. If volume in the last hour jumps from $5M to $50M, the 24h figure mechanically reflects most of that gain (the only deduction is whatever volume rolled off from 25h-ago to 24h-ago, typically a small slice of a normal day's activity).

We accepted the noise. The plan calls the actual quantity `(volume_in_last_hour) − (volume_25-to-24h-ago)` and pegs tier thresholds conservatively (10/25/50% growth over 60 min) so the signal-to-noise ratio stays reasonable. The whole feature reuses `current_volume_24h` plus the existing snapshot history (no new column, no new exchange call), and the only added schema is two `last_alerted_volume_*_tier` columns on `positions` for state tracking.

The lesson is about when to bend an existing metric versus when to add a new one. A 24h-sliding figure used as a "delta over 1h" signal is *biased* (slightly under-sensitive due to the 25h-ago rolloff) but not *broken*. For an alert system whose thresholds are tunable from one place, bias you can characterize and document is fine — you tune around it. The cost-benefit only flips if you need the metric to be *precise* (e.g., displayed to users as "volume in the last hour"), at which point a real 1h field becomes worth its weight in plumbing. Default to bending what's already there; pay the schema cost only when the bend stops being characterizable.

---

## 2026-07-05: opencode has no declarative Stop hook — but `session.idle` + `client.session.prompt` is the equivalent

Context: we wanted deterministic in-flow verification (run `mix format --check-formatted && mix compile --warning-as-errors` when the agent claims "done", re-prompt it with the errors if they fail). Claude Code has a declarative `Stop` hook in `settings.json`. We assumed opencode had the same. It does not.

The published config schema (`https://opencode.ai/config.json`) has no `hooks` field at all — only `permission`, `plugin`, `experimental`, etc. opencode hard-fails on unknown top-level keys, so a declarative hook is not available. The only lifecycle interception is the **plugin** system (a `.ts`/`.js` file in `.opencode/plugins/`, auto-loaded by Bun).

The plugin event bus is where the equivalent lives. Two primitives combine into a blocking Stop hook:

1. `session.idle` event (`EventSessionIdle = { type: "session.idle", properties: { sessionID } }`) — fires when the agent's turn completes. The opencode equivalent of Claude Code's `Stop`.
2. `client.session.prompt({ path: { id: sid }, body: { parts: [{ type: "text", text }] } })` — re-prompts the session with a new user message, which re-activates the agent with the message in context. The SDK doc explicitly notes `noReply: true` is "useful for plugins" for context-only injection; `noReply: false` (default) triggers a real assistant turn.

So a plugin that catches `session.idle`, runs the checks via Bun's `$` shell, and on failure calls `client.session.prompt()` with the error output, achieves the same "block turn-end and force the agent to fix" semantics as Claude Code's Stop hook. The `opencode-goal-plugin` ("auto-continues until complete") confirms the re-prompt-on-idle pattern is production-viable.

Three gotchas, each non-obvious:

- **`file.edited` has no `sessionID`.** The obvious event for "did this session edit anything" is `file.edited`, but its payload is just `{ file: string }` — no session linkage. Use `session.diff` instead (`{ properties: { sessionID, diff: [...] } }`), which fires when a session produces file diffs and carries the sessionID. This also gives plan-mode exemption for free: the plan agent has `edit: deny`, so no `session.diff` ever fires, so no checks run, so no re-prompt.
- **Re-entrancy.** Calling `client.session.prompt()` from inside the `session.idle` handler starts a new turn that will eventually fire its own `session.idle`. Defer the prompt with `queueMicrotask` so the idle handler returns first, and cap retries per session (we use 3) to prevent infinite fix-fail loops burning tokens. Above the cap, toast a warning and let it idle — human intervenes.
- **An undocumented `experimental.hook.session_completed` field exists in the generated SDK types** (`types.gen.ts`) but is absent from the published `config.json` schema. It looks like a declarative "run this command on session completion" hook — exactly what we wanted. We did not use it because (a) the schema discrepancy means it may be rejected at startup with `ConfigInvalidError`, and (b) it's unclear whether its output feeds back to the agent or is just a notification. Worth revisiting once it appears in the published schema and docs.

Why this matters: "the agent doesn't reliably run verification" is a real complaint, but the fix is not more prose in AGENTS.md (non-deterministic) nor a git hook alone (fires at commit, too late for the agent to course-correct mid-task). The fix is a turn-end gate that feeds errors back into the same context the agent is working in. opencode doesn't ship that gate as a config field, but the plugin primitives are sufficient to build it in ~60 lines of TypeScript. Layer with a git pre-push hook (full `mix precommit`) as the tool-agnostic backstop, and CI as the final gate.
