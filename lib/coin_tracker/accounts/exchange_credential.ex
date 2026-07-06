defmodule CoinTracker.Accounts.ExchangeCredential do
  use Ecto.Schema
  import Ecto.Changeset

  @supported_exchanges ~w(binance_spot bitget_spot mexc_spot)

  schema "exchange_credentials" do
    field :exchange, :string
    field :label, :string
    field :api_key, CoinTracker.Vault.Encrypted.Binary, source: :api_key_encrypted
    field :api_secret, CoinTracker.Vault.Encrypted.Binary, source: :api_secret_encrypted
    field :api_key_hash, Cloak.Ecto.SHA256
    field :last_used_at, :utc_datetime

    belongs_to :user, CoinTracker.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:exchange, :label, :api_key, :api_secret])
    |> validate_required([:exchange, :api_key, :api_secret])
    |> validate_inclusion(:exchange, @supported_exchanges)
    |> validate_length(:api_key, min: 8)
    |> validate_length(:api_secret, min: 8)
    |> validate_length(:label, max: 100)
    |> put_api_key_hash()
    |> unique_constraint(:exchange,
      name: :exchange_credentials_user_id_exchange_index,
      message: "you already have credentials for this exchange"
    )
  end

  defp put_api_key_hash(changeset) do
    case get_change(changeset, :api_key) do
      nil -> changeset
      api_key -> force_change(changeset, :api_key_hash, api_key)
    end
  end

  def api_key_prefix(%__MODULE__{api_key: nil}), do: nil

  def api_key_prefix(%__MODULE__{api_key: api_key}) when is_binary(api_key) do
    String.slice(api_key, 0, 8) <> "..."
  end
end
