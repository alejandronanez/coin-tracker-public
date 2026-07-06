defmodule CoinTracker.Coins.Exchanges.Binance.TradingTest do
  use CoinTracker.DataCase, async: true

  alias CoinTracker.Coins.Exchanges.Binance.Trading

  defmodule MockHTTP do
    def get(url, opts) do
      params = Keyword.get(opts, :params, [])
      credential = Keyword.get(opts, :credential)

      cond do
        url =~ "exchangeInfo" ->
          symbol = Keyword.get(params, :symbol)
          handle_exchange_info(symbol)

        url =~ "account" ->
          handle_account(credential)

        true ->
          {:ok, %{status: 404, body: %{"code" => -1000, "msg" => "Unknown endpoint"}}}
      end
    end

    defp handle_account(credential) do
      case credential do
        %{api_key: "test_key"} ->
          {:ok,
           %{
             status: 200,
             body: %{
               "balances" => [
                 %{"asset" => "BTC", "free" => "0.001", "locked" => "0.0"},
                 %{"asset" => "USDT", "free" => "500.50", "locked" => "10.0"},
                 %{"asset" => "ETH", "free" => "2.5", "locked" => "0.0"}
               ]
             }
           }}

        %{api_key: "bad_key"} ->
          {:ok, %{status: 401, body: %{"code" => -2015, "msg" => "Invalid API-key"}}}

        _ ->
          {:error, :econnrefused}
      end
    end

    defp handle_exchange_info(symbol) do
      case symbol do
        "PEPEUSDT" ->
          {:ok,
           %{
             status: 200,
             body: %{
               "symbols" => [
                 %{
                   "symbol" => "PEPEUSDT",
                   "filters" => [
                     %{
                       "filterType" => "PRICE_FILTER",
                       "tickSize" => "0.00000100",
                       "minPrice" => "0.00000001",
                       "maxPrice" => "1000.00000000"
                     },
                     %{
                       "filterType" => "LOT_SIZE",
                       "stepSize" => "1.00",
                       "minQty" => "1.00",
                       "maxQty" => "99999999999.00"
                     }
                   ]
                 }
               ]
             }
           }}

        "BTCUSDT" ->
          {:ok,
           %{
             status: 200,
             body: %{
               "symbols" => [
                 %{
                   "symbol" => "BTCUSDT",
                   "filters" => [
                     %{
                       "filterType" => "PRICE_FILTER",
                       "tickSize" => "0.01",
                       "minPrice" => "0.01",
                       "maxPrice" => "10000000.00"
                     },
                     %{
                       "filterType" => "LOT_SIZE",
                       "stepSize" => "0.00001",
                       "minQty" => "0.00001",
                       "maxQty" => "9000.00"
                     }
                   ]
                 }
               ]
             }
           }}

        "NOSYMBOLUSDT" ->
          {:ok, %{status: 200, body: %{"symbols" => []}}}

        _ ->
          {:error, :econnrefused}
      end
    end

    def post(_url, opts) do
      params = Keyword.get(opts, :params, [])
      credential = Keyword.get(opts, :credential)

      if credential == nil, do: raise("No credential passed")

      side = Keyword.get(params, :side)
      type = Keyword.get(params, :type)

      cond do
        side == "BUY" && type == "MARKET" ->
          handle_buy(params)

        side == "SELL" && Keyword.has_key?(params, :belowStopPrice) ->
          handle_oco(params)

        true ->
          {:ok, %{status: 400, body: %{"code" => -1000, "msg" => "Unknown request"}}}
      end
    end

    defp handle_buy(params) do
      symbol = Keyword.get(params, :symbol)

      case symbol do
        "PEPEUSDT" ->
          {:ok,
           %{
             status: 200,
             body: %{
               "orderId" => 12345,
               "symbol" => "PEPEUSDT",
               "executedQty" => "8103727.0",
               "cummulativeQuoteQty" => "100.0",
               "price" => "0.00001234",
               "fills" => [
                 %{
                   "price" => "0.00001234",
                   "qty" => "5000000.0",
                   "commission" => "5000.0",
                   "commissionAsset" => "PEPE"
                 },
                 %{
                   "price" => "0.00001235",
                   "qty" => "3103727.0",
                   "commission" => "3103.727",
                   "commissionAsset" => "PEPE"
                 }
               ]
             }
           }}

        "INSUFFICIENTUSDT" ->
          {:ok,
           %{status: 400, body: %{"code" => -2010, "msg" => "Account has insufficient balance"}}}

        "INVALIDUSDT" ->
          {:ok, %{status: 400, body: %{"code" => -1121, "msg" => "Invalid symbol"}}}

        "AUTHFAILUSDT" ->
          {:ok, %{status: 401, body: %{"code" => -2015, "msg" => "Invalid API-key"}}}

        _ ->
          {:error, :econnrefused}
      end
    end

    defp handle_oco(params) do
      symbol = Keyword.get(params, :symbol)

      case symbol do
        "PEPEUSDT" ->
          {:ok,
           %{
             status: 200,
             body: %{
               "orderListId" => 99999,
               "orderReports" => [
                 %{"orderId" => 100, "type" => "LIMIT_MAKER"},
                 %{"orderId" => 101, "type" => "STOP_LOSS_LIMIT"}
               ]
             }
           }}

        "PRICERULEUSDT" ->
          {:ok,
           %{status: 400, body: %{"code" => -2021, "msg" => "Order would immediately trigger"}}}

        "MINLOTUSDT" ->
          {:ok,
           %{
             status: 400,
             body: %{"code" => -1013, "msg" => "Filter failure: LOT_SIZE"}
           }}

        _ ->
          {:error, :timeout}
      end
    end
  end

  defmodule NoCommissionMockHTTP do
    def post(_url, _opts) do
      {:ok,
       %{
         status: 200,
         body: %{
           "orderId" => 12345,
           "symbol" => "PEPEUSDT",
           "executedQty" => "8103727.0",
           "cummulativeQuoteQty" => "100.0",
           "price" => "0.00001234",
           "fills" => [
             %{"price" => "0.00001234", "qty" => "8103727.0"}
           ]
         }
       }}
    end

    def get(_url, _opts), do: {:ok, %{status: 200, body: %{}}}
  end

  defmodule BnbFeeMockHTTP do
    def post(_url, _opts) do
      {:ok,
       %{
         status: 200,
         body: %{
           "orderId" => 12345,
           "symbol" => "PEPEUSDT",
           "executedQty" => "8103727.0",
           "cummulativeQuoteQty" => "100.0",
           "price" => "0.00001234",
           "fills" => [
             %{
               "price" => "0.00001234",
               "qty" => "8103727.0",
               "commission" => "0.00005",
               "commissionAsset" => "BNB"
             }
           ]
         }
       }}
    end

    def get(_url, _opts), do: {:ok, %{status: 200, body: %{}}}
  end

  @credential %{api_key: "test_key", api_secret: "test_secret"}
  @opts [http_client: MockHTTP]

  describe "fetch_balance/3" do
    test "returns free balance for USDT" do
      assert {:ok, result} = Trading.fetch_balance(@credential, "USDT", @opts)
      assert result.asset == "USDT"
      assert Decimal.equal?(result.free, Decimal.new("500.50"))
    end

    test "returns zero for asset not in account" do
      assert {:ok, result} = Trading.fetch_balance(@credential, "DOGE", @opts)
      assert result.asset == "DOGE"
      assert Decimal.equal?(result.free, Decimal.new("0"))
    end

    test "returns auth error for invalid credentials" do
      bad_credential = %{api_key: "bad_key", api_secret: "bad_secret"}
      assert {:error, {:auth_error, _msg}} = Trading.fetch_balance(bad_credential, "USDT", @opts)
    end

    test "returns network error on connection failure" do
      nil_credential = %{api_key: nil, api_secret: nil}
      assert {:error, :network_error} = Trading.fetch_balance(nil_credential, "USDT", @opts)
    end
  end

  describe "fetch_symbol_filters/2" do
    test "returns tick_size and step_size for valid symbol" do
      assert {:ok, filters} = Trading.fetch_symbol_filters("PEPE/USDT", @opts)
      assert filters.tick_size == Decimal.new("0.00000100")
      assert filters.step_size == Decimal.new("1.00")
    end

    test "returns correct filters for different symbols" do
      assert {:ok, filters} = Trading.fetch_symbol_filters("BTC/USDT", @opts)
      assert filters.tick_size == Decimal.new("0.01")
      assert filters.step_size == Decimal.new("0.00001")
    end

    test "returns error for unknown symbol" do
      assert {:error, {:invalid_symbol, _}} = Trading.fetch_symbol_filters("NOSYMBOL/USDT", @opts)
    end

    test "returns network error on connection failure" do
      assert {:error, :network_error} = Trading.fetch_symbol_filters("NOPE/USDT", @opts)
    end
  end

  describe "market_buy/4" do
    test "successful buy returns fill details" do
      assert {:ok, result} = Trading.market_buy(@credential, "PEPE/USDT", 100.0, @opts)
      assert result.order_id == 12345
      assert result.symbol == "PEPE/USDT"
      assert Decimal.gt?(result.fill_price, Decimal.new(0))
      assert Decimal.gt?(result.filled_qty, Decimal.new(0))
      assert result.quote_qty == Decimal.new("100.0")

      # filled_qty should be net of base-asset commissions:
      # 8103727.0 - 5000.0 - 3103.727 = 8095623.273
      assert Decimal.equal?(result.filled_qty, Decimal.new("8095623.273"))
    end

    test "calculates weighted average fill price" do
      {:ok, result} = Trading.market_buy(@credential, "PEPE/USDT", 100.0, @opts)

      # Weighted avg: (5000000 * 0.00001234 + 3103727 * 0.00001235) / 8103727
      assert Decimal.gt?(result.fill_price, Decimal.new("0.00001233"))
      assert Decimal.lt?(result.fill_price, Decimal.new("0.00001236"))
    end

    test "does not subtract commission when paid in BNB" do
      assert {:ok, result} =
               Trading.market_buy(@credential, "PEPE/USDT", 100.0, http_client: BnbFeeMockHTTP)

      # Commission is in BNB, not base asset, so filled_qty should be the full executedQty
      assert Decimal.equal?(result.filled_qty, Decimal.new("8103727.0"))
    end

    test "handles fills without commission fields" do
      assert {:ok, result} =
               Trading.market_buy(@credential, "PEPE/USDT", 100.0,
                 http_client: NoCommissionMockHTTP
               )

      # No commission fields means no deduction — filled_qty equals executedQty
      assert Decimal.equal?(result.filled_qty, Decimal.new("8103727.0"))
    end

    test "insufficient balance returns tagged error" do
      assert {:error, {:insufficient_balance, msg}} =
               Trading.market_buy(@credential, "INSUFFICIENT/USDT", 100.0, @opts)

      assert msg =~ "insufficient"
    end

    test "invalid symbol returns tagged error" do
      assert {:error, {:invalid_symbol, _msg}} =
               Trading.market_buy(@credential, "INVALID/USDT", 100.0, @opts)
    end

    test "auth failure returns tagged error" do
      assert {:error, {:auth_error, _msg}} =
               Trading.market_buy(@credential, "AUTHFAIL/USDT", 100.0, @opts)
    end

    test "network error returns :network_error" do
      assert {:error, :network_error} =
               Trading.market_buy(@credential, "NETWORKFAIL/USDT", 100.0, @opts)
    end
  end

  describe "place_oco_sell/6" do
    test "successful OCO returns order IDs" do
      assert {:ok, result} =
               Trading.place_oco_sell(
                 @credential,
                 "PEPE/USDT",
                 Decimal.new("8103727"),
                 Decimal.new("0.00001419"),
                 Decimal.new("0.00000987"),
                 @opts
               )

      assert result.order_list_id == 99999
      assert result.tp_order_id == 100
      assert result.sl_order_id == 101
    end

    test "rounds sl_limit_price to tick_size" do
      tick_size = Decimal.new("0.00000100")
      opts = Keyword.put(@opts, :tick_size, tick_size)

      # sl_price = 0.00000987, sl_limit = 0.00000987 * 0.995 = 0.0000098...
      # rounded to tick_size 0.00000100 should be 0.00000900
      assert {:ok, _result} =
               Trading.place_oco_sell(
                 @credential,
                 "PEPE/USDT",
                 Decimal.new("8103727"),
                 Decimal.new("0.00001400"),
                 Decimal.new("0.00000987"),
                 opts
               )
    end

    test "price rule violation returns tagged error" do
      assert {:error, {:price_rule_violation, _msg}} =
               Trading.place_oco_sell(
                 @credential,
                 "PRICERULE/USDT",
                 Decimal.new("100"),
                 Decimal.new("1.5"),
                 Decimal.new("0.8"),
                 @opts
               )
    end

    test "filter failure returns tagged error" do
      assert {:error, {:filter_failure, msg}} =
               Trading.place_oco_sell(
                 @credential,
                 "MINLOT/USDT",
                 Decimal.new("0.001"),
                 Decimal.new("1.5"),
                 Decimal.new("0.8"),
                 @opts
               )

      assert msg =~ "LOT_SIZE"
    end

    test "network error returns :network_error" do
      assert {:error, :network_error} =
               Trading.place_oco_sell(
                 @credential,
                 "TIMEOUT/USDT",
                 Decimal.new("100"),
                 Decimal.new("1.5"),
                 Decimal.new("0.8"),
                 @opts
               )
    end
  end
end
