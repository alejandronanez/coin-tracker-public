defmodule CoinTracker.Coins.HTTPClient.ReqAdapter do
  @moduledoc """
  Real HTTP client implementation using Req library.
  """

  @behaviour CoinTracker.Coins.HTTPClient

  @impl true
  def get(url, opts \\ []) do
    Req.get(url, opts)
  end
end
