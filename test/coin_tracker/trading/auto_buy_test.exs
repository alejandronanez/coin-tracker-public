defmodule CoinTracker.Trading.AutoBuyTest do
  use CoinTracker.DataCase

  import CoinTracker.AccountsFixtures
  import CoinTracker.SignalsFixtures

  alias CoinTracker.Accounts
  alias CoinTracker.Coins
  alias CoinTracker.Trading.AutoBuy

  defmodule Fixtures do
    def account_response(usdt_free) do
      %{
        status: 200,
        body: %{
          "balances" => [
            %{"asset" => "BTC", "free" => "0.001", "locked" => "0.0"},
            %{"asset" => "USDT", "free" => usdt_free, "locked" => "0.0"}
          ]
        }
      }
    end

    def exchange_info_response do
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
      }
    end
  end

  defmodule SuccessHTTP do
    def get(url, _opts) do
      cond do
        url =~ "exchangeInfo" -> {:ok, Fixtures.exchange_info_response()}
        url =~ "account" -> {:ok, Fixtures.account_response("1000.00")}
        true -> {:ok, %{status: 200, body: [%{"symbol" => "PEPEUSDT", "price" => "0.00001234"}]}}
      end
    end

    def post(_url, opts) do
      params = Keyword.get(opts, :params, [])
      side = Keyword.get(params, :side)
      type = Keyword.get(params, :type)

      cond do
        side == "BUY" && type == "MARKET" ->
          client_order_id = Keyword.get(params, :newClientOrderId)

          unless is_binary(client_order_id) and byte_size(client_order_id) == 32 and
                   Regex.match?(~r/^[0-9a-f]{32}$/, client_order_id) do
            raise "Expected newClientOrderId to be a 32-char hex string, got: #{inspect(client_order_id)}"
          end

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
                   "commission" => "8103.727",
                   "commissionAsset" => "PEPE"
                 }
               ]
             }
           }}

        side == "SELL" && Keyword.has_key?(params, :belowStopPrice) ->
          list_client_order_id = Keyword.get(params, :listClientOrderId)

          unless is_binary(list_client_order_id) and byte_size(list_client_order_id) == 32 and
                   Regex.match?(~r/^[0-9a-f]{32}$/, list_client_order_id) do
            raise "Expected listClientOrderId to be a 32-char hex string, got: #{inspect(list_client_order_id)}"
          end

          {:ok,
           %{
             status: 200,
             body: %{
               "orderListId" => 99999,
               "orderReports" => [
                 %{"orderId" => 111, "type" => "LIMIT_MAKER"},
                 %{"orderId" => 222, "type" => "STOP_LOSS_LIMIT"}
               ]
             }
           }}
      end
    end
  end

  defmodule BuyFailHTTP do
    def get(url, _opts) do
      cond do
        url =~ "exchangeInfo" -> {:ok, Fixtures.exchange_info_response()}
        url =~ "account" -> {:ok, Fixtures.account_response("1000.00")}
        true -> {:ok, %{status: 200, body: [%{"symbol" => "PEPEUSDT", "price" => "0.00001234"}]}}
      end
    end

    def post(_url, _opts) do
      {:ok,
       %{
         status: 400,
         body: %{"code" => -2010, "msg" => "Account has insufficient balance"}
       }}
    end
  end

  defmodule OcoFailHTTP do
    def get(url, _opts) do
      cond do
        url =~ "exchangeInfo" -> {:ok, Fixtures.exchange_info_response()}
        url =~ "account" -> {:ok, Fixtures.account_response("1000.00")}
        true -> {:ok, %{status: 200, body: [%{"symbol" => "PEPEUSDT", "price" => "0.00001234"}]}}
      end
    end

    def post(_url, opts) do
      params = Keyword.get(opts, :params, [])
      side = Keyword.get(params, :side)
      type = Keyword.get(params, :type)

      if side == "BUY" && type == "MARKET" do
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
                 "commission" => "8103.727",
                 "commissionAsset" => "PEPE"
               }
             ]
           }
         }}
      else
        {:ok,
         %{
           status: 400,
           body: %{"code" => -2021, "msg" => "Price rule violation"}
         }}
      end
    end
  end

  # Captures the OCO params so we can verify tick-size rounding
  defmodule TickSizeVerifyHTTP do
    def get(url, _opts) do
      cond do
        url =~ "exchangeInfo" -> {:ok, Fixtures.exchange_info_response()}
        url =~ "account" -> {:ok, Fixtures.account_response("1000.00")}
        true -> {:ok, %{status: 200, body: [%{"symbol" => "PEPEUSDT", "price" => "0.00001234"}]}}
      end
    end

    def post(_url, opts) do
      params = Keyword.get(opts, :params, [])
      side = Keyword.get(params, :side)
      type = Keyword.get(params, :type)

      cond do
        side == "BUY" && type == "MARKET" ->
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
                 # Weighted avg will be non-round: 0.00001234383...
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

        side == "SELL" && Keyword.has_key?(params, :belowStopPrice) ->
          # Verify all prices are multiples of tick_size 0.00000100
          above_price = Keyword.get(params, :abovePrice)
          below_price = Keyword.get(params, :belowPrice)
          below_stop = Keyword.get(params, :belowStopPrice)

          tick = Decimal.new("0.00000100")

          for price_str <- [above_price, below_price, below_stop] do
            price = Decimal.new(price_str)
            remainder = price |> Decimal.div(tick) |> Decimal.rem(1)

            unless Decimal.equal?(remainder, 0) do
              raise "Price #{price_str} is not a multiple of tick_size #{tick}"
            end
          end

          # Verify quantity is a multiple of step_size 1.00
          quantity_str = Keyword.get(params, :quantity)
          quantity = Decimal.new(quantity_str)
          step = Decimal.new("1.00")
          qty_remainder = quantity |> Decimal.div(step) |> Decimal.rem(1)

          unless Decimal.equal?(qty_remainder, 0) do
            raise "Quantity #{quantity_str} is not a multiple of step_size #{step}"
          end

          {:ok,
           %{
             status: 200,
             body: %{
               "orderListId" => 99999,
               "orderReports" => [
                 %{"orderId" => 111, "type" => "LIMIT_MAKER"},
                 %{"orderId" => 222, "type" => "STOP_LOSS_LIMIT"}
               ]
             }
           }}
      end
    end
  end

  defmodule LowBalanceHTTP do
    def get(url, _opts) do
      cond do
        url =~ "exchangeInfo" -> {:ok, Fixtures.exchange_info_response()}
        url =~ "account" -> {:ok, Fixtures.account_response("50.00")}
        true -> {:ok, %{status: 200, body: [%{"symbol" => "PEPEUSDT", "price" => "0.00001234"}]}}
      end
    end

    def post(_url, opts) do
      params = Keyword.get(opts, :params, [])
      side = Keyword.get(params, :side)
      type = Keyword.get(params, :type)

      cond do
        side == "BUY" && type == "MARKET" ->
          # Return the quoteOrderQty back to verify capping
          quote_qty = Keyword.get(params, :quoteOrderQty, "0")

          {:ok,
           %{
             status: 200,
             body: %{
               "orderId" => 12345,
               "symbol" => "PEPEUSDT",
               "executedQty" => "4000000.0",
               "cummulativeQuoteQty" => quote_qty,
               "price" => "0.00001234",
               "fills" => [
                 %{
                   "price" => "0.00001234",
                   "qty" => "4000000.0",
                   "commission" => "4000.0",
                   "commissionAsset" => "PEPE"
                 }
               ]
             }
           }}

        side == "SELL" && Keyword.has_key?(params, :belowStopPrice) ->
          {:ok,
           %{
             status: 200,
             body: %{
               "orderListId" => 99999,
               "orderReports" => [
                 %{"orderId" => 111, "type" => "LIMIT_MAKER"},
                 %{"orderId" => 222, "type" => "STOP_LOSS_LIMIT"}
               ]
             }
           }}
      end
    end
  end

  defmodule TooLowBalanceHTTP do
    def get(url, _opts) do
      cond do
        url =~ "exchangeInfo" -> {:ok, Fixtures.exchange_info_response()}
        url =~ "account" -> {:ok, Fixtures.account_response("0.50")}
        true -> {:ok, %{status: 200, body: []}}
      end
    end

    def post(_url, _opts), do: raise("Should not be called")
  end

  defmodule BalanceFetchFailHTTP do
    def get(url, _opts) do
      cond do
        url =~ "exchangeInfo" -> {:ok, Fixtures.exchange_info_response()}
        url =~ "account" -> {:error, :econnrefused}
        true -> {:ok, %{status: 200, body: []}}
      end
    end

    def post(_url, _opts), do: raise("Should not be called")
  end

  setup do
    user = admin_user_fixture()
    signal = signal_fixture(%{symbol: "PEPE"})

    {:ok, symbol_price} =
      Coins.upsert_symbol_price(%{
        exchange: :binance_spot,
        symbol_pair: "PEPE/USDT",
        current_price: "0.00001234"
      })

    signal =
      signal
      |> Ecto.Changeset.change(symbol_price_id: symbol_price.id)
      |> Repo.update!()
      |> Repo.preload(:symbol_price)

    trade_params = %{take_profit: 15, stop_loss: 20}

    %{user: user, signal: signal, trade_params: trade_params}
  end

  describe "execute/5 - full success" do
    test "returns :ok with position, buy_order, and oco_order", %{
      user: user,
      signal: signal,
      trade_params: trade_params
    } do
      credential = exchange_credential_fixture(user)

      assert {:ok, result} =
               AutoBuy.execute(user, signal, Decimal.new("100"), trade_params,
                 http_client: SuccessHTTP
               )

      assert %{position: position, buy_order: buy, oco_order: oco} = result
      assert position.source == "auto_buy"
      assert buy.order_id == 12345
      assert oco.order_list_id == 99999

      # Verify credential last_used_at was updated
      updated_credential = Accounts.get_exchange_credential(user.id, :binance_spot)
      assert updated_credential.last_used_at != credential.last_used_at
    end

    test "rounds OCO prices to tick_size multiples", %{
      user: user,
      signal: signal,
      trade_params: trade_params
    } do
      _credential = exchange_credential_fixture(user)

      # TickSizeVerifyHTTP validates all OCO prices are multiples of 0.00000100
      # If any price has excess precision, the mock raises an error
      assert {:ok, _result} =
               AutoBuy.execute(user, signal, Decimal.new("100"), trade_params,
                 http_client: TickSizeVerifyHTTP
               )
    end
  end

  describe "execute/5 - OCO failure" do
    test "returns :error with :oco_failed when buy succeeds but OCO fails", %{
      user: user,
      signal: signal,
      trade_params: trade_params
    } do
      _credential = exchange_credential_fixture(user)

      assert {:error, {:oco_failed, details}} =
               AutoBuy.execute(user, signal, Decimal.new("100"), trade_params,
                 http_client: OcoFailHTTP
               )

      assert details.buy_order.order_id == 12345
      assert {:price_rule_violation, _} = details.reason
    end

    test "does not create a position when OCO fails", %{
      user: user,
      signal: signal,
      trade_params: trade_params
    } do
      _credential = exchange_credential_fixture(user)

      assert {:error, {:oco_failed, _}} =
               AutoBuy.execute(user, signal, Decimal.new("100"), trade_params,
                 http_client: OcoFailHTTP
               )

      # No position should have been created
      assert CoinTracker.Trading.list_active_positions_for_user(user.id) == []
    end
  end

  describe "execute/5 - balance capping" do
    test "does not cap when requested amount is within balance", %{
      user: user,
      signal: signal,
      trade_params: trade_params
    } do
      _credential = exchange_credential_fixture(user)

      # SuccessHTTP has 1000 USDT, requesting 100 — no capping
      assert {:ok, result} =
               AutoBuy.execute(user, signal, Decimal.new("100"), trade_params,
                 http_client: SuccessHTTP
               )

      assert result.buy_order.order_id == 12345
    end

    test "caps amount when requested exceeds available balance", %{
      user: user,
      signal: signal,
      trade_params: trade_params
    } do
      _credential = exchange_credential_fixture(user)

      # LowBalanceHTTP has 50 USDT, requesting 100 — should cap to 50 * 0.99 = 49.50
      assert {:ok, result} =
               AutoBuy.execute(user, signal, Decimal.new("100"), trade_params,
                 http_client: LowBalanceHTTP
               )

      assert result.buy_order.order_id == 12345
    end

    test "returns error when balance is too low for minimum order", %{
      user: user,
      signal: signal,
      trade_params: trade_params
    } do
      _credential = exchange_credential_fixture(user)

      # TooLowBalanceHTTP has 0.50 USDT — 0.50 * 0.99 = 0.495 < 1.0 min
      assert {:error, {:insufficient_balance, msg}} =
               AutoBuy.execute(user, signal, Decimal.new("100"), trade_params,
                 http_client: TooLowBalanceHTTP
               )

      assert msg =~ "too low"
    end

    test "returns error when balance fetch fails", %{
      user: user,
      signal: signal,
      trade_params: trade_params
    } do
      _credential = exchange_credential_fixture(user)

      assert {:error, :network_error} =
               AutoBuy.execute(user, signal, Decimal.new("100"), trade_params,
                 http_client: BalanceFetchFailHTTP
               )
    end
  end

  describe "execute/5 - buy failure" do
    test "returns :error when buy fails", %{
      user: user,
      signal: signal,
      trade_params: trade_params
    } do
      _credential = exchange_credential_fixture(user)

      assert {:error, {:insufficient_balance, _}} =
               AutoBuy.execute(user, signal, Decimal.new("100"), trade_params,
                 http_client: BuyFailHTTP
               )
    end
  end

  describe "execute/5 - no credentials" do
    test "returns :error when user has no credentials", %{
      user: user,
      signal: signal,
      trade_params: trade_params
    } do
      assert {:error, :no_credentials} =
               AutoBuy.execute(user, signal, Decimal.new("100"), trade_params,
                 http_client: SuccessHTTP
               )
    end
  end

  describe "execute/5 - unsupported exchange" do
    test "returns :error for unsupported exchange", %{
      user: user,
      trade_params: trade_params
    } do
      signal = signal_fixture(%{symbol: "SOL"})

      {:ok, symbol_price} =
        Coins.upsert_symbol_price(%{
          exchange: :bitget_spot,
          symbol_pair: "SOL/USDT",
          current_price: "150.00"
        })

      signal =
        signal
        |> Ecto.Changeset.change(symbol_price_id: symbol_price.id)
        |> Repo.update!()
        |> Repo.preload(:symbol_price)

      _credential = exchange_credential_fixture(user, %{"exchange" => "bitget_spot"})

      assert {:error, {:exchange_not_supported, _}} =
               AutoBuy.execute(user, signal, Decimal.new("100"), trade_params,
                 http_client: SuccessHTTP
               )
    end
  end
end
