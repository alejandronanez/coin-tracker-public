defmodule CoinTracker.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Changeset
  import Ecto.Query, warn: false
  alias CoinTracker.Repo

  alias CoinTracker.Accounts.{
    ExchangeCredential,
    User,
    UserToken,
    UserNotifier,
    TelegramUser,
    UserSettings
  }

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `CoinTracker.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `CoinTracker.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Subscription management

  @doc """
  Activates a pro subscription for the given user with an expiry date.

  ## Examples

      iex> expires_at = DateTime.add(DateTime.utc_now(), 30, :day)
      iex> activate_pro_subscription(user, expires_at)
      {:ok, %User{subscription_tier: :pro}}

  """
  def activate_pro_subscription(%User{} = user, expires_at)
      when is_struct(expires_at, DateTime) do
    user
    |> User.subscription_changeset(%{
      subscription_tier: :pro,
      subscription_expires_at: expires_at
    })
    |> Repo.update()
  end

  @doc """
  Activates an admin subscription for the given user (never expires).

  ## Examples

      iex> activate_admin_subscription(user)
      {:ok, %User{subscription_tier: :admin}}

  """
  def activate_admin_subscription(%User{} = user) do
    user
    |> User.subscription_changeset(%{
      subscription_tier: :admin,
      subscription_expires_at: nil
    })
    |> Repo.update()
  end

  @doc """
  Downgrades a user to free tier and removes telegram connection.

  This deletes the TelegramUser record and clears the telegram_token.

  ## Examples

      iex> downgrade_to_free(user)
      {:ok, %User{subscription_tier: :free}}

  """
  def downgrade_to_free(%User{} = user) do
    Repo.transaction(fn ->
      # Delete telegram user if exists
      case get_telegram_user(user.id) do
        %TelegramUser{} = telegram_user -> Repo.delete(telegram_user)
        nil -> :ok
      end

      # Update user to free tier
      result =
        user
        |> User.subscription_changeset(%{
          subscription_tier: :free,
          subscription_expires_at: nil
        })
        |> put_change(:telegram_token, nil)
        |> Repo.update()

      case result do
        {:ok, user} -> {:ok, user}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  @doc """
  Checks if a user's subscription has expired and downgrades them if so.

  Returns {:ok, user} if no action was needed or downgrade succeeded.
  Returns {:error, changeset} if downgrade failed.

  ## Examples

      iex> check_and_expire_subscription(user)
      {:ok, %User{}}

  """
  def check_and_expire_subscription(%User{subscription_tier: :pro} = user) do
    if User.active_subscription?(user) do
      {:ok, user}
    else
      downgrade_to_free(user)
    end
  end

  def check_and_expire_subscription(%User{} = user) do
    # Admin and free users don't need expiry checks
    {:ok, user}
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  ## Telegram integration

  @doc """
  Generates a one-time Telegram registration token for a user.

  The token is a 32-character random string. Returns the updated user with the token.

  ## Examples

      iex> generate_telegram_token(user)
      %User{telegram_token: "abc123..."}

  """
  def generate_telegram_token(%User{} = user) do
    token = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)

    user
    |> cast(%{telegram_token: token}, [:telegram_token])
    |> Repo.update()
  end

  @doc """
  Gets a user by their Telegram registration token.

  The token must not be nil (not already used).

  ## Examples

      iex> get_user_by_telegram_token("abc123...")
      %User{telegram_token: "abc123..."}

      iex> get_user_by_telegram_token("invalid")
      nil

  """
  def get_user_by_telegram_token(token) when is_binary(token) do
    Repo.get_by(User, telegram_token: token)
  end

  @doc """
  Invalidates a user's Telegram registration token.

  Sets the telegram_token field to nil so it can't be reused.

  ## Examples

      iex> invalidate_telegram_token(user)
      {:ok, %User{telegram_token: nil}}

  """
  def invalidate_telegram_token(%User{} = user) do
    user
    |> cast(%{telegram_token: nil}, [:telegram_token])
    |> Repo.update()
  end

  @doc """
  Gets the Telegram user record for a given user_id.

  Returns the TelegramUser struct if it exists, nil otherwise.

  ## Examples

      iex> get_telegram_user(123)
      %TelegramUser{chat_id: 987654, user_id: 123}

      iex> get_telegram_user(999)
      nil

  """
  def get_telegram_user(user_id) when is_integer(user_id) do
    Repo.get_by(TelegramUser, user_id: user_id)
  end

  @doc """
  Gets the Telegram chat_id for a given user_id.

  Returns the chat_id as an integer if found, nil otherwise.

  ## Examples

      iex> get_telegram_chat_id(123)
      987654

      iex> get_telegram_chat_id(999)
      nil

  """
  def get_telegram_chat_id(user_id) when is_integer(user_id) do
    case get_telegram_user(user_id) do
      %TelegramUser{chat_id: chat_id} -> chat_id
      nil -> nil
    end
  end

  @doc """
  Creates a TelegramUser record linking a chat_id to a user.

  Returns {:ok, telegram_user} or {:error, changeset}.

  ## Examples

      iex> create_telegram_user(%{chat_id: 987654, user_id: 123})
      {:ok, %TelegramUser{}}

      iex> create_telegram_user(%{chat_id: nil})
      {:error, %Ecto.Changeset{}}

  """
  def create_telegram_user(attrs) do
    %TelegramUser{}
    |> TelegramUser.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a user by their Telegram chat_id.

  Returns the User struct if found, nil otherwise.

  ## Examples

      iex> get_user_by_telegram_chat_id(987654)
      %User{id: 123}

      iex> get_user_by_telegram_chat_id(999999)
      nil

  """
  def get_user_by_telegram_chat_id(chat_id) when is_integer(chat_id) do
    case Repo.get_by(TelegramUser, chat_id: chat_id) do
      %TelegramUser{user_id: user_id} -> get_user!(user_id)
      nil -> nil
    end
  end

  @doc """
  Lists all users with an active pro/admin subscription who have Telegram linked.

  Returns a list of User structs. This is used for broadcasting market alerts
  to all eligible users.

  ## Examples

      iex> list_pro_users_with_telegram()
      [%User{subscription_tier: :pro, ...}, %User{subscription_tier: :admin, ...}]

  """
  def list_pro_users_with_telegram do
    now = DateTime.utc_now()

    from(u in User,
      join: tu in TelegramUser,
      on: tu.user_id == u.id,
      where:
        u.subscription_tier == :admin or
          (u.subscription_tier == :pro and
             (is_nil(u.subscription_expires_at) or u.subscription_expires_at > ^now)),
      select: u
    )
    |> Repo.all()
  end

  ## User Settings

  @doc """
  Gets the user settings for a given user_id.

  Returns the UserSettings struct if it exists, nil otherwise.

  ## Examples

      iex> get_user_settings(123)
      %UserSettings{locale: "en", user_id: 123}

      iex> get_user_settings(999)
      nil

  """
  def get_user_settings(user_id) when is_integer(user_id) do
    Repo.get_by(UserSettings, user_id: user_id)
  end

  @doc """
  Gets the user settings for a given user_id, creating default settings if none exist.

  Returns {:ok, user_settings} or {:error, changeset}.

  ## Examples

      iex> get_or_create_user_settings(123)
      {:ok, %UserSettings{locale: "en", user_id: 123}}

  """
  def get_or_create_user_settings(user_id) when is_integer(user_id) do
    case get_user_settings(user_id) do
      nil ->
        %UserSettings{}
        |> UserSettings.changeset(%{locale: "en"})
        |> Ecto.Changeset.put_change(:user_id, user_id)
        |> Repo.insert()

      settings ->
        {:ok, settings}
    end
  end

  @doc """
  Updates the user settings.

  ## Examples

      iex> update_user_settings(user_settings, %{locale: "es"})
      {:ok, %UserSettings{locale: "es"}}

      iex> update_user_settings(user_settings, %{locale: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_settings(%UserSettings{} = settings, attrs) do
    settings
    |> UserSettings.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets the locale preference for a given user_id.

  Returns the locale string if found, "en" otherwise.

  ## Examples

      iex> get_user_locale(123)
      "es"

      iex> get_user_locale(999)
      "en"

  """
  def get_user_locale(user_id) when is_integer(user_id) do
    case get_user_settings(user_id) do
      %UserSettings{locale: locale} -> locale
      nil -> "en"
    end
  end

  ## Exchange Credentials

  def create_exchange_credential(user_id, attrs) do
    %ExchangeCredential{user_id: user_id}
    |> ExchangeCredential.changeset(attrs)
    |> Repo.insert()
  end

  def list_exchange_credentials(user_id) do
    from(ec in ExchangeCredential, where: ec.user_id == ^user_id, order_by: [asc: ec.exchange])
    |> Repo.all()
  end

  def get_exchange_credential(user_id, exchange) when is_atom(exchange) do
    get_exchange_credential(user_id, Atom.to_string(exchange))
  end

  def get_exchange_credential(user_id, exchange) when is_binary(exchange) do
    Repo.get_by(ExchangeCredential, user_id: user_id, exchange: exchange)
  end

  def delete_exchange_credential(%ExchangeCredential{} = credential) do
    Repo.delete(credential)
  end

  def update_credential_last_used(%ExchangeCredential{} = credential) do
    credential
    |> Ecto.Changeset.change(last_used_at: DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update()
  end

  def has_exchange_credential?(user_id, exchange) when is_atom(exchange) do
    has_exchange_credential?(user_id, Atom.to_string(exchange))
  end

  def has_exchange_credential?(user_id, exchange) when is_binary(exchange) do
    from(ec in ExchangeCredential,
      where: ec.user_id == ^user_id and ec.exchange == ^exchange
    )
    |> Repo.exists?()
  end
end
