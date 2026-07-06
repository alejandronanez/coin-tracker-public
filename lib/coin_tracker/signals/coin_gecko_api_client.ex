defmodule CoinTracker.Signals.CoinGeckoApiClient do
  @moduledoc """
  Client for fetching market data from the CoinGecko `/coins/markets` endpoint.

  Exposes `fetch_top_500/0`, which pages the endpoint twice (per_page=250,
  page=1 then page=2) and returns a flat list of normalized rows ordered by
  market cap descending — the natural order returned by CoinGecko.

  ## Configuration

      config :coin_tracker, CoinTracker.Signals.CoinGeckoApiClient,
        base_url: "https://api.coingecko.com/api/v3",
        # Optional: set to enable the demo API key path
        api_key: nil,
        retry: :transient,
        receive_timeout: 5_000

  In test, retries are disabled and timeouts are short:

      config :coin_tracker, CoinTracker.Signals.CoinGeckoApiClient,
        retry: false,
        receive_timeout: 100

  ## Returned row shape

      %{
        coingecko_id: "bitcoin",
        symbol: "BTC",
        name: "Bitcoin",
        price_usd: #Decimal<...>,
        market_cap_usd: #Decimal<...>,
        total_volume_usd: #Decimal<...>,
        price_change_percentage_24h: #Decimal<...>
      }
  """

  alias CoinTracker.Log
  alias CoinTracker.Signals.HTTPClient

  @endpoint "/coins/markets"
  @per_page 250
  @pages [1, 2]

  @doc """
  Fetches the top 500 coins by market cap from CoinGecko. Pages twice.

  Returns `{:ok, [row, ...]}` with up to 500 rows, or `{:error, reason}` on the
  first failure encountered.
  """
  def fetch_top_500(opts \\ []) do
    {http_client, _opts} = Keyword.pop(opts, :http_client, HTTPClient.ReqAdapter)

    Enum.reduce_while(@pages, {:ok, []}, fn page, {:ok, acc} ->
      case fetch_page(page, http_client) do
        {:ok, rows} -> {:cont, {:ok, acc ++ rows}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Private

  defp fetch_page(page, http_client) do
    url = build_url(@endpoint)
    params = build_params(page)
    headers = build_headers()
    req_opts = build_req_options()

    Log.info("Fetching CoinGecko markets page #{page}",
      module: :coingecko,
      operation: :fetch
    )

    case http_client.get(url, [params: params, headers: headers] ++ req_opts) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        {:ok, Enum.flat_map(body, &transform_row/1)}

      {:ok, %Req.Response{status: 200, body: body}} ->
        Log.api_error("CoinGecko response was not a list",
          module: :coingecko,
          operation: :parse,
          reason: inspect(body)
        )

        {:error, :parse_error}

      {:ok, %Req.Response{status: status, body: body}} ->
        Log.api_error("CoinGecko request failed with status #{status}",
          module: :coingecko,
          operation: :fetch,
          reason: inspect(body)
        )

        {:error, {:http_error, status, body}}

      {:error, exception} ->
        Log.network_error("CoinGecko request failed",
          module: :coingecko,
          operation: :fetch,
          reason: inspect(exception)
        )

        {:error, :network_error}
    end
  end

  defp transform_row(%{"id" => id, "symbol" => symbol} = row)
       when is_binary(id) and is_binary(symbol) do
    [
      %{
        coingecko_id: id,
        symbol: String.upcase(symbol),
        name: Map.get(row, "name"),
        price_usd: parse_decimal(row["current_price"]),
        market_cap_usd: parse_decimal(row["market_cap"]),
        total_volume_usd: parse_decimal(row["total_volume"]),
        price_change_percentage_24h: parse_decimal(row["price_change_percentage_24h"])
      }
    ]
  end

  defp transform_row(_), do: []

  defp parse_decimal(nil), do: nil

  defp parse_decimal(value) when is_integer(value), do: Decimal.new(value)

  defp parse_decimal(value) when is_float(value), do: Decimal.from_float(value)

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end

  defp parse_decimal(_), do: nil

  defp build_url(endpoint_path) do
    base_url = get_config(:base_url, "https://api.coingecko.com/api/v3")
    base_url <> endpoint_path
  end

  defp build_params(page) do
    [
      vs_currency: "usd",
      order: "market_cap_desc",
      per_page: @per_page,
      page: page,
      sparkline: false,
      price_change_percentage: "24h"
    ]
  end

  defp build_headers do
    case get_config(:api_key, nil) do
      nil -> []
      "" -> []
      api_key -> [{"x-cg-demo-api-key", api_key}]
    end
  end

  defp build_req_options do
    config = Application.get_env(:coin_tracker, __MODULE__, [])

    opts = []

    opts =
      if Keyword.has_key?(config, :retry) do
        Keyword.put(opts, :retry, Keyword.get(config, :retry))
      else
        opts
      end

    opts =
      if Keyword.has_key?(config, :receive_timeout) do
        Keyword.put(opts, :receive_timeout, Keyword.get(config, :receive_timeout))
      else
        opts
      end

    opts
  end

  defp get_config(key, default) do
    Application.get_env(:coin_tracker, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
