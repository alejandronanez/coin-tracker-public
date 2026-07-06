defmodule CoinTracker.Repo.Migrations.AddTxHashUniqueConstraint do
  use Ecto.Migration

  def up do
    create unique_index(:payment_requests, [:tx_hash], where: "tx_hash IS NOT NULL")
  end

  def down do
    drop index(:payment_requests, [:tx_hash])
  end
end
