defmodule CoinTracker.Coins.Exchanges.Binance.AuthPlugin do
  @moduledoc """
  Req request step that signs Binance API requests using HMAC-SHA256.

  Adds `timestamp`, computes the signature from the full query string,
  and sets the `X-MBX-APIKEY` header.
  """

  def attach(%Req.Request{} = request, opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    api_secret = Keyword.fetch!(opts, :api_secret)

    Req.Request.append_request_steps(request,
      binance_auth: fn req -> sign_request(req, api_key, api_secret) end
    )
  end

  defp sign_request(request, api_key, api_secret) do
    timestamp = System.os_time(:millisecond)

    params =
      (request.options[:params] || [])
      |> Keyword.put(:timestamp, timestamp)

    query_string =
      params
      |> Enum.sort_by(fn {k, _v} -> Atom.to_string(k) end)
      |> URI.encode_query()

    signature =
      :crypto.mac(:hmac, :sha256, api_secret, query_string)
      |> Base.encode16(case: :lower)

    signed_query = query_string <> "&signature=" <> signature

    %{request | url: %{request.url | query: signed_query}}
    |> Map.update!(:options, fn opts -> Map.delete(opts, :params) end)
    |> Req.Request.put_header("X-MBX-APIKEY", api_key)
  end
end
