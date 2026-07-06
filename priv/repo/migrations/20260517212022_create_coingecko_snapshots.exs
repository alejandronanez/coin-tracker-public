defmodule CoinTracker.Repo.Migrations.CreateCoingeckoSnapshots do
  use Ecto.Migration

  def change do
    create table(:coingecko_snapshots) do
      add :coingecko_id, :string, null: false
      add :symbol, :string, null: false
      add :snapshot_at, :utc_datetime, null: false

      add :total_volume_usd, :decimal
      add :price_usd, :decimal
      add :price_change_percentage_24h, :decimal
      add :market_cap_usd, :decimal

      timestamps(type: :utc_datetime)
    end

    create unique_index(:coingecko_snapshots, [:coingecko_id, :snapshot_at])
    create index(:coingecko_snapshots, [:coingecko_id, "snapshot_at DESC"])
    create index(:coingecko_snapshots, [:snapshot_at])
  end
end
