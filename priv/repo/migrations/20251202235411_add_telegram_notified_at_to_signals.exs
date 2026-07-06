defmodule CoinTracker.Repo.Migrations.AddTelegramNotifiedAtToSignals do
  use Ecto.Migration

  def change do
    alter table(:signals) do
      add :telegram_notified_at, :utc_datetime
    end

    # Backfill: mark all existing signals as already notified
    # so they don't trigger notifications on deploy
    execute "UPDATE signals SET telegram_notified_at = NOW()", ""
  end
end
