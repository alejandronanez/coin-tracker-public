defmodule CoinTracker.Repo.Migrations.AddLastKnownPnlToPositions do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add :last_known_pnl, :decimal, precision: 10, scale: 2
    end
  end
end
