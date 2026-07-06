defmodule CoinTracker.Signals.SignalSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  alias CoinTracker.Signals.Signal

  schema "signal_snapshots" do
    belongs_to :signal, Signal

    field :snapshot_at, :utc_datetime
    field :symbol, :string

    field :current_volume_24h, :decimal
    field :initial_volume_24h, :decimal
    field :max_price_usd, :decimal
    field :current_price_usd, :decimal

    field :in_top, :boolean
    field :position, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :signal_id,
      :snapshot_at,
      :symbol,
      :current_volume_24h,
      :initial_volume_24h,
      :max_price_usd,
      :current_price_usd,
      :in_top,
      :position
    ])
    |> validate_required([
      :signal_id,
      :snapshot_at,
      :symbol,
      :in_top
    ])
    |> foreign_key_constraint(:signal_id)
  end
end
