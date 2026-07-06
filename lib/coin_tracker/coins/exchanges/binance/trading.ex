defmodule CoinTracker.Coins.Exchanges.Binance.Trading do
  @moduledoc """
  Binance exchange trading integration for placing orders.

  Implements `TradingBehaviour` for market buy and OCO sell orders.
  All requests are signed via `AuthPlugin`.
  """

  @behaviour CoinTracker.Coins.Exchanges.TradingBehaviour

  alias CoinTracker.Coins.Exchanges.Binance.AuthPlugin
  alias CoinTracker.Log

  @binance_order_url "https://api.binance.com/api/v3/order"
  @binance_oco_url "https://api.binance.com/api/v3/orderList/oco"
  @binance_exchange_info_url "https://api.binance.com/api/v3/exchangeInfo"
  @binance_account_url "https://api.binance.com/api/v3/account"

  @slippage_buffer Decimal.new("0.995")

  @impl true
  def market_buy(credential, symbol, quote_qty, opts \\ []) do
    binance_symbol = normalize_symbol(symbol)

    params = [
      symbol: binance_symbol,
      side: "BUY",
      type: "MARKET",
      quoteOrderQty: to_string(quote_qty),
      newClientOrderId: generate_client_order_id()
    ]

    buy_opts =
      Keyword.put(opts, :req_opts, connect_options: [timeout: 10_000], receive_timeout: 30_000)

    case post_signed(@binance_order_url, params, credential, buy_opts) do
      {:ok, %{status: 200, body: body}} ->
        parse_buy_response(body, symbol)

      {:ok, %{status: _status, body: body}} ->
        classify_error(body)

      {:error, reason} ->
        Log.network_error("Binance trading network error",
          module: :binance_trading,
          operation: :market_buy,
          exchange: :binance,
          symbol: symbol,
          reason: inspect(reason)
        )

        {:error, :network_error}
    end
  end

  @impl true
  def fetch_balance(credential, asset, opts \\ []) do
    case get_signed(@binance_account_url, [], credential, opts) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, result} = parse_balance(body, asset)

        Log.debug("Binance balance fetched: #{asset} = #{result.free}",
          module: :binance_trading,
          operation: :fetch_balance,
          exchange: :binance
        )

        {:ok, result}

      {:ok, %{status: _status, body: body}} ->
        classify_error(body)

      {:error, reason} ->
        Log.network_error("Binance account balance fetch failed",
          module: :binance_trading,
          operation: :fetch_balance,
          exchange: :binance,
          reason: inspect(reason)
        )

        {:error, :network_error}
    end
  end

  @doc """
  Fetches PRICE_FILTER tick_size and LOT_SIZE step_size for a symbol from Binance exchange info.

  This is a public endpoint — no authentication required.
  """
  def fetch_symbol_filters(symbol, opts \\ []) do
    binance_symbol = normalize_symbol(symbol)

    case get_public(@binance_exchange_info_url, [symbol: binance_symbol], opts) do
      {:ok, %{status: 200, body: body}} ->
        parse_symbol_filters(body)

      {:ok, %{status: _status, body: body}} ->
        classify_error(body)

      {:error, reason} ->
        Log.network_error("Binance exchange info fetch failed",
          module: :binance_trading,
          operation: :fetch_symbol_filters,
          exchange: :binance,
          symbol: symbol,
          reason: inspect(reason)
        )

        {:error, :network_error}
    end
  end

  @impl true
  def place_oco_sell(credential, symbol, quantity, tp_price, sl_price, opts \\ []) do
    binance_symbol = normalize_symbol(symbol)
    tick_size = Keyword.get(opts, :tick_size)

    sl_limit_price =
      to_decimal(sl_price)
      |> Decimal.mult(@slippage_buffer)
      |> round_to_tick(tick_size)

    params = [
      symbol: binance_symbol,
      side: "SELL",
      quantity: to_string(quantity),
      aboveType: "LIMIT_MAKER",
      abovePrice: to_string(tp_price),
      belowType: "STOP_LOSS_LIMIT",
      belowPrice: to_string(sl_limit_price),
      belowStopPrice: to_string(sl_price),
      belowTimeInForce: "GTC",
      listClientOrderId: generate_client_order_id()
    ]

    oco_opts =
      Keyword.put(opts, :req_opts, connect_options: [timeout: 10_000], receive_timeout: 60_000)

    case post_signed(@binance_oco_url, params, credential, oco_opts) do
      {:ok, %{status: 200, body: body}} ->
        parse_oco_response(body)

      {:ok, %{status: _status, body: body}} ->
        classify_error(body)

      {:error, reason} ->
        Log.network_error("Binance trading network error",
          module: :binance_trading,
          operation: :place_oco_sell,
          exchange: :binance,
          symbol: symbol,
          reason: inspect(reason)
        )

        {:error, :network_error}
    end
  end

  # --- Private ---

  defp post_signed(url, params, credential, opts) do
    http_client = Keyword.get(opts, :http_client)
    req_opts = Keyword.get(opts, :req_opts, [])

    if http_client do
      http_client.post(url, params: params, credential: credential)
    else
      Req.new(url: url, retry: false)
      |> AuthPlugin.attach(api_key: credential.api_key, api_secret: credential.api_secret)
      |> Req.post([params: params] ++ req_opts)
    end
  end

  defp get_signed(url, params, credential, opts) do
    http_client = Keyword.get(opts, :http_client)

    if http_client do
      http_client.get(url, params: params, credential: credential)
    else
      Req.new(url: url)
      |> AuthPlugin.attach(api_key: credential.api_key, api_secret: credential.api_secret)
      |> Req.get(params: params)
    end
  end

  defp get_public(url, params, opts) do
    http_client = Keyword.get(opts, :http_client)

    if http_client do
      http_client.get(url, params: params)
    else
      Req.get(url, params: params)
    end
  end

  defp parse_buy_response(body, symbol) do
    fills = body["fills"] || []
    base_asset = extract_base_asset(symbol)

    {total_qty, total_cost, base_commission} =
      Enum.reduce(fills, {Decimal.new(0), Decimal.new(0), Decimal.new(0)}, fn fill,
                                                                              {qty_acc, cost_acc,
                                                                               comm_acc} ->
        qty = Decimal.new(fill["qty"])
        price = Decimal.new(fill["price"])
        cost = Decimal.mult(qty, price)

        commission =
          if fill["commissionAsset"] == base_asset do
            Decimal.new(fill["commission"] || "0")
          else
            Decimal.new(0)
          end

        {Decimal.add(qty_acc, qty), Decimal.add(cost_acc, cost),
         Decimal.add(comm_acc, commission)}
      end)

    fill_price =
      if Decimal.gt?(total_qty, 0) do
        Decimal.div(total_cost, total_qty)
      else
        Decimal.new(body["price"] || "0")
      end

    gross_qty = Decimal.new(body["executedQty"] || to_string(total_qty))
    net_qty = Decimal.sub(gross_qty, base_commission)

    {:ok,
     %{
       order_id: body["orderId"],
       symbol: symbol,
       fill_price: fill_price,
       filled_qty: net_qty,
       quote_qty: Decimal.new(body["cummulativeQuoteQty"] || to_string(total_cost))
     }}
  end

  defp parse_balance(body, asset) do
    balances = body["balances"] || []

    free =
      Enum.find_value(balances, Decimal.new("0"), fn
        %{"asset" => ^asset, "free" => free} -> Decimal.new(free)
        _ -> nil
      end)

    {:ok, %{free: free, asset: asset}}
  end

  defp parse_symbol_filters(body) do
    symbols = body["symbols"] || []

    case symbols do
      [symbol_info | _] ->
        filters = symbol_info["filters"] || []

        tick_size =
          Enum.find_value(filters, Decimal.new("0.00000001"), fn
            %{"filterType" => "PRICE_FILTER", "tickSize" => tick} -> Decimal.new(tick)
            _ -> nil
          end)

        step_size =
          Enum.find_value(filters, Decimal.new("0.00000001"), fn
            %{"filterType" => "LOT_SIZE", "stepSize" => step} -> Decimal.new(step)
            _ -> nil
          end)

        {:ok, %{tick_size: tick_size, step_size: step_size}}

      [] ->
        {:error, {:invalid_symbol, "Symbol not found in exchange info"}}
    end
  end

  defp round_to_tick(price, nil), do: price

  defp round_to_tick(price, tick_size) do
    price
    |> Decimal.div(tick_size)
    |> Decimal.round(0, :floor)
    |> Decimal.mult(tick_size)
  end

  defp parse_oco_response(body) do
    orders = body["orderReports"] || body["orders"] || []

    {tp_id, sl_id} =
      Enum.reduce(orders, {nil, nil}, fn order, {tp, sl} ->
        cond do
          order["type"] == "LIMIT_MAKER" -> {order["orderId"], sl}
          order["type"] in ["STOP_LOSS_LIMIT", "STOP_LOSS"] -> {tp, order["orderId"]}
          true -> {tp, sl}
        end
      end)

    {:ok,
     %{
       order_list_id: body["orderListId"],
       tp_order_id: tp_id,
       sl_order_id: sl_id
     }}
  end

  defp classify_error(%{"code" => code, "msg" => msg}) do
    case code do
      -2010 ->
        {:error, {:insufficient_balance, msg}}

      -1121 ->
        {:error, {:invalid_symbol, msg}}

      -2021 ->
        {:error, {:price_rule_violation, msg}}

      -1013 ->
        {:error, {:filter_failure, msg}}

      code when code in [-2014, -2015, -1022] ->
        {:error, {:auth_error, msg}}

      _ ->
        Log.api_error("Binance trading API error: code=#{code}, msg=#{msg}",
          module: :binance_trading,
          operation: :trading,
          exchange: :binance,
          reason: "#{code}: #{msg}"
        )

        {:error, {:api_error, msg}}
    end
  end

  defp classify_error(body) do
    {:error, {:api_error, inspect(body)}}
  end

  defp extract_base_asset(symbol) do
    case String.split(symbol, "/") do
      [base, _quote] -> String.upcase(base)
      _ -> raise ArgumentError, "Expected BASE/QUOTE format, got: #{symbol}"
    end
  end

  defp normalize_symbol(symbol) do
    symbol
    |> String.upcase()
    |> String.replace("/", "")
  end

  defp generate_client_order_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_binary(n), do: Decimal.new(n)
end
