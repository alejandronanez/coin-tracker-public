defmodule CoinTracker.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true
    field :telegram_token, :string
    field :subscription_tier, Ecto.Enum, values: [:free, :pro, :admin], default: :free
    field :subscription_expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns true if the user has an active subscription (pro or admin).

  - Admin tier never expires
  - Pro tier is active if expires_at is nil or in the future
  - Free tier is never considered active
  """
  def active_subscription?(%__MODULE__{subscription_tier: :admin}), do: true

  def active_subscription?(%__MODULE__{
        subscription_tier: :pro,
        subscription_expires_at: expires_at
      }) do
    is_nil(expires_at) or DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  def active_subscription?(_user), do: false

  @doc """
  Returns true if the user has admin role.
  """
  def admin?(%__MODULE__{subscription_tier: :admin}), do: true
  def admin?(_user), do: false

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, CoinTracker.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  A user changeset for updating subscription information.

  Admin tier subscriptions never expire (expires_at is set to nil).
  Pro tier subscriptions require an expiry date.
  """
  def subscription_changeset(user, attrs) do
    user
    |> cast(attrs, [:subscription_tier, :subscription_expires_at])
    |> validate_required([:subscription_tier])
    |> validate_subscription_expiry()
  end

  defp validate_subscription_expiry(changeset) do
    tier = get_field(changeset, :subscription_tier)

    case tier do
      :admin ->
        # Admin never expires
        put_change(changeset, :subscription_expires_at, nil)

      :free ->
        # Free tier can have nil expiry
        changeset

      :pro ->
        # Pro tier should have an expiry date
        validate_required(changeset, [:subscription_expires_at])

      _ ->
        changeset
    end
  end

  @doc """
  A user changeset for admin updates via Backpex.

  Allows updating email, subscription tier, and subscription expiry.
  This changeset is used by the Backpex admin interface and requires
  arity 3 to match Backpex's changeset function signature.
  """
  def admin_changeset(user, attrs, _metadata \\ []) do
    user
    |> cast(attrs, [:email, :subscription_tier, :subscription_expires_at])
    |> validate_required([:subscription_tier])
    |> validate_admin_email()
    |> validate_subscription_expiry()
  end

  defp validate_admin_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%CoinTracker.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
