defmodule CoinTracker.Repo.Migrations.CreateExchangeCredentials do
  use Ecto.Migration

  def change do
    create table(:exchange_credentials) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :exchange, :string, null: false
      add :label, :string
      add :api_key_encrypted, :binary, null: false
      add :api_secret_encrypted, :binary, null: false
      add :api_key_hash, :binary, null: false
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:exchange_credentials, [:user_id, :exchange])
    create index(:exchange_credentials, [:user_id])
    create index(:exchange_credentials, [:api_key_hash])
  end
end
