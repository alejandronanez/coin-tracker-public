defmodule CoinTracker.Repo.Migrations.AddAmountInvestedToPositions do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add :amount_invested, :decimal, precision: 20, scale: 8
    end
  end
end
