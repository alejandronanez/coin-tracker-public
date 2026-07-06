defmodule CoinTracker.Repo.Migrations.CreatePositions do
  use Ecto.Migration

  def change do
    create table(:positions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :symbol_price_id, references(:symbol_prices, on_delete: :restrict), null: false

      add :entry_price, :decimal, precision: 20, scale: 8, null: false
      add :stop_loss_percent, :decimal, precision: 5, scale: 2, null: false
      add :take_profit_percent, :decimal, precision: 5, scale: 2, null: false
      add :current_threshold_zone, :integer
      add :status, :string, null: false, default: "active"
      add :closed_reason, :string
      add :closed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # 🔍 Query optimization indexes
    create index(:positions, [:user_id])
    create index(:positions, [:status])
    create index(:positions, [:user_id, :status])

    # 🚀 Fast joins to symbol_prices (auto-created by the FK, but explicit is nice)
    create index(:positions, [:symbol_price_id])
  end
end
