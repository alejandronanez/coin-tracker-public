defmodule CoinTracker.Repo.Migrations.AddBlockchainFieldsToPaymentRequests do
  use Ecto.Migration

  def up do
    alter table(:payment_requests) do
      add :sender_address, :string
      add :notified_at, :utc_datetime
    end
  end

  def down do
    alter table(:payment_requests) do
      remove :sender_address
      remove :notified_at
    end
  end
end
