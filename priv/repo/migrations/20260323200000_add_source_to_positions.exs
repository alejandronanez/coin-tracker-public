defmodule CoinTracker.Repo.Migrations.AddSourceToPositions do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add :source, :string, default: "manual", null: false
    end
  end
end
