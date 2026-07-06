defmodule CoinTracker.TelegramClient.DispatchClaim do
  @moduledoc """
  Cluster-wide claim record used to suppress duplicate Telegram dispatches.

  The app runs multiple clustered BEAM nodes (DNSCluster + Fly auto_start_machines).
  Each node independently runs every poller and PubSub subscriber, so the same
  alert can be generated and sent N times — once per node — for a single logical
  event. The in-memory `DuplicateDetector` cannot prevent this because its ETS
  table is node-local.

  This schema backs an "insert-then-send" claim protocol:

    1. `claim/4` attempts to `INSERT ... ON CONFLICT DO NOTHING` on
       `(user_id, fingerprint, window_bucket)`.
    2. If the row is fresh (`returning :id` is non-nil), the caller has won the
       claim and is the only node that will send this notification within the
       current window.
    3. If the row already exists, the caller gets `:duplicate` and skips the
       send.

  Postgres is the only piece of infrastructure visible to all nodes, so a single
  unique-index INSERT is sufficient — no leader election, no extra deps.
  Failures (e.g. Postgres unreachable) return `{:error, reason}` so the caller
  can fail open: better to send a duplicate than silence a real alert.

  ## Window buckets

  `window_bucket = div(unix_seconds, window_seconds)`. Discrete bucketing keeps
  the unique index cheap and atomic at the cost of boundary aliasing — two
  identical sends straddling a bucket boundary both succeed. Acceptable: the
  duplicates we observe arrive within ~1 second.
  """
  use Ecto.Schema
  import Ecto.Query

  alias CoinTracker.Repo

  @default_window_seconds 300

  schema "telegram_dispatch_claims" do
    field :user_id, :integer
    field :fingerprint, :string
    field :window_bucket, :integer
    field :dispatch_id, :string
    field :notification_kind, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Atomically claims the right to send a Telegram notification identified by
  `(user_id, fingerprint)` within the current window bucket.

  Returns:
    * `:ok` — claim acquired, caller should send.
    * `:duplicate` — another node/process already claimed this triple, skip.
    * `{:error, reason}` — DB unreachable or other failure; caller should fail
      open (send anyway) per project policy.
  """
  def claim(user_id, fingerprint, dispatch_id, kind)
      when is_integer(user_id) and is_binary(fingerprint) and is_binary(dispatch_id) do
    bucket = current_bucket()
    kind_string = to_string(kind)

    attrs = %{
      user_id: user_id,
      fingerprint: fingerprint,
      window_bucket: bucket,
      dispatch_id: dispatch_id,
      notification_kind: kind_string,
      inserted_at: DateTime.utc_now()
    }

    case Repo.insert_all(
           __MODULE__,
           [attrs],
           on_conflict: :nothing,
           conflict_target: [:user_id, :fingerprint, :window_bucket],
           returning: [:id]
         ) do
      {1, [_]} -> :ok
      {0, _} -> :duplicate
      other -> {:error, {:unexpected_insert_result, other}}
    end
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, e}
  end

  @doc """
  Deletes claim rows older than `cutoff_seconds_ago` seconds.

  Idempotent across nodes — fine for every node's sweeper to run it.
  """
  def prune(cutoff_seconds_ago) when is_integer(cutoff_seconds_ago) and cutoff_seconds_ago > 0 do
    cutoff = DateTime.utc_now() |> DateTime.add(-cutoff_seconds_ago, :second)

    {deleted, _} =
      from(c in __MODULE__, where: c.inserted_at < ^cutoff)
      |> Repo.delete_all()

    {:ok, deleted}
  end

  @doc """
  Returns the configured dedup window in seconds.
  """
  def window_seconds do
    Application.get_env(:coin_tracker, __MODULE__, [])
    |> Keyword.get(:window_seconds, @default_window_seconds)
  end

  @doc false
  # Public for test injection. Computes the current window bucket, optionally
  # overridable via process dictionary `:dispatch_claim_now_override` for tests
  # that want to advance time without sleeping.
  def current_bucket do
    now = Process.get(:dispatch_claim_now_override) || System.system_time(:second)
    div(now, window_seconds())
  end
end
