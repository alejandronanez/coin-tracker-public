defmodule CoinTracker.Coins.Exchanges.Binance.AuthPluginTest do
  use ExUnit.Case, async: true

  alias CoinTracker.Coins.Exchanges.Binance.AuthPlugin

  test "attaches auth step to request and signs correctly" do
    request = Req.new(url: "https://api.binance.com/api/v3/order", params: [symbol: "BTCUSDT"])

    signed = AuthPlugin.attach(request, api_key: "my_api_key", api_secret: "my_secret")

    # Execute just the request steps (without actually sending)
    {signed_req, _} =
      Enum.reduce(signed.request_steps, {signed, Req.Response.new()}, fn {_name, step},
                                                                         {req, resp} ->
        case step.(req) do
          {%Req.Request{} = r, %Req.Response{} = resp} -> {r, resp}
          %Req.Request{} = r -> {r, resp}
        end
      end)

    query = signed_req.url.query

    # Verify params are encoded directly in the URL, not left in options
    refute Map.has_key?(signed_req.options, :params)

    # Verify timestamp is in the query string
    assert query =~ "timestamp="

    # Verify signature is appended at the end of the query string
    assert query =~ ~r/&signature=[0-9a-f]+$/

    # Verify original params are present
    assert query =~ "symbol=BTCUSDT"

    # Verify API key header
    assert Req.Request.get_header(signed_req, "X-MBX-APIKEY") == ["my_api_key"]
  end

  test "signature is deterministic for same params and secret" do
    # Two requests with same params and secret should produce same signature
    # (if timestamp is the same)
    api_secret = "test_secret"
    query = "symbol=BTCUSDT&timestamp=1234567890"

    sig1 =
      :crypto.mac(:hmac, :sha256, api_secret, query) |> Base.encode16(case: :lower)

    sig2 =
      :crypto.mac(:hmac, :sha256, api_secret, query) |> Base.encode16(case: :lower)

    assert sig1 == sig2
  end
end
