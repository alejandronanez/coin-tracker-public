defmodule CoinTracker.Repo.Migrations.AddExitPriceToPositions do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add :exit_price, :decimal
    end
  end
end
