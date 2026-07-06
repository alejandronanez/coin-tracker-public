defmodule CoinTracker.Repo.Migrations.AddApiTokenToUserSettings do
  use Ecto.Migration

  def change do
    alter table(:user_settings) do
      add :api_token_hash, :string
      add :api_token_prefix, :string
      add :api_token_created_at, :utc_datetime
    end

    create index(:user_settings, [:api_token_hash])
  end
end
