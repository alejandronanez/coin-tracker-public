defmodule CoinTracker.Trading.Position do
  use Ecto.Schema
  import Ecto.Changeset

  schema "positions" do
    field :entry_price, :decimal
    field :stop_loss_percent, :decimal
    field :take_profit_percent, :decimal
    field :amount_invested, :decimal
    field :current_threshold_zone, :decimal
    field :highest_alert_zone_reached, :decimal
    field :last_alerted_threshold_positive, :decimal
    field :last_alerted_negative_proximity, :integer
    field :last_alerted_volume_window_tier, :decimal
    field :last_alerted_volume_cumulative_tier, :decimal
    field :last_alerted_at, :utc_datetime
    field :last_known_pnl, :decimal
    field :status, Ecto.Enum, values: [:active, :closed], default: :active
    field :closed_reason, :string
    field :closed_at, :utc_datetime
    field :exit_price, :decimal
    field :source, :string, default: "manual"
    field :entry_rank, :integer
    field :kind, Ecto.Enum, values: [:tracked, :watched], default: :tracked
    field :symbol, :string, virtual: true
    field :exchange, :string, virtual: true

    belongs_to :user, CoinTracker.Accounts.User
    belongs_to :symbol_price, CoinTracker.Coins.SymbolPrice

    timestamps(type: :utc_datetime)
  end

  def changeset(position, attrs) do
    position
    |> cast(attrs, [
      :symbol,
      :entry_price,
      :stop_loss_percent,
      :take_profit_percent,
      :amount_invested,
      :current_threshold_zone
    ])
    |> validate_required([:entry_price, :stop_loss_percent, :take_profit_percent])
    |> validate_number(:entry_price, greater_than: 0)
    |> validate_number(:amount_invested, greater_than: 0)
    |> validate_number(:current_threshold_zone, greater_than: 0)
    |> validate_stop_loss_vs_take_profit()
  end

  def create_changeset(position, attrs) do
    # Strip /USDT suffix from symbol before validation to handle form resubmissions
    attrs =
      case Map.get(attrs, "symbol") || Map.get(attrs, :symbol) do
        nil ->
          attrs

        symbol when is_binary(symbol) ->
          clean_symbol = String.replace_suffix(symbol, "/USDT", "")
          # Only update the key type that exists in attrs
          cond do
            Map.has_key?(attrs, "symbol") -> Map.put(attrs, "symbol", clean_symbol)
            Map.has_key?(attrs, :symbol) -> Map.put(attrs, :symbol, clean_symbol)
            true -> attrs
          end

        _ ->
          attrs
      end

    position
    |> changeset(attrs)
    |> cast(attrs, [:current_threshold_zone, :exchange, :source])
    |> validate_required([:symbol, :current_threshold_zone, :exchange])
    |> validate_length(:symbol, min: 1, max: 20)
    |> validate_format(:symbol, ~r/^[\p{L}\p{N}]+$/u,
      message: "must contain only letters and numbers (supports any language)"
    )
    |> normalize_symbol()
    |> validate_number(:stop_loss_percent, less_than_or_equal_to: 0)
    |> validate_number(:take_profit_percent, greater_than: 0)
    |> validate_number(:current_threshold_zone, greater_than: 0)
  end

  @doc """
  Builds a changeset for a watched position created from a signal.

  Watched positions track signals for surge milestone alerts only — they have
  no `amount_invested`, `stop_loss_percent`, or `take_profit_percent`. The
  `entry_price` is the signal's `initial_price_usd` so the existing milestone
  alert math measures gain since the coin first entered the top 10.

  Caller is expected to set `:user_id`, `:symbol_price_id`, and `:entry_rank`
  via `put_change/3` after this changeset is built.
  """
  def watch_changeset(position, attrs) do
    position
    |> cast(attrs, [:symbol, :exchange, :entry_price, :current_threshold_zone, :source])
    |> validate_required([:symbol, :exchange, :entry_price, :current_threshold_zone])
    |> validate_number(:entry_price, greater_than: 0)
    |> validate_number(:current_threshold_zone, greater_than: 0)
    |> put_change(:kind, :watched)
    |> normalize_symbol()
    |> unique_constraint(:symbol_price_id,
      name: :positions_watched_unique_per_user_symbol,
      message: "already watched"
    )
  end

  defp validate_stop_loss_vs_take_profit(changeset) do
    stop_loss = get_field(changeset, :stop_loss_percent)
    take_profit = get_field(changeset, :take_profit_percent)

    if stop_loss && take_profit && Decimal.compare(stop_loss, take_profit) != :lt do
      add_error(
        changeset,
        :stop_loss_percent,
        "must be less than take profit percent"
      )
    else
      changeset
    end
  end

  defp normalize_symbol(changeset) do
    case get_change(changeset, :symbol) do
      nil ->
        changeset

      symbol ->
        # Only append /USDT if not already present
        normalized =
          symbol
          |> String.upcase()
          |> then(fn s ->
            if String.ends_with?(s, "/USDT") do
              s
            else
              s <> "/USDT"
            end
          end)

        put_change(changeset, :symbol, normalized)
    end
  end
end
