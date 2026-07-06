defmodule CoinTracker.Signals.CoingeckoSnapshot do
  @moduledoc """
  Point-in-time snapshot of CoinGecko market data for a single coin.

  Persisted on every successful CoinGeckoPoller tick so we can later
  compute deltas (e.g. 24h volume change) that CoinGecko does not expose
  natively. Keyed by `(coingecko_id, snapshot_at)` so re-runs of the
  same tick are idempotent.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "coingecko_snapshots" do
    field :coingecko_id, :string
    field :symbol, :string
    field :snapshot_at, :utc_datetime

    field :total_volume_usd, :decimal
    field :price_usd, :decimal
    field :price_change_percentage_24h, :decimal
    field :market_cap_usd, :decimal

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :coingecko_id,
      :symbol,
      :snapshot_at,
      :total_volume_usd,
      :price_usd,
      :price_change_percentage_24h,
      :market_cap_usd
    ])
    |> validate_required([:coingecko_id, :symbol, :snapshot_at])
    |> unique_constraint([:coingecko_id, :snapshot_at],
      name: :coingecko_snapshots_coingecko_id_snapshot_at_index
    )
  end
end
