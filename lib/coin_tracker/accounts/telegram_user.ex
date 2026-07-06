defmodule CoinTracker.Accounts.TelegramUser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "telegram_users" do
    field :chat_id, :integer
    belongs_to :user, CoinTracker.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(telegram_user, attrs) do
    telegram_user
    |> cast(attrs, [:chat_id, :user_id])
    |> validate_required([:chat_id, :user_id])
    |> unique_constraint(:chat_id)
    |> unique_constraint(:user_id)
  end
end
