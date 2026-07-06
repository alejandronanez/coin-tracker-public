defmodule CoinTracker.Repo.Migrations.AddLlmUsageToSignalEnrichments do
  use Ecto.Migration

  def change do
    alter table(:signal_enrichments) do
      add :llm_input_tokens, :integer
      add :llm_output_tokens, :integer
      add :llm_cached_tokens, :integer
      add :llm_cache_creation_tokens, :integer
      add :llm_cost_usd, :decimal
      add :llm_model, :string
    end
  end
end
