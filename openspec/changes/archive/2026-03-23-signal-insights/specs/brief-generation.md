# Spec: Brief Generation

## Capability

Generate plain-English (and Spanish) coin briefs from structured signal + enrichment data using Claude Sonnet 4.6 via
the `req_llm` library.

## Requirements

### LLM Client via req_llm

- Add `{:req_llm, "~> 1.7"}` to mix.exs dependencies
- `req_llm` is built on Req (already in deps) and handles all Anthropic API wire format
- No raw HTTP calls, no manual header management, no hand-rolled JSON parsing
- No GenServer needed — `req_llm` is stateless function calls, invoked from the EnrichmentPoller
- Model: `anthropic:claude-sonnet-4-6`
- Max tokens: 4096 (briefs are ~1500 tokens for both languages; Sonnet 4.6 supports up to 64K)

Configuration:

```elixir
# runtime.exs
config :req_llm,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")

# test.exs
config :req_llm,
  anthropic_api_key: "test-key"
```

### Prompt Caching

Prompt caching is crucial for cost efficiency. The system prompt is identical across all signal
enrichments in a cycle (~10 calls). Without caching, we pay full input price for the system
prompt on every call. With caching:

- **First call**: Cache WRITE at 1.25x input price ($3.75/MTok)
- **Remaining 9 calls**: Cache READ at 0.1x input price ($0.30/MTok) — 90% discount
- **Default TTL**: 5 minutes (free) — sufficient since all calls in a cycle run back-to-back

Implementation via `req_llm` provider options:

```elixir
ReqLLM.generate_text(
  "anthropic:claude-sonnet-4-6",
  messages,
  max_tokens: 4096,
  temperature: 0.7,
  provider_options: [
    anthropic_prompt_cache: true
  ]
)
```

The system prompt must be structured as a content block (not a plain string) for caching to work.
`req_llm` handles this automatically when `anthropic_prompt_cache: true` is set.

### Prompt Design

System prompt defines:

- **Tone**: Bold — opinionated, conditional, actionable
- **Volume priority**: Volume is the most important indicator. Analyze it first, most prominently. Without volume,
  nothing else matters.
- **Two volume stories**: CoinScanX entry volume vs current (signal validity) + CoinGecko absolute volume and vol/mcap
  ratio (market reality)
- **Audience**: Non-crypto-experts. No jargon without explanation. Conversational but informative.
- **Honesty**: If data looks bad, say so clearly
- **Not financial advice**: Frame as "this data suggests..." not "you should buy..."
- **Output format**: JSON with `en` and `es` keys, each containing `tldr`, `volume_analysis`, `full_analysis`,
  `disclaimer`
- **Spanish**: Natural Spanish, not a robotic translation. Written as if the analyst speaks Spanish natively.

User message contains structured JSON with all available data:

- From CoinScanX signal: symbol, name, rank, entry price, current price, price change %, max increase %, initial volume,
  current volume, volume change since signal %
- From CoinGecko enrichment: market cap, rank, 24h volume, vol/mcap ratio, circulating supply %, FDV/mcap ratio, ATH
  distance %, ATH date, exchange count, category, 1h/24h/7d price changes

### Brief Structure

Each language produces:

| Field             | Content                                                                                                                                                              |
|-------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `tldr`            | 2-4 sentences. Opens with a bold verdict phrase. Explains why. Mentions the main risk.                                                                               |
| `volume_analysis` | 3-5 sentences. Explains volume at signal entry vs now. Explains absolute 24h volume. Contextualizes with vol/mcap ratio. Explains what this means in plain language. |
| `full_analysis`   | 4-8 sentences. Covers market cap context, supply/dilution risk, exchange liquidity, ATH context, category context. Each point explained for a non-expert.            |
| `disclaimer`      | Standard disclaimer in natural language. Not legalese.                                                                                                               |

### Generation Trigger

- Briefs are generated after enrichment data is fetched/updated
- One API call per signal (not batched — each coin needs its own analysis)
- Both languages generated in a single API call
- Generated briefs stored in `signal_enrichments.brief_en` and `brief_es`
- `brief_generated_at` timestamp updated
- Two trigger paths:
  - **Event-driven**: new signal appears without enrichment → enrich + generate brief immediately
  - **Refresh**: every 30 min → re-enrich existing signals + regenerate briefs

### Error Handling

- If Anthropic API returns an error: log it, keep previous brief (if any), retry next cycle
- If response JSON is malformed: log the raw response, keep previous brief, retry next cycle
- If API is unreachable: skip brief generation, raw metrics still available in UI

## Constraints

- Never call LLM from LiveView processes — always pre-computed via EnrichmentPoller
- Never generate briefs without enrichment data (CoinGecko must succeed first)
- Brief generation is idempotent — regenerating with same data produces a new brief (that's fine, it's a feature not a
  bug — language models add natural variety)
- Prompt caching must be enabled on all brief generation calls
- Cost ceiling: ~10 top signals * ~2000 tokens * 48 refresh cycles/day + ~10 event-driven/day ≈ ~970K tokens/day
  at Sonnet 4.6 pricing ($3/MTok input, $15/MTok output). With prompt caching, effective input cost drops ~80%.
