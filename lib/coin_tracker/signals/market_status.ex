defmodule CoinTracker.Signals.MarketStatus do
  use Ecto.Schema
  import Ecto.Changeset

  schema "market_statuses" do
    field :active_signals_count, :integer
    field :recorded_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(market_status, attrs) do
    market_status
    |> cast(attrs, [:active_signals_count, :recorded_at])
    |> validate_required([:active_signals_count, :recorded_at])
    |> validate_number(:active_signals_count,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 10
    )
  end
end
