defmodule CoinTracker.Repo.Migrations.DropApiTokenFromUserSettings do
  use Ecto.Migration

  def change do
    drop index(:user_settings, [:api_token_hash])

    alter table(:user_settings) do
      remove :api_token_hash
      remove :api_token_prefix
      remove :api_token_created_at
    end
  end
end
