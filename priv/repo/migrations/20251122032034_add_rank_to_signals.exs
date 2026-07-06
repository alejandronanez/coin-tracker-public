defmodule CoinTracker.Repo.Migrations.AddRankToSignals do
  use Ecto.Migration

  def change do
    alter table(:signals) do
      add :rank, :integer
    end

    create index(:signals, [:rank])
  end
end
