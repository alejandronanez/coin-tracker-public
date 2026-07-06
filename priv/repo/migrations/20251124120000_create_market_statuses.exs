defmodule CoinTracker.Repo.Migrations.CreateMarketStatuses do
  use Ecto.Migration

  def change do
    create table(:market_statuses) do
      add :active_signals_count, :integer, null: false
      add :recorded_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    # Index for time-based queries (most common query pattern)
    create index(:market_statuses, [:recorded_at])

    # Composite index for efficient time-range queries
    create index(:market_statuses, [:recorded_at, :active_signals_count])
  end
end
