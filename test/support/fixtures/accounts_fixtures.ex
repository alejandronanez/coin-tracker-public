defmodule CoinTracker.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `CoinTracker.Accounts` context.
  """

  import Ecto.Query

  alias CoinTracker.Accounts
  alias CoinTracker.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    CoinTracker.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    CoinTracker.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    CoinTracker.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end

  @doc """
  Creates a user with a pro subscription.

  ## Options

    * `:expires_at` - When the subscription expires (default: 30 days from now)

  """
  def pro_user_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    expires_at = Map.get(attrs, :expires_at, DateTime.add(DateTime.utc_now(), 30, :day))
    {:ok, user} = Accounts.activate_pro_subscription(user, expires_at)
    user
  end

  @doc """
  Creates a user with an admin subscription.
  """
  def admin_user_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, user} = Accounts.activate_admin_subscription(user)
    user
  end

  @doc """
  Links a Telegram chat to a user.

  Returns the updated user (for chaining) and creates the TelegramUser record.
  """
  def link_telegram(user, chat_id \\ System.unique_integer([:positive])) do
    {:ok, _telegram_user} = Accounts.create_telegram_user(%{user_id: user.id, chat_id: chat_id})
    user
  end

  @doc """
  Creates a pro user with Telegram linked.
  """
  def pro_user_with_telegram_fixture(attrs \\ %{}) do
    user = pro_user_fixture(attrs)
    link_telegram(user)
  end

  @doc """
  Creates an admin user with Telegram linked.
  """
  def admin_user_with_telegram_fixture(attrs \\ %{}) do
    user = admin_user_fixture(attrs)
    link_telegram(user)
  end

  def exchange_credential_fixture(user, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "exchange" => "binance_spot",
        "api_key" => "test_api_key_#{System.unique_integer([:positive])}",
        "api_secret" => "test_api_secret_#{System.unique_integer([:positive])}"
      })

    {:ok, credential} = Accounts.create_exchange_credential(user.id, attrs)
    credential
  end
end
