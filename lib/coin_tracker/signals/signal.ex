defmodule CoinTracker.Signals.Signal do
  use Ecto.Schema
  import Ecto.Changeset

  schema "signals" do
    field :symbol, :string
    field :name, :string

    field :initial_volume_24h, :decimal
    field :current_volume_24h, :decimal

    field :current_price_usd, :decimal
    field :initial_price_usd, :decimal
    field :max_price_usd, :decimal
    field :max_increase_percentage, :decimal
    field :price_after_7d, :decimal
    field :price_after_14d, :decimal

    field :in_top, :boolean, default: false
    field :active, :boolean, default: true
    field :in_top_since, :utc_datetime
    field :exit_date, :utc_datetime
    field :position, :integer
    field :telegram_notified_at, :utc_datetime

    field :coingecko_id, :string

    field :cg_price_change_24h_pct, :decimal, virtual: true
    field :cg_volume_change_24h_pct, :decimal, virtual: true

    belongs_to :symbol_price, CoinTracker.Coins.SymbolPrice

    timestamps(type: :utc_datetime)
  end

  @doc false
  def admin_changeset(signal, attrs, _metadata), do: changeset(signal, attrs)

  @doc false
  def changeset(signal, attrs) do
    signal
    |> cast(attrs, [
      :symbol,
      :name,
      :initial_volume_24h,
      :current_volume_24h,
      :current_price_usd,
      :initial_price_usd,
      :max_price_usd,
      :max_increase_percentage,
      :price_after_7d,
      :price_after_14d,
      :in_top,
      :active,
      :in_top_since,
      :exit_date,
      :position,
      :telegram_notified_at,
      :coingecko_id
    ])
    |> validate_required([:symbol, :in_top_since, :name])
    |> unique_constraint([:symbol, :in_top_since],
      name: :signals_symbol_in_top_since_index
    )
  end

  def volume_increase(%__MODULE__{current_volume_24h: nil} = _signal), do: Decimal.new(0)
  def volume_increase(%__MODULE__{initial_volume_24h: nil} = _signal), do: Decimal.new(0)

  def volume_increase(%__MODULE__{} = signal) do
    Decimal.sub(signal.current_volume_24h, signal.initial_volume_24h)
  end

  def volume_increase_percentage(%__MODULE__{} = signal) do
    initial = signal.initial_volume_24h

    cond do
      is_nil(initial) ->
        Decimal.new(0)

      Decimal.eq?(initial, 0) ->
        Decimal.new(0)

      true ->
        increase = volume_increase(signal)

        Decimal.div(increase, initial)
        |> Decimal.mult(100)
    end
  end
end
