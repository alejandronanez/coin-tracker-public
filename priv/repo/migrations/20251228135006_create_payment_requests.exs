defmodule CoinTracker.Repo.Migrations.CreatePaymentRequests do
  use Ecto.Migration

  def up do
    create table(:payment_requests) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :amount, :decimal, precision: 10, scale: 4, null: false
      add :status, :string, null: false, default: "pending"
      add :approved_by_id, references(:users, on_delete: :nilify_all)
      add :approved_at, :utc_datetime
      add :rejected_reason, :string
      add :tx_hash, :string
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:payment_requests, [:user_id])
    create index(:payment_requests, [:status])

    # Unique constraint on amount for pending payments only
    # This prevents two pending payments from having the same amount
    create unique_index(:payment_requests, [:amount], where: "status = 'pending'")
  end

  def down do
    drop table(:payment_requests)
  end
end
