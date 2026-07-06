defmodule CoinTracker.Signals.CoinscanApiClient do
  @moduledoc """
  Client for fetching cryptocurrency signals from CoinScanX API.

  This module provides functions to query two different API endpoints:
  - `/v3/top10` - Fetches the top 10 cryptocurrencies currently being tracked
  - `/v3/periodo-gracia` - Fetches cryptocurrencies in grace period (recently exited from top 10)

  ## Configuration

  Configure in `config/dev.exs` or `config/runtime.exs`:

      config :coin_tracker, CoinTracker.Signals.CoinscanApiClient,
        base_url: "https://api.coinscanx.com",
        api_key: "YOUR_API_KEY_HERE"

  The API key is sent as a Bearer token in the `Authorization` header on every request.

  ## Retry Behavior

  In production, this client uses Req's default retry logic (3 attempts with exponential backoff)
  for resilience against temporary network failures and server errors.

  In test environment, retries are disabled via configuration for deterministic, fast test behavior:

      # config/test.exs
      config :coin_tracker, CoinTracker.Signals.CoinscanApiClient,
        retry: false,
        receive_timeout: 100

  You can customize retry behavior for other environments:

      # Disable retries
      config :coin_tracker, CoinTracker.Signals.CoinscanApiClient,
        retry: false

      # Custom retry (production default is :transient which retries on network errors and 5xx)
      config :coin_tracker, CoinTracker.Signals.CoinscanApiClient,
        retry: :transient,
        max_retries: 3
  """

  alias CoinTracker.Log
  alias CoinTracker.Signals.Signal
  alias CoinTracker.Signals.HTTPClient

  @doc """
  Fetches the top 10 cryptocurrencies currently being tracked.

  Returns signals with `in_top: true` and `active: true`.

  ## Examples

      iex> fetch_top_10()
      {:ok, [%Signal{symbol: "TRAC", in_top: true, active: true}, ...]}

      iex> fetch_top_10()
      {:error, :network_error}
  """
  def fetch_top_10(opts \\ []) do
    {http_client, opts} = Keyword.pop(opts, :http_client, HTTPClient.ReqAdapter)
    make_request("/v3/top10", :top_criptomonedas, opts, http_client)
  end

  @doc """
  Fetches cryptocurrencies in grace period (recently exited from top 10).

  Returns signals with `in_top: false` and `active: true`, including exit dates.

  ## Examples

      iex> fetch_grace_period()
      {:ok, [%Signal{symbol: "SNX", in_top: false, active: false, exit_date: ~U[...]}, ...]}

      iex> fetch_grace_period()
      {:error, :network_error}
  """
  def fetch_grace_period(opts \\ []) do
    {http_client, opts} = Keyword.pop(opts, :http_client, HTTPClient.ReqAdapter)
    opts_with_limit = Keyword.put_new(opts, :limit, 200)
    make_request("/v3/periodo-gracia", :monedas_periodo_gracia, opts_with_limit, http_client)
  end

  # Private functions

  defp make_request(endpoint_path, data_key, opts, http_client) do
    url = build_url(endpoint_path)
    req_opts = build_req_options()
    api_key = get_config(:api_key)

    request_opts = [params: opts, auth: {:bearer, api_key}] ++ req_opts

    Log.info("Fetching data from Coinscan API: #{endpoint_path}",
      module: :coinscan,
      operation: :fetch
    )

    case http_client.get(url, request_opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse_response(body, data_key)

      {:ok, %Req.Response{status: status, body: body}} ->
        Log.api_error("Coinscan API request failed with status #{status}",
          module: :coinscan,
          operation: :fetch,
          reason: inspect(body)
        )

        {:error, {:http_error, status, body}}

      {:error, exception} ->
        Log.network_error("Coinscan API request failed",
          module: :coinscan,
          operation: :fetch,
          reason: inspect(exception)
        )

        {:error, :network_error}
    end
  end

  defp build_url(endpoint_path) do
    base_url = get_config(:base_url)
    "#{base_url}#{endpoint_path}"
  end

  defp build_req_options do
    config = Application.get_env(:coin_tracker, __MODULE__, [])

    opts = []

    # Add retry configuration (false in test, default in prod)
    # Use has_key? because retry: false is falsy and would be skipped with simple if check
    opts =
      if Keyword.has_key?(config, :retry) do
        Keyword.put(opts, :retry, Keyword.get(config, :retry))
      else
        opts
      end

    # Add timeout configuration (100ms in test, default in prod)
    opts =
      if Keyword.has_key?(config, :receive_timeout) do
        Keyword.put(opts, :receive_timeout, Keyword.get(config, :receive_timeout))
      else
        opts
      end

    opts
  end

  defp parse_response(body, data_key) do
    # CoinScanX API returns: {"status": "success", "data": {"top_criptomonedas": [...]}, ...}
    # or: {"status": "success", "data": {"monedas_periodo_gracia": [...]}, ...}

    with {:ok, status} <- Map.fetch(body, "status"),
         true <- status == "success",
         {:ok, data} <- Map.fetch(body, "data"),
         {:ok, items} <- Map.fetch(data, Atom.to_string(data_key)),
         true <- is_list(items) do
      signals = Enum.map(items, &transform_to_signal/1)
      {:ok, signals}
    else
      {:error, :key_not_found} ->
        Log.api_error("Missing expected key in Coinscan API response",
          module: :coinscan,
          operation: :parse,
          reason: inspect(body)
        )

        {:error, :parse_error}

      false ->
        Log.api_error("Coinscan API returned non-success status or invalid data structure",
          module: :coinscan,
          operation: :parse,
          reason: inspect(body)
        )

        {:error, :parse_error}

      error ->
        Log.api_error("Failed to parse Coinscan API response",
          module: :coinscan,
          operation: :parse,
          reason: inspect(error)
        )

        {:error, :parse_error}
    end
  rescue
    error ->
      Log.api_error("Exception while parsing Coinscan API response",
        module: :coinscan,
        operation: :parse,
        reason: inspect(error)
      )

      {:error, :parse_error}
  end

  defp transform_to_signal(api_data) do
    in_top = Map.get(api_data, "in_top", false)
    in_top_since = parse_datetime(api_data, "in_top_since")
    {initial_volume_24h, current_volume_24h} = build_volume_values(api_data, in_top_since)

    %Signal{
      symbol: Map.get(api_data, "symbol"),
      name: Map.get(api_data, "name"),
      initial_volume_24h: initial_volume_24h,
      current_volume_24h: current_volume_24h,
      # Note: current_price_usd is not provided by the API
      # Setting to nil - you may want to fetch this separately or use max_price_usd
      current_price_usd: nil,
      initial_price_usd: parse_decimal(api_data, "initial_price_usd"),
      max_price_usd: parse_decimal(api_data, "max_price_usd"),
      max_increase_percentage: parse_decimal(api_data, "max_increase_percentage"),
      in_top: in_top,
      active: true,
      in_top_since: in_top_since,
      exit_date: parse_datetime(api_data, "exit_date"),
      position: parse_integer(api_data, "rank")
    }
  end

  defp build_volume_values(api_data, _in_top_since) do
    # `nil` flows through to the upsert, where COALESCE preserves the existing
    # current_volume_24h instead of clobbering it (e.g. on a transient API
    # response missing the field). The upsert keeps initial_volume_24h
    # immutable after first insert.
    current_volume = parse_decimal(api_data, "volumen24h")
    {current_volume, current_volume}
  end

  defp parse_decimal(map, key) when is_map(map) do
    case Map.get(map, key) do
      nil ->
        nil

      value when is_number(value) ->
        Decimal.from_float(value * 1.0)

      value when is_binary(value) ->
        case Decimal.parse(value) do
          {decimal, _} -> decimal
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_decimal(_, _), do: nil

  defp parse_integer(map, key) when is_map(map) do
    case Map.get(map, key) do
      nil ->
        nil

      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, _} -> int
          :error -> nil
        end

      value when is_float(value) ->
        round(value)

      _ ->
        nil
    end
  end

  defp parse_integer(_, _), do: nil

  defp parse_datetime(map, key) when is_map(map) do
    case Map.get(map, key) do
      nil ->
        nil

      datetime_string when is_binary(datetime_string) ->
        case DateTime.from_iso8601(datetime_string) do
          {:ok, datetime, _offset} -> datetime
          {:error, _} -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_datetime(_, _), do: nil

  defp get_config(key) do
    Application.get_env(:coin_tracker, __MODULE__, [])
    |> Keyword.get(key)
  end
end
