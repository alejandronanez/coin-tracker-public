defmodule CoinTracker.Signals.HTTPClient.ReqAdapter do
  @moduledoc """
  Real HTTP client implementation using Req library for the Signals context.
  """

  @behaviour CoinTracker.Signals.HTTPClient

  @impl true
  def get(url, opts \\ []) do
    Req.get(url, opts)
  end
end
