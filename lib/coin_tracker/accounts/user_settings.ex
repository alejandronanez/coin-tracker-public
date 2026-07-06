defmodule CoinTracker.Accounts.UserSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @supported_locales ~w(en es)

  schema "user_settings" do
    field :locale, :string, default: "en"
    belongs_to :user, CoinTracker.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of supported locales.
  """
  def supported_locales, do: @supported_locales

  @doc """
  A changeset for updating user settings.
  """
  def changeset(user_settings, attrs) do
    user_settings
    |> cast(attrs, [:locale])
    |> validate_required([:locale])
    |> validate_inclusion(:locale, @supported_locales)
  end
end
