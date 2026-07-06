defmodule CoinTracker.Trading.AutoBuy do
  @moduledoc """
  Orchestrates the three-step automatic buying flow:

  1. Market buy on exchange
  2. Place OCO sell order (take-profit + stop-loss)
  3. Create position in the app

  Exchange-agnostic — dispatches through `TradingClient`, never directly
  to a specific exchange module. The exchange is determined by the signal's
  `symbol_price.exchange`.
  """

  alias CoinTracker.Accounts
  alias CoinTracker.Coins.TradingClient
  alias CoinTracker.Log
  alias CoinTracker.TelegramClient.TelegramService
  alias CoinTracker.Trading

  @safety_margin Decimal.new("0.99")
  @min_order_usdt Decimal.new("1")

  @doc """
  Executes the full auto-buy flow for a signal.

  ## Parameters

  - `user` - The user placing the trade
  - `signal` - The signal to trade (must have `symbol_price` preloaded)
  - `amount_usdt` - Amount in USDT to spend (Decimal). Automatically capped to
    available balance * 0.99 if it exceeds account funds.
  - `trade_params` - Map with `:take_profit` and `:stop_loss` percentages (positive numbers)
  - `opts` - Keyword list of options (e.g., `[http_client: MockHTTP]` for testing)

  ## Returns

  - `{:ok, %{position: position, buy_order: buy, oco_order: oco}}` — full success
  - `{:error, reason}` — any failure (balance too low, buy failed, OCO failed, etc.)
  """
  def execute(user, signal, amount_usdt, trade_params, opts \\ []) do
    take_profit = Map.fetch!(trade_params, :take_profit)
    stop_loss = Map.fetch!(trade_params, :stop_loss)
    exchange = signal.symbol_price.exchange
    symbol = signal.symbol_price.symbol_pair

    with {:ok, credential} <- fetch_credential(user.id, exchange),
         {:ok, filters} <- TradingClient.fetch_symbol_filters(exchange, symbol, opts),
         {:ok, balance} <- TradingClient.fetch_balance(exchange, credential, "USDT", opts),
         {:ok, capped_amount} <- cap_to_balance(amount_usdt, balance.free),
         {:ok, buy_result} <-
           TradingClient.market_buy(exchange, credential, symbol, capped_amount, opts),
         _ <- Accounts.update_credential_last_used(credential) do
      fill_price = buy_result.fill_price
      tick_size = filters.tick_size
      step_size = filters.step_size

      # Round quantity down to step_size to satisfy Binance LOT_SIZE filter.
      # round_to_tick floors to the nearest increment — works for both
      # price tick_size and quantity step_size.
      filled_qty = round_to_tick(buy_result.filled_qty, step_size)

      tp_pct = to_decimal(take_profit)
      sl_pct = to_decimal(stop_loss)

      tp_price =
        fill_price
        |> Decimal.mult(Decimal.add(1, Decimal.div(tp_pct, 100)))
        |> round_to_tick(tick_size)

      sl_price =
        fill_price
        |> Decimal.mult(Decimal.sub(1, Decimal.div(sl_pct, 100)))
        |> round_to_tick(tick_size)

      position_attrs = %{
        "symbol" => symbol,
        "exchange" => Atom.to_string(exchange),
        "entry_price" => Decimal.to_string(fill_price),
        "stop_loss_percent" => Decimal.to_string(Decimal.negate(sl_pct)),
        "take_profit_percent" => Decimal.to_string(tp_pct),
        "amount_invested" => Decimal.to_string(buy_result.quote_qty),
        "current_threshold_zone" => "1",
        "source" => "auto_buy"
      }

      oco_opts = Keyword.put(opts, :tick_size, tick_size)

      case TradingClient.place_oco_sell(
             exchange,
             credential,
             symbol,
             filled_qty,
             tp_price,
             sl_price,
             oco_opts
           ) do
        {:ok, oco_result} ->
          {:ok, position} = Trading.create_position(user.id, position_attrs, opts)

          {:ok,
           %{
             position: position,
             buy_order: buy_result,
             oco_order: oco_result
           }}

        {:error, oco_reason} ->
          Log.api_error("OCO placement failed after successful buy",
            module: :trading,
            operation: :auto_buy,
            symbol: symbol,
            error: inspect(oco_reason)
          )

          send_oco_failure_alert(user.id, symbol, filled_qty, fill_price, oco_reason)

          {:error, {:oco_failed, %{buy_order: buy_result, reason: oco_reason}}}
      end
    end
  end

  defp fetch_credential(user_id, exchange) do
    case Accounts.get_exchange_credential(user_id, exchange) do
      nil -> {:error, :no_credentials}
      credential -> {:ok, credential}
    end
  end

  defp send_oco_failure_alert(user_id, symbol, quantity, fill_price, error) do
    message = """
    ⚠️ URGENT: OCO Order Failed

    Your market buy for #{symbol} succeeded, but the OCO sell order could not be placed.

    Details:
    - Symbol: #{symbol}
    - Quantity: #{quantity}
    - Fill Price: $#{Decimal.to_string(fill_price)}
    - Error: #{format_error(error)}

    ⚠️ You need to place a stop-loss order manually on Binance to protect your position.
    """

    TelegramService.send_message(user_id, message, kind: :auto_buy_failure)
  end

  defp format_error({:price_rule_violation, msg}), do: "Price rule violation: #{msg}"
  defp format_error({:insufficient_balance, msg}), do: "Insufficient balance: #{msg}"
  defp format_error({:invalid_symbol, msg}), do: "Invalid symbol: #{msg}"
  defp format_error({:auth_error, msg}), do: "Authentication error: #{msg}"
  defp format_error({:filter_failure, msg}), do: "Filter failure: #{msg}"
  defp format_error({:api_error, msg}), do: "API error: #{msg}"
  defp format_error({:exchange_not_supported, msg}), do: msg
  defp format_error(other), do: inspect(other)

  defp cap_to_balance(requested, available) do
    max_spend = Decimal.mult(available, @safety_margin)

    capped = Decimal.min(requested, max_spend)

    if Decimal.lt?(capped, @min_order_usdt) do
      {:error,
       {:insufficient_balance,
        "Available balance ($#{Decimal.to_string(available)} USDT) is too low after applying safety margin"}}
    else
      {:ok, capped}
    end
  end

  defp round_to_tick(price, tick_size) do
    price
    |> Decimal.div(tick_size)
    |> Decimal.round(0, :floor)
    |> Decimal.mult(tick_size)
  end

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp to_decimal(n) when is_binary(n), do: Decimal.new(n)
end
