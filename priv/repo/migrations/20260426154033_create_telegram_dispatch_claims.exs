defmodule CoinTracker.Repo.Migrations.CreateTelegramDispatchClaims do
  use Ecto.Migration

  def change do
    create table(:telegram_dispatch_claims) do
      add :user_id, :bigint, null: false
      add :fingerprint, :string, size: 12, null: false
      add :window_bucket, :bigint, null: false
      add :dispatch_id, :string, size: 8, null: false
      add :notification_kind, :string, size: 64, null: false, default: "unknown"

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:telegram_dispatch_claims, [:user_id, :fingerprint, :window_bucket])
    create index(:telegram_dispatch_claims, [:inserted_at])
  end
end
