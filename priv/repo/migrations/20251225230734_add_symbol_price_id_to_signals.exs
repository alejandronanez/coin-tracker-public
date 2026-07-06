defmodule CoinTracker.Repo.Migrations.AddSymbolPriceIdToSignals do
  use Ecto.Migration

  def change do
    alter table(:signals) do
      add :symbol_price_id, references(:symbol_prices, on_delete: :nilify_all)
    end

    create index(:signals, [:symbol_price_id])
  end
end
