defmodule CoinTracker.Repo.Migrations.AddPriceAfterFieldsToSignals do
  use Ecto.Migration

  def change do
    alter table(:signals) do
      add :price_after_7d, :decimal
      add :price_after_14d, :decimal
    end
  end
end
