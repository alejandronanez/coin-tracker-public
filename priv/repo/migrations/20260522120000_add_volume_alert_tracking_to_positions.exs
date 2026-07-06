defmodule CoinTracker.Repo.Migrations.AddVolumeAlertTrackingToPositions do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add :last_alerted_volume_window_tier, :decimal, precision: 5, scale: 2
      add :last_alerted_volume_cumulative_tier, :decimal, precision: 5, scale: 2
    end
  end
end
