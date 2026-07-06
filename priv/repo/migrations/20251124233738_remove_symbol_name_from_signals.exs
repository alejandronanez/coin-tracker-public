defmodule CoinTracker.Repo.Migrations.RemoveSymbolNameFromSignals do
  use Ecto.Migration

  def change do
    alter table(:signals) do
      remove :symbol_name, :string
    end
  end
end
