defmodule CoinTracker.Repo.Migrations.CreateSignals do
  use Ecto.Migration

  def change do
    create table(:signals) do
      add :symbol, :string, null: false
      add :name, :string, null: false
      add :symbol_name, :string

      add :initial_volume_24h, :decimal
      add :current_volume_24h, :decimal

      add :current_price_usd, :decimal
      add :initial_price_usd, :decimal
      add :max_price_usd, :decimal
      add :max_increase_percentage, :decimal

      add :in_top, :boolean, default: false, null: false
      add :active, :boolean, default: true, null: false
      add :in_top_since, :utc_datetime, null: false
      add :exit_date, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Composite unique index - prevents duplicate symbol + in_top_since combinations
    create unique_index(:signals, [:symbol, :in_top_since],
             name: :signals_symbol_in_top_since_index
           )

    # Performance index for querying active signals by symbol
    create index(:signals, [:symbol], where: "active = true")
  end
end
