defmodule CoinTracker.Coins.HTTPClient do
  @moduledoc """
  Behavior for HTTP client operations.
  Allows mocking HTTP requests in tests.
  """

  @callback get(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
end
