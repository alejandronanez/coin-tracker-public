defmodule CoinTracker.Repo.Migrations.CreateSymbolPrices do
  use Ecto.Migration

  def change do
    create table(:symbol_prices) do
      add :exchange, :string, size: 50, null: false
      add :symbol_pair, :string, size: 20, null: false
      add :current_price, :decimal, precision: 20, scale: 8, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:symbol_prices, [:exchange, :symbol_pair])
  end
end
