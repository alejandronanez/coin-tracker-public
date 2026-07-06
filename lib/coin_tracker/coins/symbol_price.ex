defmodule CoinTracker.Coins.SymbolPrice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "symbol_prices" do
    field :exchange, Ecto.Enum, values: [:binance_spot, :bitget_spot, :mexc_spot]
    field :symbol_pair, :string
    field :current_price, :decimal

    timestamps(type: :utc_datetime)
  end

  def changeset(symbol_price, attrs) do
    symbol_price
    |> cast(attrs, [
      :exchange,
      :symbol_pair,
      :current_price
    ])
    |> validate_required([:exchange, :symbol_pair, :current_price])
    |> unique_constraint([:exchange, :symbol_pair])
  end
end
