defmodule CoinTracker.VaultTest do
  use CoinTracker.DataCase, async: true

  alias CoinTracker.Vault

  describe "encrypt/decrypt round-trip" do
    test "encrypts and decrypts a string value" do
      plaintext = "my-secret-api-key-12345"

      {:ok, ciphertext} = Vault.encrypt(plaintext)

      assert is_binary(ciphertext)
      assert ciphertext != plaintext

      {:ok, decrypted} = Vault.decrypt(ciphertext)
      assert decrypted == plaintext
    end

    test "produces different ciphertext for same plaintext (AES-GCM uses random IV)" do
      plaintext = "same-value"

      {:ok, ciphertext1} = Vault.encrypt(plaintext)
      {:ok, ciphertext2} = Vault.encrypt(plaintext)

      assert ciphertext1 != ciphertext2
    end

    test "handles nil gracefully via Ecto type" do
      # Vault.decrypt doesn't handle nil directly, but the Ecto type does
      alias CoinTracker.Vault.Encrypted.Binary, as: EncryptedBinary
      assert {:ok, nil} = EncryptedBinary.load(nil)
    end
  end

  describe "Cloak.Ecto.SHA256" do
    test "produces consistent hash for same input" do
      {:ok, hash1} = Cloak.Ecto.SHA256.dump("api-key-abc")
      {:ok, hash2} = Cloak.Ecto.SHA256.dump("api-key-abc")

      assert hash1 == hash2
    end

    test "produces different hash for different input" do
      {:ok, hash1} = Cloak.Ecto.SHA256.dump("key-one")
      {:ok, hash2} = Cloak.Ecto.SHA256.dump("key-two")

      assert hash1 != hash2
    end

    test "hash is binary, not the original value" do
      {:ok, hash} = Cloak.Ecto.SHA256.dump("my-key")

      assert is_binary(hash)
      assert hash != "my-key"
      assert byte_size(hash) == 32
    end
  end

  describe "Vault.Encrypted.Binary Ecto type" do
    alias CoinTracker.Vault.Encrypted.Binary, as: EncryptedBinary

    test "dump encrypts and load decrypts" do
      plaintext = "secret-data"

      {:ok, encrypted} = EncryptedBinary.dump(plaintext)
      assert encrypted != plaintext

      {:ok, decrypted} = EncryptedBinary.load(encrypted)
      assert decrypted == plaintext
    end

    test "cast accepts string values" do
      assert {:ok, "hello"} = EncryptedBinary.cast("hello")
    end
  end
end
