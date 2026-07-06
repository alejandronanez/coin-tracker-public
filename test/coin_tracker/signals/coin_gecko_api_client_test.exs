defmodule CoinTracker.Signals.CoinGeckoApiClientTest do
  use ExUnit.Case, async: true
  import Mox

  alias CoinTracker.Signals.CoinGeckoApiClient
  alias CoinTracker.Signals.HTTPClientMock

  setup :verify_on_exit!

  describe "fetch_top_500/0" do
    test "pages twice (per_page=250) and returns a flat list of parsed rows" do
      page_1 = coingecko_markets(start_rank: 1, count: 250)
      page_2 = coingecko_markets(start_rank: 251, count: 250)

      expect(HTTPClientMock, :get, fn url, opts ->
        params = Keyword.fetch!(opts, :params)
        assert url =~ "/coins/markets"
        assert Keyword.get(params, :per_page) == 250
        assert Keyword.get(params, :page) == 1
        {:ok, %Req.Response{status: 200, body: page_1}}
      end)

      expect(HTTPClientMock, :get, fn _url, opts ->
        params = Keyword.fetch!(opts, :params)
        assert Keyword.get(params, :page) == 2
        {:ok, %Req.Response{status: 200, body: page_2}}
      end)

      assert {:ok, rows} = CoinGeckoApiClient.fetch_top_500(http_client: HTTPClientMock)
      assert length(rows) == 500
      assert hd(rows).coingecko_id == "coin-1"
      assert hd(rows).symbol == "SYM1"
      assert List.last(rows).coingecko_id == "coin-500"
    end

    test "parses fields into a normalized map with atom keys" do
      page_1 = [
        %{
          "id" => "bitcoin",
          "symbol" => "btc",
          "name" => "Bitcoin",
          "current_price" => 50_000.5,
          "market_cap" => 1_000_000_000,
          "total_volume" => 25_000_000_000,
          "price_change_percentage_24h" => 2.5
        }
      ]

      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: page_1}}
      end)

      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      assert {:ok, [row]} = CoinGeckoApiClient.fetch_top_500(http_client: HTTPClientMock)
      assert row.coingecko_id == "bitcoin"
      assert row.symbol == "BTC"
      assert Decimal.equal?(row.price_usd, Decimal.from_float(50_000.5))
      assert Decimal.equal?(row.market_cap_usd, Decimal.new("1000000000"))
      assert Decimal.equal?(row.total_volume_usd, Decimal.new("25000000000"))
      assert Decimal.equal?(row.price_change_percentage_24h, Decimal.from_float(2.5))
    end

    test "returns network error on HTTP failure of page 1" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:error, %Mint.TransportError{reason: :econnrefused}}
      end)

      assert {:error, :network_error} =
               CoinGeckoApiClient.fetch_top_500(http_client: HTTPClientMock)
    end

    test "returns http_error tuple on non-2xx response (e.g. 429)" do
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 429, body: %{"error" => "rate limited"}}}
      end)

      assert {:error, {:http_error, 429, _}} =
               CoinGeckoApiClient.fetch_top_500(http_client: HTTPClientMock)
    end

    test "fails fast if page 1 succeeds but page 2 errors" do
      page_1 = coingecko_markets(start_rank: 1, count: 250)

      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: page_1}}
      end)

      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "boom"}}}
      end)

      assert {:error, {:http_error, 500, _}} =
               CoinGeckoApiClient.fetch_top_500(http_client: HTTPClientMock)
    end

    test "ignores rows with missing id or symbol (defensive parsing)" do
      page_1 = [
        %{
          "id" => "bitcoin",
          "symbol" => "btc",
          "name" => "Bitcoin"
        },
        %{
          # missing id
          "symbol" => "eth",
          "name" => "Ethereum"
        },
        %{
          "id" => "no-symbol",
          # missing symbol
          "name" => "NoSymbol"
        }
      ]

      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: page_1}}
      end)

      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      assert {:ok, [row]} = CoinGeckoApiClient.fetch_top_500(http_client: HTTPClientMock)
      assert row.coingecko_id == "bitcoin"
    end
  end

  defp coingecko_markets(start_rank: start_rank, count: count) do
    for i <- start_rank..(start_rank + count - 1) do
      %{
        "id" => "coin-#{i}",
        "symbol" => "sym#{i}",
        "name" => "Coin #{i}",
        "current_price" => i * 1.0,
        "market_cap" => i * 1_000_000,
        "total_volume" => i * 100_000,
        "price_change_percentage_24h" => 1.0
      }
    end
  end
end
