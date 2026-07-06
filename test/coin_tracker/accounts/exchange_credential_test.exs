defmodule CoinTracker.Accounts.ExchangeCredentialTest do
  use CoinTracker.DataCase, async: true

  alias CoinTracker.Accounts
  alias CoinTracker.Accounts.ExchangeCredential

  import CoinTracker.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "create_exchange_credential/2" do
    test "creates a credential with encrypted fields", %{user: user} do
      attrs = %{
        "exchange" => "binance_spot",
        "api_key" => "my_api_key_12345678",
        "api_secret" => "my_api_secret_87654321",
        "label" => "My trading key"
      }

      assert {:ok, credential} = Accounts.create_exchange_credential(user.id, attrs)
      assert credential.exchange == "binance_spot"
      assert credential.label == "My trading key"
      assert credential.api_key == "my_api_key_12345678"
      assert credential.api_secret == "my_api_secret_87654321"
      assert credential.user_id == user.id
      assert credential.api_key_hash != nil
    end

    test "encrypted data is not plaintext in the database", %{user: user} do
      attrs = %{
        "exchange" => "binance_spot",
        "api_key" => "plaintext_key_visible",
        "api_secret" => "plaintext_secret_visible"
      }

      {:ok, credential} = Accounts.create_exchange_credential(user.id, attrs)

      # Read raw binary from DB to verify encryption
      raw =
        CoinTracker.Repo.one(
          from(ec in "exchange_credentials",
            where: ec.id == ^credential.id,
            select: {ec.api_key_encrypted, ec.api_secret_encrypted}
          )
        )

      {raw_key, raw_secret} = raw
      refute raw_key == "plaintext_key_visible"
      refute raw_secret == "plaintext_secret_visible"
      assert is_binary(raw_key)
      assert is_binary(raw_secret)
    end

    test "enforces uniqueness per user+exchange", %{user: user} do
      attrs = %{
        "exchange" => "binance_spot",
        "api_key" => "key_one_12345678",
        "api_secret" => "secret_one_12345678"
      }

      assert {:ok, _} = Accounts.create_exchange_credential(user.id, attrs)

      assert {:error, changeset} =
               Accounts.create_exchange_credential(user.id, %{
                 "exchange" => "binance_spot",
                 "api_key" => "key_two_12345678",
                 "api_secret" => "secret_two_12345678"
               })

      assert {"you already have credentials for this exchange", _} =
               changeset.errors[:exchange]
    end

    test "allows same exchange for different users" do
      user1 = user_fixture()
      user2 = user_fixture()

      attrs = %{
        "exchange" => "binance_spot",
        "api_key" => "key_user1_12345678",
        "api_secret" => "secret_user1_12345678"
      }

      assert {:ok, _} = Accounts.create_exchange_credential(user1.id, attrs)

      assert {:ok, _} =
               Accounts.create_exchange_credential(user2.id, %{
                 "exchange" => "binance_spot",
                 "api_key" => "key_user2_12345678",
                 "api_secret" => "secret_user2_12345678"
               })
    end

    test "validates required fields", %{user: user} do
      assert {:error, changeset} = Accounts.create_exchange_credential(user.id, %{})
      assert %{exchange: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates exchange is supported", %{user: user} do
      attrs = %{
        "exchange" => "kraken",
        "api_key" => "some_key_12345678",
        "api_secret" => "some_secret_12345678"
      }

      assert {:error, changeset} = Accounts.create_exchange_credential(user.id, attrs)
      assert %{exchange: ["is invalid"]} = errors_on(changeset)
    end

    test "validates key minimum length", %{user: user} do
      attrs = %{"exchange" => "binance_spot", "api_key" => "short", "api_secret" => "short"}
      assert {:error, changeset} = Accounts.create_exchange_credential(user.id, attrs)
      assert %{api_key: [msg]} = errors_on(changeset)
      assert msg =~ "at least"
    end
  end

  describe "list_exchange_credentials/1" do
    test "returns all credentials for a user", %{user: user} do
      exchange_credential_fixture(user, %{"exchange" => "binance_spot"})
      exchange_credential_fixture(user, %{"exchange" => "bitget_spot"})

      credentials = Accounts.list_exchange_credentials(user.id)
      assert length(credentials) == 2
      exchanges = Enum.map(credentials, & &1.exchange)
      assert "binance_spot" in exchanges
      assert "bitget_spot" in exchanges
    end

    test "does not return other users' credentials", %{user: user} do
      other_user = user_fixture()
      exchange_credential_fixture(user, %{"exchange" => "binance_spot"})
      exchange_credential_fixture(other_user, %{"exchange" => "binance_spot"})

      credentials = Accounts.list_exchange_credentials(user.id)
      assert length(credentials) == 1
    end

    test "returns empty list when no credentials", %{user: user} do
      assert Accounts.list_exchange_credentials(user.id) == []
    end
  end

  describe "get_exchange_credential/2" do
    test "returns credential by user and exchange atom", %{user: user} do
      exchange_credential_fixture(user, %{"exchange" => "binance_spot"})

      credential = Accounts.get_exchange_credential(user.id, :binance_spot)
      assert %ExchangeCredential{} = credential
      assert credential.exchange == "binance_spot"
    end

    test "returns credential by user and exchange string", %{user: user} do
      exchange_credential_fixture(user, %{"exchange" => "binance_spot"})

      credential = Accounts.get_exchange_credential(user.id, "binance_spot")
      assert %ExchangeCredential{} = credential
    end

    test "returns nil when not found", %{user: user} do
      assert Accounts.get_exchange_credential(user.id, :binance_spot) == nil
    end
  end

  describe "delete_exchange_credential/1" do
    test "deletes a credential", %{user: user} do
      credential = exchange_credential_fixture(user)

      assert {:ok, _} = Accounts.delete_exchange_credential(credential)
      assert Accounts.get_exchange_credential(user.id, :binance_spot) == nil
    end
  end

  describe "update_credential_last_used/1" do
    test "updates last_used_at timestamp", %{user: user} do
      credential = exchange_credential_fixture(user)
      assert credential.last_used_at == nil

      {:ok, updated} = Accounts.update_credential_last_used(credential)
      assert %DateTime{} = updated.last_used_at
    end
  end

  describe "has_exchange_credential?/2" do
    test "returns true when credential exists", %{user: user} do
      exchange_credential_fixture(user, %{"exchange" => "binance_spot"})
      assert Accounts.has_exchange_credential?(user.id, :binance_spot)
    end

    test "returns false when credential doesn't exist", %{user: user} do
      refute Accounts.has_exchange_credential?(user.id, :binance_spot)
    end
  end

  describe "ExchangeCredential.api_key_prefix/1" do
    test "returns first 8 chars with ellipsis", %{user: user} do
      credential = exchange_credential_fixture(user, %{"api_key" => "abcdefghijklmnop"})
      assert ExchangeCredential.api_key_prefix(credential) == "abcdefgh..."
    end
  end
end
