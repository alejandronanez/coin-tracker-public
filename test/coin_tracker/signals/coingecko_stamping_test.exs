defmodule CoinTracker.Signals.CoingeckoStampingTest do
  @moduledoc """
  Verifies that the CoinScan ingestion path stamps `coingecko_id` on each
  signal it inserts, using `CoinGeckoPoller.lookup_coingecko_id/1`.
  """

  # async: false — we register the poller under its global name.
  use CoinTracker.DataCase, async: false

  import Mox

  alias CoinTracker.Signals
  alias CoinTracker.Signals.{CoinGeckoPoller, HTTPClientMock, Signal}

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "upsert via ingest_prefetched_top_10/1" do
    test "stamps coingecko_id when the symbol is in the cache" do
      poller = start_poller_with_cache!(%{"BTC" => "bitcoin", "ETH" => "ethereum"})

      Mox.allow(HTTPClientMock, self(), poller)

      assert Signals.ingest_prefetched_top_10([
               build_signal("BTC", "Bitcoin"),
               build_signal("ETH", "Ethereum")
             ]) == 2

      btc = Repo.get_by!(Signal, symbol: "BTC")
      eth = Repo.get_by!(Signal, symbol: "ETH")

      assert btc.coingecko_id == "bitcoin"
      assert eth.coingecko_id == "ethereum"
    end

    test "leaves coingecko_id nil when symbol is not in the cache" do
      _poller = start_poller_with_cache!(%{"BTC" => "bitcoin"})

      assert Signals.ingest_prefetched_top_10([build_signal("UNKNOWN", "UnknownCoin")]) == 1

      unknown = Repo.get_by!(Signal, symbol: "UNKNOWN")
      assert unknown.coingecko_id == nil
    end

    test "ingestion does not crash when the poller process is not running" do
      # Don't start a poller — lookup_coingecko_id should return nil for everything.
      refute Process.whereis(CoinGeckoPoller)

      assert Signals.ingest_prefetched_top_10([build_signal("FOO", "Foo")]) == 1

      foo = Repo.get_by!(Signal, symbol: "FOO")
      assert foo.coingecko_id == nil
    end

    test "does not clobber a previously-stamped coingecko_id when cache is cold" do
      # First ingest with warm cache — BTC gets stamped.
      poller = start_poller_with_cache!(%{"BTC" => "bitcoin"})
      Mox.allow(HTTPClientMock, self(), poller)
      assert Signals.ingest_prefetched_top_10([build_signal("BTC", "Bitcoin")]) == 1
      assert Repo.get_by!(Signal, symbol: "BTC").coingecko_id == "bitcoin"

      # Stop the poller, simulating a cold cache on the next ingestion tick.
      stop_supervised!(CoinGeckoPoller)

      # Re-ingest the same BTC — lookup now returns nil. The pre-existing
      # stamp must NOT be overwritten.
      assert Signals.ingest_prefetched_top_10([build_signal("BTC", "Bitcoin")]) == 1
      assert Repo.get_by!(Signal, symbol: "BTC").coingecko_id == "bitcoin"
    end
  end

  defp start_poller_with_cache!(symbol_map) do
    pages = pages_from_map(symbol_map)

    Mox.stub(HTTPClientMock, :get, fn _url, opts ->
      page = Keyword.fetch!(opts, :params) |> Keyword.fetch!(:page)
      body = Map.get(pages, page, [])
      {:ok, %Req.Response{status: 200, body: body}}
    end)

    pid =
      start_supervised!(
        {CoinGeckoPoller, [enabled: false, http_client: HTTPClientMock, name: CoinGeckoPoller]}
      )

    Mox.allow(HTTPClientMock, self(), pid)
    assert {:ok, _count} = CoinGeckoPoller.poll_now(pid)
    pid
  end

  defp pages_from_map(symbol_map) do
    rows =
      Enum.map(symbol_map, fn {symbol, coingecko_id} ->
        %{
          "id" => coingecko_id,
          "symbol" => String.downcase(symbol),
          "name" => coingecko_id,
          "current_price" => 1.0
        }
      end)

    %{1 => rows, 2 => []}
  end

  defp build_signal(symbol, name) do
    %Signal{
      symbol: symbol,
      name: name,
      in_top: true,
      active: true,
      in_top_since: ~U[2026-05-17 12:00:00Z],
      initial_volume_24h: Decimal.new("1000000"),
      current_volume_24h: Decimal.new("1500000")
    }
  end
end
