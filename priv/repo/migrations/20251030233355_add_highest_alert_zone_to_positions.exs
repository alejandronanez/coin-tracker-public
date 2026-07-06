defmodule CoinTracker.Repo.Migrations.AddHighestAlertZoneToPositions do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add :highest_alert_zone_reached, :decimal, precision: 5, scale: 2
    end
  end
end
