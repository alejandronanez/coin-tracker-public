defmodule CoinTracker.Repo.Migrations.CreateCoinGeckoMappings do
  use Ecto.Migration

  def change do
    create table(:coin_gecko_mappings) do
      add :symbol, :string, null: false
      add :coingecko_id, :string, null: false
      add :name, :string, null: false
      add :market_cap_rank, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:coin_gecko_mappings, [:symbol])
  end
end
