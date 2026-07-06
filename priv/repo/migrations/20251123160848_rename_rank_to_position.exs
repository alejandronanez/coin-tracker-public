defmodule CoinTracker.Repo.Migrations.RenameRankToPosition do
  use Ecto.Migration

  def change do
    rename table(:signals), :rank, to: :position
    rename table(:signal_snapshots), :rank, to: :position

    # Drop the old index on rank and create a new one on position
    drop index(:signals, [:rank])
    create index(:signals, [:position])
  end
end
