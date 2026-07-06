defmodule CoinTracker.Coins do
  @moduledoc """
  The Coins context manages cryptocurrency market data.

  Provides functions for upserting symbol prices from exchange APIs
  and querying current prices for use by other contexts (e.g., Positions).
  """

  alias CoinTracker.Coins.SymbolPrice
  alias CoinTracker.Log
  alias CoinTracker.Repo

  @doc """
  Upserts a symbol price, updating if it exists or creating if it doesn't.

  After a successful upsert, broadcasts the update via Phoenix.PubSub on the
  "price_updates" topic to enable real-time UI updates.

  ## Parameters

    * `attrs` - Map containing `:exchange`, `:symbol_pair`, and `:current_price`

  ## Returns

    * `{:ok, %SymbolPrice{}}` - Successfully upserted symbol price
    * `{:error, %Ecto.Changeset{}}` - Validation or database error
  """
  def upsert_symbol_price(attrs) do
    result =
      %SymbolPrice{}
      |> SymbolPrice.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:current_price, :updated_at]},
        conflict_target: [:exchange, :symbol_pair]
      )

    case result do
      {:ok, symbol_price} ->
        broadcast_price_updated(symbol_price)
        {:ok, symbol_price}

      error ->
        error
    end
  end

  defp broadcast_price_updated(symbol_price) do
    Phoenix.PubSub.broadcast(
      CoinTracker.PubSub,
      "price_updates",
      {:price_updated, symbol_price}
    )

    Log.debug(
      "Broadcasted price update for #{symbol_price.symbol_pair} on #{symbol_price.exchange}",
      module: :coins,
      operation: :broadcast,
      exchange: symbol_price.exchange,
      symbol: symbol_price.symbol_pair
    )
  end
end
