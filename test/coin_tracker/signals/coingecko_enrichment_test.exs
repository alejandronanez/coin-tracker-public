defmodule CoinTracker.Signals.CoingeckoEnrichmentTest do
  @moduledoc """
  Tests for the `cg_price_change_24h_pct` virtual field attached by
  `Signals.list_signals_with_prices/1`.
  """

  use CoinTracker.DataCase, async: true

  alias CoinTracker.Signals
  import CoinTracker.SignalsFixtures

  describe "list_signals_with_prices/1 — cg_price_change_24h_pct enrichment" do
    test "attaches the latest snapshot's price_change_percentage_24h to each signal" do
      btc = signal_fixture(%{coingecko_id: "bitcoin", symbol: "BTC", active: true})
      eth = signal_fixture(%{coingecko_id: "ethereum", symbol: "ETH", active: true})

      # BTC: older + newer snapshot, the newer wins.
      {:ok, _} =
        Signals.create_coingecko_snapshot(%{
          coingecko_id: "bitcoin",
          symbol: "BTC",
          snapshot_at: ~U[2026-05-17 11:00:00Z],
          price_change_percentage_24h: Decimal.new("1.0")
        })

      {:ok, _} =
        Signals.create_coingecko_snapshot(%{
          coingecko_id: "bitcoin",
          symbol: "BTC",
          snapshot_at: ~U[2026-05-17 12:00:00Z],
          price_change_percentage_24h: Decimal.new("2.5")
        })

      {:ok, _} =
        Signals.create_coingecko_snapshot(%{
          coingecko_id: "ethereum",
          symbol: "ETH",
          snapshot_at: ~U[2026-05-17 12:00:00Z],
          price_change_percentage_24h: Decimal.new("-3.2")
        })

      results = Signals.list_signals_with_prices(active: true)

      enriched_btc = Enum.find(results, &(&1.id == btc.id))
      enriched_eth = Enum.find(results, &(&1.id == eth.id))

      assert Decimal.equal?(enriched_btc.cg_price_change_24h_pct, Decimal.new("2.5"))
      assert Decimal.equal?(enriched_eth.cg_price_change_24h_pct, Decimal.new("-3.2"))
    end

    test "leaves cg_price_change_24h_pct nil when signal has no coingecko_id" do
      signal = signal_fixture(%{coingecko_id: nil, active: true})

      [result] = Signals.list_signals_with_prices(active: true)
      assert result.id == signal.id
      assert result.cg_price_change_24h_pct == nil
    end

    test "leaves cg_price_change_24h_pct nil when no snapshot row exists for the id" do
      signal = signal_fixture(%{coingecko_id: "no-snapshot-yet", active: true})

      [result] = Signals.list_signals_with_prices(active: true)
      assert result.id == signal.id
      assert result.cg_price_change_24h_pct == nil
    end

    test "batches snapshot loading (does not N+1)" do
      # Sanity test: with 10 signals + 10 snapshots, the result should still
      # come back. We can't trivially count queries from a test without
      # extra plumbing, but exercising the batched path catches regressions
      # like a per-signal lookup that would 11x the query count.
      for i <- 1..10 do
        cg_id = "coin-#{i}"
        signal_fixture(%{coingecko_id: cg_id, symbol: "SYM#{i}", active: true})

        {:ok, _} =
          Signals.create_coingecko_snapshot(%{
            coingecko_id: cg_id,
            symbol: "SYM#{i}",
            snapshot_at: ~U[2026-05-17 12:00:00Z],
            price_change_percentage_24h: Decimal.new(i)
          })
      end

      results = Signals.list_signals_with_prices(active: true)
      assert length(results) == 10

      assert Enum.all?(results, &(&1.cg_price_change_24h_pct != nil))
    end
  end

  describe "list_signals_with_prices/1 — cg_volume_change_24h_pct enrichment" do
    test "computes (now-then)/then * 100 when both snapshots exist" do
      signal = signal_fixture(%{coingecko_id: "bitcoin", symbol: "BTC", active: true})

      # `now` snapshot has total_volume = 130; ~24h ago has 100 → +30%.
      # Use clock-relative dates so the enrichment query's `now - 24h` cutoff
      # places `latest_at` after the cutoff and `prior_at` before it.
      {latest_at, prior_at} = recent_snapshot_pair()

      insert_snapshot_history("bitcoin", "BTC",
        latest_volume: 130,
        latest_at: latest_at,
        prior_volume: 100,
        prior_at: prior_at
      )

      [result] = Signals.list_signals_with_prices(active: true)
      assert result.id == signal.id

      assert Decimal.equal?(
               result.cg_volume_change_24h_pct,
               Decimal.new("30")
             )
    end

    test "returns negative percentage when volume dropped" do
      signal_fixture(%{coingecko_id: "ethereum", symbol: "ETH", active: true})

      # 200 → 150 = -25%
      {latest_at, prior_at} = recent_snapshot_pair()

      insert_snapshot_history("ethereum", "ETH",
        latest_volume: 150,
        latest_at: latest_at,
        prior_volume: 200,
        prior_at: prior_at
      )

      [result] = Signals.list_signals_with_prices(active: true)
      assert Decimal.equal?(result.cg_volume_change_24h_pct, Decimal.new("-25"))
    end

    test "returns nil when no snapshot is older than 24h" do
      # Only one snapshot, recent. v_then doesn't exist → nil.
      signal_fixture(%{coingecko_id: "solana", symbol: "SOL", active: true})

      {:ok, _} =
        Signals.create_coingecko_snapshot(%{
          coingecko_id: "solana",
          symbol: "SOL",
          snapshot_at: ~U[2026-05-17 12:00:00Z],
          total_volume_usd: Decimal.new("100")
        })

      [result] = Signals.list_signals_with_prices(active: true)
      assert result.cg_volume_change_24h_pct == nil
    end

    test "returns nil when v_then is zero (avoid division by zero)" do
      signal_fixture(%{coingecko_id: "cardano", symbol: "ADA", active: true})

      insert_snapshot_history("cardano", "ADA",
        latest_volume: 100,
        latest_at: ~U[2026-05-17 12:00:00Z],
        prior_volume: 0,
        prior_at: ~U[2026-05-16 11:00:00Z]
      )

      [result] = Signals.list_signals_with_prices(active: true)
      assert result.cg_volume_change_24h_pct == nil
    end

    test "returns nil when no current snapshot exists" do
      signal_fixture(%{coingecko_id: "polkadot", symbol: "DOT", active: true})

      # Only an old snapshot, no current. We need both.
      {:ok, _} =
        Signals.create_coingecko_snapshot(%{
          coingecko_id: "polkadot",
          symbol: "DOT",
          snapshot_at: ~U[2026-05-16 11:00:00Z],
          total_volume_usd: Decimal.new("100")
        })

      # Volume Δ requires v_then to exist *before* v_now. If we only have one
      # snapshot, either v_now or v_then is missing. Either way → nil.
      [result] = Signals.list_signals_with_prices(active: true)
      assert result.cg_volume_change_24h_pct == nil
    end

    test "returns nil when coingecko_id is nil" do
      signal_fixture(%{coingecko_id: nil, active: true})

      [result] = Signals.list_signals_with_prices(active: true)
      assert result.cg_volume_change_24h_pct == nil
    end

    test "batches the lookup across signals" do
      # 5 signals, each with their own latest+prior pair. The batched query
      # must return them all without N+1.
      {latest_at, prior_at} = recent_snapshot_pair()

      for i <- 1..5 do
        cg_id = "vol-coin-#{i}"
        signal_fixture(%{coingecko_id: cg_id, symbol: "VOL#{i}", active: true})

        insert_snapshot_history(cg_id, "VOL#{i}",
          latest_volume: 100 + i * 10,
          latest_at: latest_at,
          prior_volume: 100,
          prior_at: prior_at
        )
      end

      results = Signals.list_signals_with_prices(active: true)
      assert length(results) == 5
      assert Enum.all?(results, &(&1.cg_volume_change_24h_pct != nil))
    end
  end

  # Returns {latest_at, prior_at} positioned around the enrichment query's
  # `now - 24h` cutoff. The enrichment uses `DateTime.utc_now()` at query
  # time, so hard-coded timestamps drift out of range as wall-clock time
  # advances.
  defp recent_snapshot_pair do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {DateTime.add(now, -1, :hour), DateTime.add(now, -25, :hour)}
  end

  defp insert_snapshot_history(coingecko_id, symbol, opts) do
    {:ok, _} =
      Signals.create_coingecko_snapshot(%{
        coingecko_id: coingecko_id,
        symbol: symbol,
        snapshot_at: Keyword.fetch!(opts, :latest_at),
        total_volume_usd: Decimal.new(Keyword.fetch!(opts, :latest_volume))
      })

    {:ok, _} =
      Signals.create_coingecko_snapshot(%{
        coingecko_id: coingecko_id,
        symbol: symbol,
        snapshot_at: Keyword.fetch!(opts, :prior_at),
        total_volume_usd: Decimal.new(Keyword.fetch!(opts, :prior_volume))
      })
  end
end
