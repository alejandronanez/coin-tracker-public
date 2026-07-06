defmodule CoinTracker.Repo.Migrations.AddCoingeckoIdToSignals do
  use Ecto.Migration

  def change do
    alter table(:signals) do
      add :coingecko_id, :string
    end

    create index(:signals, [:coingecko_id])
  end
end
