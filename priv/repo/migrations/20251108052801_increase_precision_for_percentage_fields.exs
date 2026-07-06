defmodule CoinTracker.Repo.Migrations.IncreasePrecisionForPercentageFields do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      modify :stop_loss_percent, :decimal,
        precision: 10,
        scale: 2,
        from: {:decimal, precision: 5, scale: 2}

      modify :take_profit_percent, :decimal,
        precision: 10,
        scale: 2,
        from: {:decimal, precision: 5, scale: 2}

      modify :current_threshold_zone, :decimal,
        precision: 10,
        scale: 2,
        from: {:decimal, precision: 5, scale: 2}

      modify :last_alerted_threshold_positive, :decimal,
        precision: 10,
        scale: 2,
        from: {:decimal, precision: 5, scale: 2}
    end
  end
end
