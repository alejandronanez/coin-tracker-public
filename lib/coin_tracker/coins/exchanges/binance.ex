defmodule CoinTracker.Coins.Exchanges.Binance do
  @moduledoc """
  Binance exchange integration for fetching cryptocurrency prices.
  """

  @behaviour CoinTracker.Coins.Exchanges.Behaviour

  alias CoinTracker.Coins.HTTPClient
  alias CoinTracker.Log

  @binance_api_url "https://api.binance.com/api/v3/ticker/price"

  @impl true
  def fetch_prices(symbols, opts \\ []) do
    # this code is here mostly for tests as it allow us to do dependency injection
    # in production, we don't pass anything to it, but in our tests, we pass the
    # mocked version of the HttpClient so we can return what we need.
    http_client = Keyword.get(opts, :http_client, HTTPClient.ReqAdapter)

    symbols
    |> normalize_symbols()
    |> call_api(http_client)
    |> parse_response()
  end

  defp normalize_symbols(symbols) do
    Enum.map(symbols, fn symbol ->
      symbol
      |> String.upcase()
      |> String.replace("/", "")
    end)
  end

  defp call_api(symbols, http_client) do
    symbols_json = Jason.encode!(symbols)

    Log.debug("Calling Binance API for #{length(symbols)} symbols",
      module: :binance,
      operation: :fetch_prices,
      exchange: :binance
    )

    http_client.get(@binance_api_url, params: [symbols: symbols_json])
  end

  defp parse_response({:ok, %{status: 200, body: coins}}) do
    prices =
      Enum.map(coins, fn coin ->
        %{
          symbol: denormalize_symbol(coin["symbol"]),
          price: Decimal.new(coin["price"])
        }
      end)

    {:ok, prices}
  end

  defp parse_response({:ok, %{status: _status, body: error}}) do
    message = error["msg"] || "Unknown API error"

    # "Invalid symbol" is expected when trying fallback exchanges - use debug level
    if message == "Invalid symbol." do
      Log.debug("Binance: symbol not found",
        module: :binance,
        operation: :fetch_prices,
        exchange: :binance
      )
    else
      Log.api_error("Binance API error: #{message}",
        module: :binance,
        operation: :fetch_prices,
        exchange: :binance,
        reason: inspect(error)
      )
    end

    {:error, {:api_error, message}}
  end

  defp parse_response({:error, reason}) do
    Log.network_error("Binance network error",
      module: :binance,
      operation: :fetch_prices,
      exchange: :binance,
      reason: inspect(reason)
    )

    {:error, :network_error}
  end

  # Helper to convert "ETHUSDT" → "ETH/USDT"
  defp denormalize_symbol(binance_symbol) do
    base = String.replace_suffix(binance_symbol, "USDT", "")
    "#{base}/USDT"
  end
end
