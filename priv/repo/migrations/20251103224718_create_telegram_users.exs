defmodule CoinTracker.Repo.Migrations.CreateTelegramUsers do
  use Ecto.Migration

  def change do
    create table(:telegram_users) do
      add :chat_id, :bigint, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:telegram_users, [:chat_id])
    create unique_index(:telegram_users, [:user_id])
  end
end
