defmodule CoinTracker.Repo.Migrations.AddEntryRankToPositions do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add :entry_rank, :integer
    end
  end
end
