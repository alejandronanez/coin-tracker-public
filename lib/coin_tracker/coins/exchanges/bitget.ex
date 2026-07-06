defmodule CoinTracker.Coins.Exchanges.Bitget do
  @moduledoc """
  Bitget exchange integration for fetching cryptocurrency prices.
  """

  @behaviour CoinTracker.Coins.Exchanges.Behaviour

  alias CoinTracker.Coins.HTTPClient
  alias CoinTracker.Log

  @bitget_api_url "https://api.bitget.com/api/v2/spot/market/tickers"

  @impl true
  def fetch_prices(symbols, opts \\ []) do
    http_client = Keyword.get(opts, :http_client, HTTPClient.ReqAdapter)

    symbols
    |> normalize_symbols()
    |> fetch_prices_parallel(http_client)
  end

  defp normalize_symbols(symbols) do
    Enum.map(symbols, fn symbol ->
      symbol
      |> String.upcase()
      |> String.replace("/", "")
    end)
  end

  defp fetch_prices_parallel(symbols, http_client) do
    results =
      symbols
      |> Task.async_stream(&fetch_single(&1, http_client), timeout: :infinity)
      |> Enum.to_list()

    case collect_results(results) do
      {:ok, prices} -> {:ok, prices}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_single(symbol, http_client) do
    Log.debug("Calling Bitget API for symbol: #{symbol}",
      module: :bitget,
      operation: :fetch_prices,
      exchange: :bitget,
      symbol: symbol
    )

    case http_client.get(@bitget_api_url, params: [symbol: symbol]) do
      {:ok, %{status: 200, body: %{"code" => "00000", "data" => [coin | _]}}} ->
        {:ok,
         %{
           symbol: denormalize_symbol(coin["symbol"]),
           price: Decimal.new(coin["lastPr"])
         }}

      {:ok, %{status: 200, body: %{"code" => code, "msg" => msg}}} ->
        # Symbol not found errors are expected when trying fallback exchanges
        if String.contains?(String.downcase(msg || ""), ["symbol", "not exist", "invalid"]) do
          Log.debug("Bitget: symbol not found",
            module: :bitget,
            operation: :fetch_prices,
            exchange: :bitget,
            symbol: symbol
          )
        else
          Log.api_error("Bitget API error: code=#{code}, msg=#{msg}",
            module: :bitget,
            operation: :fetch_prices,
            exchange: :bitget,
            symbol: symbol
          )
        end

        {:error, {:api_error, msg}}

      {:ok, %{status: status, body: error}} ->
        message = error["msg"] || "Unknown API error"

        # Symbol not found errors are expected when trying fallback exchanges
        if String.contains?(String.downcase(message), ["symbol", "not exist", "invalid"]) do
          Log.debug("Bitget: symbol not found",
            module: :bitget,
            operation: :fetch_prices,
            exchange: :bitget,
            symbol: symbol
          )
        else
          Log.api_error("Bitget API error: status=#{status}, msg=#{message}",
            module: :bitget,
            operation: :fetch_prices,
            exchange: :bitget,
            symbol: symbol
          )
        end

        {:error, {:api_error, message}}

      {:error, reason} ->
        Log.network_error("Bitget network error",
          module: :bitget,
          operation: :fetch_prices,
          exchange: :bitget,
          symbol: symbol,
          reason: inspect(reason)
        )

        {:error, :network_error}
    end
  end

  defp collect_results(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, {:ok, price_data}}, {:ok, acc} ->
        {:cont, {:ok, [price_data | acc]}}

      {:ok, {:error, reason}}, _acc ->
        {:halt, {:error, reason}}

      {:exit, reason}, _acc ->
        Log.api_error("Bitget task exited unexpectedly",
          module: :bitget,
          operation: :fetch_prices,
          exchange: :bitget,
          reason: inspect(reason)
        )

        {:halt, {:error, :task_error}}
    end)
    |> case do
      {:ok, prices} -> {:ok, Enum.reverse(prices)}
      error -> error
    end
  end

  defp denormalize_symbol(bitget_symbol) do
    base = String.replace_suffix(bitget_symbol, "USDT", "")
    "#{base}/USDT"
  end
end
