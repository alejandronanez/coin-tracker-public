defmodule CoinTracker.Repo.Migrations.CreateSignalEnrichments do
  use Ecto.Migration

  def change do
    create table(:signal_enrichments) do
      add :signal_id, references(:signals, on_delete: :delete_all), null: false
      add :coingecko_id, :string, null: false

      # Market data
      add :market_cap_usd, :decimal
      add :market_cap_rank, :integer
      add :volume_24h_usd, :decimal
      add :vol_mcap_ratio, :decimal
      add :circulating_supply_pct, :decimal
      add :fdv_mcap_ratio, :decimal
      add :total_supply, :decimal
      add :circulating_supply, :decimal

      # ATH data
      add :ath_usd, :decimal
      add :ath_distance_pct, :decimal
      add :ath_date, :date

      # Exchange and category
      add :exchange_count, :integer
      add :category, :string

      # Price changes
      add :price_change_1h_pct, :decimal
      add :price_change_24h_pct, :decimal
      add :price_change_7d_pct, :decimal

      # Generated briefs (JSON text)
      add :brief_en, :text
      add :brief_es, :text

      # Timestamps for data freshness
      add :enriched_at, :utc_datetime
      add :brief_generated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:signal_enrichments, [:signal_id])
  end
end
