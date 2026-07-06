defmodule CoinTracker.Repo.Migrations.AddAlertTrackingToPositions do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add :last_alerted_threshold_positive, :decimal, precision: 5, scale: 2
      add :last_alerted_negative_proximity, :integer
      add :last_alerted_at, :utc_datetime
    end
  end
end
