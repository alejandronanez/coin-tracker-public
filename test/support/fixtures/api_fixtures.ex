defmodule CoinTracker.ApiFixtures do
  @moduledoc """
  Test fixtures for external API responses.

  This module provides fixture functions that return JSON response strings
  for use with Bypass in HTTP client tests. Each function accepts optional
  overrides to customize specific fields while maintaining realistic defaults.
  """

  @doc """
  Returns a successful top10 API response JSON string.

  ## Options

    * `:coins` - List of coin maps to include. Each coin map can contain:
      * `:symbol` - Coin symbol (required)
      * `:name` - Coin name (required)
      * `:initial_price_usd` - Initial price
      * `:max_price_usd` - Max price
      * `:max_increase_percentage` - Max increase percentage
      * `:in_top_since` - ISO8601 datetime string
      * `:in_top` - Boolean
      * `:volumen24h` - 24h volume
      * `:position` - Coin position
    * `:timestamp` - ISO8601 timestamp for the response
    * `:count` - Override the count field

  ## Examples

      # Use default response with 3 realistic coins
      api_top10_response()

      # Override with custom coins
      api_top10_response(coins: [
        %{symbol: "BTC", name: "Bitcoin", initial_price_usd: 50000.0, in_top: true}
      ])

      # Empty response
      api_top10_response(coins: [])
  """
  def api_top10_response(opts \\ []) do
    coins = Keyword.get(opts, :coins, default_top10_coins())
    timestamp = Keyword.get(opts, :timestamp, "2025-10-18T03:30:24+00:00")
    count = Keyword.get(opts, :count, length(coins))

    Jason.encode!(%{
      "status" => "success",
      "api_version" => "3.7.1",
      "mode" => "live",
      "timestamp" => timestamp,
      "data" => %{
        "top_criptomonedas" => Enum.map(coins, &build_coin/1)
      },
      "count" => count
    })
  end

  @doc """
  Returns a successful grace period API response JSON string.

  ## Options

    * `:coins` - List of coin maps (similar structure to top10)
    * `:timestamp` - ISO8601 timestamp
    * `:count` - Override the count field
  """
  def api_grace_period_response(opts \\ []) do
    coins = Keyword.get(opts, :coins, default_grace_period_coins())
    timestamp = Keyword.get(opts, :timestamp, "2025-10-18T03:36:57+00:00")
    count = Keyword.get(opts, :count, length(coins))

    Jason.encode!(%{
      "status" => "success",
      "api_version" => "3.7.1",
      "mode" => "live",
      "timestamp" => timestamp,
      "data" => %{
        "monedas_periodo_gracia" => Enum.map(coins, &build_coin/1)
      },
      "count" => count
    })
  end

  @doc """
  Returns an API error response JSON string.

  ## Options

    * `:message` - Error message string (required)
    * `:status` - Status field value (default: "error")

  ## Examples

      api_error_response(message: "La clave de API es inválida")
      api_error_response(message: "Rate limited", status: "error")
  """
  def api_error_response(opts) do
    message = Keyword.fetch!(opts, :message)
    status = Keyword.get(opts, :status, "error")

    Jason.encode!(%{
      "status" => status,
      "message" => message
    })
  end

  @doc """
  Returns an invalid/malformed API response for testing error handling.

  ## Variants

    * `:missing_status` - Response missing the status field
    * `:non_success_status` - Response with status != "success"
    * `:missing_data_wrapper` - Response missing the data wrapper
    * `:missing_nested_key` - Response with wrong nested key

  ## Examples

      # Missing status field
      api_invalid_response(:missing_status)

      # Non-success status
      api_invalid_response(:non_success_status)
  """
  def api_invalid_response(:missing_status) do
    Jason.encode!(%{
      "data" => %{"top_criptomonedas" => []}
    })
  end

  def api_invalid_response(:non_success_status) do
    Jason.encode!(%{
      "status" => "error",
      "data" => %{"top_criptomonedas" => []}
    })
  end

  def api_invalid_response(:missing_data_wrapper) do
    Jason.encode!(%{
      "status" => "success",
      "top_criptomonedas" => []
    })
  end

  def api_invalid_response(:missing_nested_key) do
    Jason.encode!(%{
      "status" => "success",
      "data" => %{"wrong_key" => []}
    })
  end

  @doc """
  Builds a minimal valid coin map for use in custom responses.

  ## Options

  Any coin field can be overridden. Common fields:
    * `:symbol` - Coin symbol (default: "BTC")
    * `:name` - Coin name (default: "Bitcoin")
    * `:in_top` - Boolean (default: true)
    * `:in_top_since` - ISO8601 datetime string
    * `:initial_price_usd` - Initial price
    * `:max_price_usd` - Max price
    * `:volumen24h` - 24h volume

  ## Examples

      coin(symbol: "ETH", name: "Ethereum", initial_price_usd: 3000.0)
      coin(symbol: "BTC", initial_price_usd: 50000.0)
  """
  def coin(overrides \\ []) do
    Keyword.merge(
      [
        symbol: "BTC",
        name: "Bitcoin",
        in_top: true,
        in_top_since: "2025-10-18T00:00:00+00:00"
      ],
      overrides
    )
    |> Enum.into(%{})
  end

  # Private builder functions

  defp build_coin(coin_map) do
    # Only include fields that are present in the map
    # Convert atom keys to strings for JSON encoding
    coin_map
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.into(%{})
  end

  defp default_top10_coins do
    [
      %{
        position: 9,
        symbol: "UNI",
        name: "UNI",
        initial_price_usd: 6.14,
        max_price_usd: 6.14,
        max_increase_percentage: 0,
        in_top_since: "2025-10-18T03:16:42+00:00",
        in_top: true,
        volumen24h: 355_192_507
      },
      %{
        position: 2,
        symbol: "RSR",
        name: "Reserve Rights",
        initial_price_usd: 0.006263,
        max_price_usd: 0.006993,
        max_increase_percentage: 11.67,
        in_top_since: "2025-10-15T04:20:20+00:00",
        in_top: true,
        volumen24h: 49_102_244
      },
      %{
        position: 1,
        symbol: "TRAC",
        name: "OriginTrail",
        initial_price_usd: 0.6047,
        max_price_usd: 0.8348,
        max_increase_percentage: 38.06,
        in_top_since: "2025-10-12T00:50:02+00:00",
        in_top: true,
        volumen24h: 9_972_980
      }
    ]
  end

  defp default_grace_period_coins do
    [
      %{
        symbol: "SNX",
        name: "Synthetix",
        initial_price_usd: 1.29,
        max_price_usd: 2.51,
        max_increase_percentage: 94.57,
        in_top_since: "2025-10-12T16:10:03+00:00",
        exit_date: "2025-10-18T02:40:02+00:00",
        in_top: false
      },
      %{
        symbol: "COMP",
        name: "Compound",
        initial_price_usd: 33.39,
        max_price_usd: 33.97,
        max_increase_percentage: 1.74,
        in_top_since: "2025-10-18T00:25:02+00:00",
        exit_date: "2025-10-18T02:40:02+00:00",
        in_top: false
      }
    ]
  end
end
