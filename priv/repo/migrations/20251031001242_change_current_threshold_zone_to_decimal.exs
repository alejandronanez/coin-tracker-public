defmodule CoinTracker.Repo.Migrations.ChangeCurrentThresholdZoneToDecimal do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      modify :current_threshold_zone, :decimal, precision: 5, scale: 2
    end
  end
end
