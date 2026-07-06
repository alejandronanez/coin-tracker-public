defmodule CoinTracker.Signals.HTTPClient do
  @moduledoc """
  Behavior for HTTP client operations in the Signals context.
  Allows mocking HTTP requests in tests for the CoinscanApiClient.
  """

  @callback get(String.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
end
