defmodule CoinTracker.Repo.Migrations.AddTelegramTokenToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :telegram_token, :string
    end
  end
end
