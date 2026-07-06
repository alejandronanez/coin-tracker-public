defmodule CoinTracker.Repo.Migrations.CreateSignalSnapshots do
  use Ecto.Migration

  def change do
    create table(:signal_snapshots) do
      add :signal_id, references(:signals, on_delete: :delete_all), null: false
      add :snapshot_at, :utc_datetime, null: false
      add :symbol, :string, null: false

      add :current_volume_24h, :decimal
      add :initial_volume_24h, :decimal
      add :max_price_usd, :decimal
      add :current_price_usd, :decimal

      add :in_top, :boolean, null: false
      add :rank, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:signal_snapshots, [:signal_id])
    create index(:signal_snapshots, [:snapshot_at])
    create index(:signal_snapshots, [:signal_id, :snapshot_at])
  end
end
