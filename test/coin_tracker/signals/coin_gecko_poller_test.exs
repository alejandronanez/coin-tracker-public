defmodule CoinTracker.Signals.CoinGeckoPollerTest do
  @moduledoc """
  Tests for `CoinGeckoPoller` exercise the GenServer via its public surface:
  - `start_link/1` (with `enabled: false` so no timer fires)
  - `poll_now/0` (synchronous trigger we use in place of the 15-min timer)
  - `lookup_coingecko_id/1` (the cache read API used by ingestion)

  The HTTP layer is stubbed via `Mox` and the `:http_client` keyword passed
  through the poller into `CoinGeckoApiClient.fetch_top_500/1`. The mock has
  to be `set_mox_global` because the poller process owns the call site.
  """

  use CoinTracker.DataCase, async: false

  import Mox

  alias CoinTracker.Signals
  alias CoinTracker.Signals.{CoingeckoSnapshot, CoinGeckoPoller, HTTPClientMock}

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "poll_now/1" do
    test "inserts snapshots for every parsed row and builds the symbol cache" do
      stub_pages([
        %{"id" => "bitcoin", "symbol" => "btc", "name" => "Bitcoin", "current_price" => 50_000},
        %{"id" => "ethereum", "symbol" => "eth", "name" => "Ethereum", "current_price" => 3000}
      ])

      poller = start_poller!()

      assert {:ok, 2} = CoinGeckoPoller.poll_now(poller)

      assert Repo.aggregate(CoingeckoSnapshot, :count) == 2
      assert CoinGeckoPoller.lookup_coingecko_id(poller, "BTC") == "bitcoin"
      assert CoinGeckoPoller.lookup_coingecko_id(poller, "ETH") == "ethereum"
    end

    test "lookup_coingecko_id is case-insensitive and returns nil for unknown" do
      stub_pages([
        %{"id" => "solana", "symbol" => "sol", "name" => "Solana", "current_price" => 100}
      ])

      poller = start_poller!()
      assert {:ok, 1} = CoinGeckoPoller.poll_now(poller)

      assert CoinGeckoPoller.lookup_coingecko_id(poller, "sol") == "solana"
      assert CoinGeckoPoller.lookup_coingecko_id(poller, "SOL") == "solana"
      assert CoinGeckoPoller.lookup_coingecko_id(poller, "UNKNOWN") == nil
    end

    test "first-match-wins by market-cap order (higher market cap stays in cache)" do
      # CoinGecko returns rows sorted by market cap desc — the poller must
      # respect that order so duplicate symbols (rare but possible) resolve
      # to the dominant coin.
      stub_pages([
        %{"id" => "real-eth", "symbol" => "eth", "name" => "Ethereum", "current_price" => 3000},
        %{"id" => "fake-eth", "symbol" => "eth", "name" => "FakeETH", "current_price" => 1}
      ])

      poller = start_poller!()
      assert {:ok, 2} = CoinGeckoPoller.poll_now(poller)

      assert CoinGeckoPoller.lookup_coingecko_id(poller, "ETH") == "real-eth"
    end

    test "on HTTP failure: retains prior cache, does not crash, returns error" do
      # First poll: success, populates cache
      stub_pages([
        %{"id" => "bitcoin", "symbol" => "btc", "name" => "Bitcoin", "current_price" => 50_000}
      ])

      poller = start_poller!()
      assert {:ok, 1} = CoinGeckoPoller.poll_now(poller)
      assert CoinGeckoPoller.lookup_coingecko_id(poller, "BTC") == "bitcoin"

      # Second poll: 429, simulate page 1 failure
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 429, body: %{"error" => "rate limited"}}}
      end)

      assert {:error, _} = CoinGeckoPoller.poll_now(poller)

      # Cache MUST be preserved across failures.
      assert CoinGeckoPoller.lookup_coingecko_id(poller, "BTC") == "bitcoin"
      assert Process.alive?(poller)
    end

    test "prunes coingecko_snapshots rows older than 48h inline" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      cutoff = DateTime.add(now, -48, :hour)

      {:ok, _stale} =
        Signals.create_coingecko_snapshot(%{
          coingecko_id: "old-coin",
          symbol: "OLD",
          snapshot_at: DateTime.add(cutoff, -3600, :second)
        })

      stub_pages([
        %{"id" => "bitcoin", "symbol" => "btc", "name" => "Bitcoin", "current_price" => 50_000}
      ])

      poller = start_poller!()
      assert {:ok, 1} = CoinGeckoPoller.poll_now(poller)

      # The stale row should be gone; only the fresh BTC snapshot should remain.
      remaining =
        from(s in CoingeckoSnapshot, select: s.coingecko_id) |> Repo.all() |> Enum.sort()

      assert remaining == ["bitcoin"]
    end

    test "is idempotent on the (coingecko_id, snapshot_at) unique constraint" do
      # If the same tick somehow runs twice with the same snapshot_at, the
      # second run must not crash — the unique index should swallow the dup.
      fixed_now = ~U[2026-05-17 12:00:00Z]

      stub_pages([
        %{"id" => "bitcoin", "symbol" => "btc", "name" => "Bitcoin", "current_price" => 50_000}
      ])

      poller = start_poller!(now_fn: fn -> fixed_now end)
      assert {:ok, 1} = CoinGeckoPoller.poll_now(poller)

      stub_pages([
        %{"id" => "bitcoin", "symbol" => "btc", "name" => "Bitcoin", "current_price" => 51_000}
      ])

      # Same fixed_now → same snapshot_at → unique conflict on insert.
      assert {:ok, 0} = CoinGeckoPoller.poll_now(poller)

      # Only one row total.
      assert Repo.aggregate(CoingeckoSnapshot, :count) == 1
    end

    test "broadcasts on signals:updated after a successful poll cycle" do
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "signals:updated")

      stub_pages([
        %{"id" => "bitcoin", "symbol" => "btc", "name" => "Bitcoin", "current_price" => 50_000}
      ])

      poller = start_poller!()
      assert {:ok, 1} = CoinGeckoPoller.poll_now(poller)

      assert_receive {:signals_updated, _signals}, 1000
    end

    test "does not broadcast on a failed poll cycle" do
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "signals:updated")

      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 429, body: %{"error" => "rate limited"}}}
      end)

      poller = start_poller!()
      assert {:error, _} = CoinGeckoPoller.poll_now(poller)

      refute_receive {:signals_updated, _}, 200
    end
  end

  defp start_poller!(extra_opts \\ []) do
    opts =
      [
        enabled: false,
        http_client: HTTPClientMock,
        name: nil
      ] ++ extra_opts

    pid = start_supervised!({CoinGeckoPoller, opts})
    Mox.allow(HTTPClientMock, self(), pid)
    pid
  end

  defp stub_pages(rows) do
    expect(HTTPClientMock, :get, fn _url, _opts ->
      {:ok, %Req.Response{status: 200, body: rows}}
    end)

    expect(HTTPClientMock, :get, fn _url, _opts ->
      {:ok, %Req.Response{status: 200, body: []}}
    end)
  end
end
