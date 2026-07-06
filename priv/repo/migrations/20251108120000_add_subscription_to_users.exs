defmodule CoinTracker.Repo.Migrations.AddSubscriptionToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :subscription_tier, :string, default: "free", null: false
      add :subscription_expires_at, :utc_datetime
    end

    create index(:users, [:subscription_tier])
  end
end
