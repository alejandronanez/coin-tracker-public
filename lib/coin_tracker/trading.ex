defmodule CoinTracker.Trading do
  import Ecto.Changeset
  import Ecto.Query

  alias CoinTracker.Coins
  alias CoinTracker.Coins.{PriceClient, SymbolPrice}
  alias CoinTracker.Signals
  alias CoinTracker.Trading.Position
  alias CoinTracker.Repo
  alias CoinTracker.Watchlist

  @doc """
  Returns a map of unique symbol prices grouped by exchange for all active positions.

  This function is used by the PricePoller to efficiently batch-fetch current prices
  from exchanges for all active positions.

  ## Returns

  A map where keys are exchange atoms (e.g., `:binance_spot`) and values are lists
  of unique symbol pairs (e.g., `["ETH/USDT", "BTC/USDT"]`).

  ## Examples

      iex> Trading.get_symbol_prices_by_exchange_for_active_positions()
      %{
        binance_spot: ["ETH/USDT", "BTC/USDT"],
        bitget_spot: ["SOL/USDT"]
      }

      iex> Trading.get_symbol_prices_by_exchange_for_active_positions()
      %{}  # When no active positions exist
  """
  def get_symbol_prices_by_exchange_for_active_positions do
    # Watched positions intentionally included: their prices need to be polled so
    # surge milestone alerts (entry_price = signal.initial_price_usd) can fire.
    query =
      from p in Position,
        where: p.status == :active,
        join: sp in SymbolPrice,
        on: p.symbol_price_id == sp.id,
        distinct: [sp.exchange, sp.symbol_pair],
        select: {sp.exchange, sp.symbol_pair}

    Repo.all(query)
    |> Enum.group_by(fn {exchange, _symbol} -> exchange end, fn {_exchange, symbol} -> symbol end)
  end

  @doc """
  Creates a new position for a user by fetching current market price and storing position details.

  This function orchestrates the following steps:
  1. Validates the position attributes
  2. Fetches current price from the exchange API
  3. Upserts the symbol price in the database (creates or updates)
  4. Creates a position record linked to the user and symbol price

  All errors (validation, API, network) are converted to changeset errors for consistent
  error handling in the UI layer.

  ## Parameters

  - `user_id` - Integer ID of the user creating the position
  - `attrs` - Map with string keys containing:
    - `"symbol"` - String, the base symbol (e.g., "ETH", "BTC")
    - `"exchange"` - String, the exchange name (e.g., "binance_spot", "bitget_spot") - converted to atom internally
    - `"entry_price"` - String or number, the price the user paid for the asset - converted to Decimal
    - `"stop_loss_percent"` - String or number, percentage for stop loss - converted to Decimal
    - `"take_profit_percent"` - String or number, percentage for take profit - converted to Decimal
  - `opts` - Keyword list of options (e.g., [http_client: HTTPClientMock] for testing)

  ## Returns

  - `{:ok, %Position{}}` - Successfully created position
  - `{:error, %Ecto.Changeset{}}` - Any error (validation, API, network) with errors attached to changeset

  ## Examples

      iex> Trading.create_position(1, %{
      ...>   "symbol" => "ETH",
      ...>   "exchange" => "binance_spot",
      ...>   "entry_price" => "2000",
      ...>   "stop_loss_percent" => "-10",
      ...>   "take_profit_percent" => "20"
      ...> })
      {:ok, %Position{id: 1, entry_price: Decimal.new("2000"), ...}}

      iex> Trading.create_position(1, %{"symbol" => "INVALID", "exchange" => "binance_spot", ...})
      {:error, %Ecto.Changeset{errors: [symbol: {"Exchange API error: ...", []}]}}
  """
  def create_position(user_id, attrs, opts \\ []) do
    # Validate the changeset early before making API calls
    initial_changeset = Position.create_changeset(%Position{}, attrs)

    with {:changeset_valid, changeset} when changeset.valid? <-
           {:changeset_valid, initial_changeset},
         {:exchange, exchange} when not is_nil(exchange) <-
           {:exchange, parse_exchange(attrs["exchange"])},
         symbol <- get_field(changeset, :symbol),
         {:price_fetch, {:ok, [price | _]}} <-
           {:price_fetch, PriceClient.fetch_current_prices(exchange, [symbol], opts)},
         {:ok, symbol_price} <- upsert_symbol_price(exchange, price),
         {:ok, position} <- insert_position(user_id, symbol_price.id, changeset) do
      {:ok, position}
    else
      {:changeset_valid, changeset} ->
        # Changeset validation failed
        {:error, changeset}

      {:exchange, nil} ->
        # Invalid exchange
        changeset = add_symbol_error(attrs, "Invalid exchange")
        {:error, changeset}

      {:price_fetch, {:ok, []}} ->
        # No prices returned from API
        changeset = add_symbol_error(attrs, "No price data available for this symbol")
        {:error, changeset}

      {:price_fetch, {:error, {:api_error, message}}} ->
        # Exchange API error
        changeset = add_symbol_error(attrs, "Exchange API error: #{message}")
        {:error, changeset}

      {:price_fetch, {:error, :network_error}} ->
        # Network error
        changeset =
          add_symbol_error(attrs, "Network error. Please check your connection and try again.")

        {:error, changeset}

      {:error, %Ecto.Changeset{} = changeset} ->
        # Database insertion error
        {:error, changeset}

      error ->
        # Unexpected error fallback
        changeset = add_symbol_error(attrs, "An unexpected error occurred: #{inspect(error)}")
        {:error, changeset}
    end
  end

  @doc """
  Updates an existing position with new trading parameters.

  Only allows updating entry_price, stop_loss_percent, and take_profit_percent.
  Position must belong to the specified user for authorization.

  ## Parameters

  - `position_id` - Integer ID of the position to update
  - `user_id` - Integer ID of the user (for authorization)
  - `attrs` - Map with string keys containing fields to update:
    - `"entry_price"` - String or number, the new entry price - converted to Decimal
    - `"stop_loss_percent"` - String or number, the new stop loss percentage - converted to Decimal
    - `"take_profit_percent"` - String or number, the new take profit percentage - converted to Decimal

  ## Returns

  - `{:ok, %Position{}}` - Successfully updated position
  - `{:error, %Ecto.Changeset{}}` - Validation error or position not found
  - `{:error, :not_found}` - Position not found or doesn't belong to user

  ## Examples

      iex> Trading.update_position(1, 1, %{
      ...>   "entry_price" => "2500",
      ...>   "stop_loss_percent" => "-15",
      ...>   "take_profit_percent" => "25"
      ...> })
      {:ok, %Position{id: 1, entry_price: Decimal.new("2500"), ...}}

      iex> Trading.update_position(1, 999, %{...})
      {:error, :not_found}
  """
  def update_position(position_id, user_id, attrs) do
    case get_position_for_user(position_id, user_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, position} ->
        changeset = Position.changeset(position, attrs)
        Repo.update(changeset)
    end
  end

  @doc """
  Lists all active positions for a given user.

  Returns positions ordered by most recently created first, with symbol_price
  association preloaded to avoid N+1 queries.

  ## Parameters

  - `user_id` - Integer ID of the user

  ## Returns

  - List of `%Position{}` structs with preloaded :symbol_price association

  ## Examples

      iex> Trading.list_active_positions_for_user(1)
      [%Position{id: 1, status: :active, symbol_price: %SymbolPrice{...}}, ...]

      iex> Trading.list_active_positions_for_user(999)
      []
  """
  def list_active_positions_for_user(user_id) do
    from(p in Position,
      where: p.user_id == ^user_id and p.status == :active and p.kind == :tracked,
      order_by: [desc: p.inserted_at],
      preload: [:symbol_price]
    )
    |> Repo.all()
  end

  @doc """
  Lists all active positions for a specific symbol price.

  Used by PricePoller to check which positions need alert checking when
  a price update occurs.

  ## Parameters

  - `symbol_price_id` - Integer ID of the symbol price

  ## Returns

  - List of `%Position{}` structs with preloaded :symbol_price association

  ## Examples

      iex> Trading.list_active_positions_for_symbol_price(1)
      [%Position{id: 1, status: :active, symbol_price: %SymbolPrice{...}}, ...]

      iex> Trading.list_active_positions_for_symbol_price(999)
      []
  """
  def list_active_positions_for_symbol_price(symbol_price_id) do
    from(p in Position,
      where: p.symbol_price_id == ^symbol_price_id and p.status == :active,
      preload: [:symbol_price]
    )
    |> Repo.all()
  end

  @doc """
  Lists distinct user IDs that have an active position whose base symbol matches
  the given base symbol (e.g. "ETH" matches positions on "ETH/USDT").

  Used by the watchlist alert subscriber to fan out drop-out / re-entry alerts
  to every user who holds the affected coin.

  ## Parameters

  - `base_symbol` - Plain symbol like "ETH" (not "ETH/USDT"). Case-insensitive.

  ## Returns

  - List of integer user IDs.
  """
  def list_user_ids_with_active_position_for_symbol(base_symbol) when is_binary(base_symbol) do
    # Intentionally unfiltered by `kind`: both real positions and watched
    # entries should receive top-10 entry/exit Telegram alerts.
    upper = String.upcase(base_symbol)
    pattern = upper <> "/%"

    from(p in Position,
      join: sp in SymbolPrice,
      on: p.symbol_price_id == sp.id,
      where: p.status == :active and ilike(sp.symbol_pair, ^pattern),
      distinct: p.user_id,
      select: p.user_id
    )
    |> Repo.all()
  end

  @doc """
  Lists all active positions across all users with their `symbol_price` preloaded.

  Used by the watchlist coverage metric to determine the fraction of positions
  whose base symbol resolves to a current signal — the early-warning signal
  for symbol-matching breakage.
  """
  def list_all_active_positions do
    from(p in Position,
      where: p.status == :active and p.kind == :tracked,
      preload: [:symbol_price]
    )
    |> Repo.all()
  end

  @doc """
  Lists all closed positions for a specific user.

  Returns closed positions ordered by close date (most recent first).
  Useful for displaying position history and calculating historical PnL.

  ## Parameters

  - `user_id` - Integer ID of the user
  - `opts` - Keyword list of options:
    - `:limit` - Maximum number of positions to return (default: 100)

  ## Returns

  - List of `%Position{}` structs with preloaded :symbol_price association

  ## Examples

      iex> Trading.list_closed_positions_for_user(1)
      [%Position{id: 1, status: :closed, symbol_price: %SymbolPrice{...}}, ...]

      iex> Trading.list_closed_positions_for_user(999)
      []
  """
  def list_closed_positions_for_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(p in Position,
      where: p.user_id == ^user_id and p.status == :closed and p.kind == :tracked,
      order_by: [desc: p.closed_at],
      limit: ^limit,
      preload: [:symbol_price]
    )
    |> Repo.all()
  end

  @doc """
  Fetches a position by ID, verifying it belongs to the specified user.

  Used primarily for permission verification before operations like closing positions
  from untrusted (client) input. The position must exist and belong to the given user.

  ## Parameters

  - `position_id` - Integer ID of the position
  - `user_id` - Integer ID of the user who should own the position

  ## Returns

  - `{:ok, %Position{}}` - Position found and belongs to user, with preloaded :symbol_price association
  - `{:error, :not_found}` - Position doesn't exist or doesn't belong to user

  ## Examples

      iex> Trading.get_position_for_user(1, 1)
      {:ok, %Position{id: 1, user_id: 1, ...}}

      iex> Trading.get_position_for_user(1, 999)
      {:error, :not_found}
  """
  def get_position_for_user(position_id, user_id) do
    case from(p in Position,
           where: p.id == ^position_id and p.user_id == ^user_id,
           preload: [:symbol_price]
         )
         |> Repo.one() do
      nil -> {:error, :not_found}
      position -> {:ok, position}
    end
  end

  @doc """
  Calculates the profit/loss percentage between entry price and current price.

  Formula: ((current_price - entry_price) / entry_price) * 100

  ## Parameters

  - `entry_price` - Decimal, the price at which the position was entered
  - `current_price` - Decimal, the current market price

  ## Returns

  - Decimal representing the profit/loss percentage

  ## Examples

      iex> Trading.calculate_pnl_percent(Decimal.new("2000"), Decimal.new("2200"))
      Decimal.new("10.0")  # 10% profit

      iex> Trading.calculate_pnl_percent(Decimal.new("2000"), Decimal.new("1800"))
      Decimal.new("-10.0")  # 10% loss
  """
  def calculate_pnl_percent(entry_price, current_price) do
    entry_price
    |> Decimal.sub(current_price)
    |> Decimal.mult(-1)
    |> Decimal.div(entry_price)
    |> Decimal.mult(100)
  end

  @doc """
  Closes a position with the specified reason.

  Updates the position's status to :closed, sets the closure reason and timestamp.
  Already closed positions are not modified.

  ## Parameters

  - `position` - The position struct to close
  - `reason` - Atom indicating the closure reason (:take_profit, :stop_loss, or :manual)

  ## Returns

  - `{:ok, %Position{}}` - Successfully closed position
  - `{:error, %Ecto.Changeset{}}` - Error during update
  - `{:error, :already_closed}` - Position is already closed

  ## Examples

      iex> Trading.close_position(position, :take_profit)
      {:ok, %Position{status: :closed, closed_reason: "take_profit", ...}}

      iex> Trading.close_position(closed_position, :stop_loss)
      {:error, :already_closed}
  """
  def close_position(%Position{status: :closed} = _position, _reason) do
    {:error, :already_closed}
  end

  def close_position(%Position{} = position, reason)
      when reason in [:take_profit, :stop_loss, :manual] do
    # Ensure symbol_price is loaded to capture exit price
    position = Repo.preload(position, :symbol_price)
    exit_price = position.symbol_price.current_price

    changeset =
      position
      |> change()
      |> put_change(:status, :closed)
      |> put_change(:closed_reason, Atom.to_string(reason))
      |> put_change(:closed_at, DateTime.utc_now() |> DateTime.truncate(:second))
      |> put_change(:exit_price, exit_price)

    case Repo.update(changeset) do
      {:ok, closed_position} ->
        # Only broadcast for automatic closures (stop_loss, take_profit)
        # Manual closures are handled directly in the LiveView event handler
        if reason in [:take_profit, :stop_loss] do
          broadcast_position_closed(position, reason)
        end

        {:ok, closed_position}

      error ->
        error
    end
  end

  defp broadcast_position_closed(position, reason) do
    # Ensure symbol_price is loaded for the broadcast
    position = Repo.preload(position, :symbol_price)
    symbol_pair = position.symbol_price.symbol_pair

    Phoenix.PubSub.broadcast(
      CoinTracker.PubSub,
      "positions:#{position.user_id}",
      {:position_closed, position.id, symbol_pair, reason}
    )
  end

  defp parse_exchange("binance_spot"), do: :binance_spot
  defp parse_exchange("bitget_spot"), do: :bitget_spot
  defp parse_exchange("mexc_spot"), do: :mexc_spot
  defp parse_exchange(_), do: nil

  defp upsert_symbol_price(exchange, price) do
    Coins.upsert_symbol_price(%{
      exchange: exchange,
      symbol_pair: price.symbol,
      current_price: price.price
    })
  end

  defp insert_position(user_id, symbol_price_id, changeset) do
    base_symbol = changeset |> get_field(:symbol) |> Watchlist.base_symbol()
    entry_rank = lookup_entry_rank(base_symbol)

    changeset
    |> put_change(:user_id, user_id)
    |> put_change(:symbol_price_id, symbol_price_id)
    |> put_change(:entry_rank, entry_rank)
    |> Repo.insert()
  end

  defp lookup_entry_rank(nil), do: nil

  defp lookup_entry_rank(base_symbol) do
    case Signals.current_signal_for(base_symbol) do
      %{position: rank} -> rank
      _ -> nil
    end
  end

  @doc """
  Updates a position's alert tracking fields.

  Atomically updates last_alerted_threshold_positive, last_alerted_negative_proximity,
  and last_alerted_at to track which alerts have been sent.

  ## Parameters

  - `position` - The position struct to update
  - `threshold_positive` - Decimal, the positive threshold just alerted on (or nil to keep existing)
  - `proximity_negative` - Integer (80, 85, 90, 95) or nil to keep existing
  - `now` - DateTime timestamp for last_alerted_at (usually DateTime.utc_now())

  ## Returns

  - `{:ok, %Position{}}` - Successfully updated position
  - `{:error, %Ecto.Changeset{}}` - Update error

  ## Examples

      iex> Trading.update_position_alert_state(position, Decimal.new("4"), nil, DateTime.utc_now())
      {:ok, %Position{last_alerted_threshold_positive: Decimal.new("4"), ...}}

      iex> Trading.update_position_alert_state(position, nil, 85, DateTime.utc_now())
      {:ok, %Position{last_alerted_negative_proximity: 85, ...}}
  """
  def update_position_alert_state(position, threshold_positive, proximity_negative, now) do
    changes = %{}

    changes =
      if threshold_positive do
        Map.put(changes, :last_alerted_threshold_positive, threshold_positive)
      else
        changes
      end

    changes =
      if proximity_negative do
        Map.put(changes, :last_alerted_negative_proximity, proximity_negative)
      else
        changes
      end

    changes = Map.put(changes, :last_alerted_at, now)

    position
    |> change(changes)
    |> Repo.update()
  end

  @doc """
  Updates only the last_alerted_threshold_positive field without updating the alert timestamp.

  Used to track threshold position when price drops below the last alerted threshold,
  enabling detection of re-crossings without resetting the 30-second throttle.

  ## Parameters

  - `position` - The position struct to update
  - `threshold_positive` - Decimal, the current threshold to track

  ## Returns

  - `{:ok, %Position{}}` - Successfully updated position
  - `{:error, %Ecto.Changeset{}}` - Update error

  ## Examples

      iex> Trading.update_position_threshold(position, Decimal.new("0"))
      {:ok, %Position{last_alerted_threshold_positive: Decimal.new("0"), ...}}
  """
  def update_position_threshold(position, threshold_positive) do
    position
    |> change(%{last_alerted_threshold_positive: threshold_positive})
    |> Repo.update()
  end

  @doc """
  Updates the watch-mode short-window volume surge alert state.

  Sets `last_alerted_volume_window_tier` to the tier just alerted on, and
  bumps `last_alerted_at` so the shared 30s throttle covers volume alerts
  too. Used in watch-mode after `PositionAlert.check_volume_window_surge/4`
  fires.
  """
  def update_position_volume_window_alert(position, tier, now) do
    position
    |> change(%{last_alerted_volume_window_tier: tier, last_alerted_at: now})
    |> Repo.update()
  end

  @doc """
  Updates the watch-mode cumulative since-signal volume alert state.

  Sets `last_alerted_volume_cumulative_tier` and bumps `last_alerted_at`.
  Used in watch-mode after `PositionAlert.check_volume_cumulative_tier/3`
  fires.
  """
  def update_position_volume_cumulative_alert(position, tier, now) do
    position
    |> change(%{last_alerted_volume_cumulative_tier: tier, last_alerted_at: now})
    |> Repo.update()
  end

  @doc """
  Updates only the last_known_pnl field to track PnL across poll cycles.

  Used to detect recovery alert transitions by comparing previous PnL with current PnL.
  This field is updated after every alert check cycle, regardless of whether alerts were sent.

  ## Parameters

  - `position` - The position struct to update
  - `current_pnl` - Decimal, the current PnL to store for next cycle comparison

  ## Returns

  - `{:ok, %Position{}}` - Successfully updated position
  - `{:error, %Ecto.Changeset{}}` - Update error

  ## Examples

      iex> Trading.update_position_pnl(position, Decimal.new("5.5"))
      {:ok, %Position{last_known_pnl: Decimal.new("5.5"), ...}}
  """
  def update_position_pnl(position, current_pnl) do
    position
    |> change(%{last_known_pnl: current_pnl})
    |> Repo.update()
  end

  @default_watch_threshold_zone Decimal.new("5")

  @doc """
  Creates a watched position from a signal.

  Watched positions exist purely to receive Telegram alerts (top-10
  entry/exit and surge milestones). They have no `amount_invested`,
  `stop_loss_percent`, or `take_profit_percent`. The `entry_price` is the
  signal's `initial_price_usd`, which becomes the baseline for surge
  milestone alerts (default step: 5%).

  Idempotent: if the user already has a watch for this signal's base symbol,
  returns the existing watched position.
  """
  def watch_signal(user_id, %CoinTracker.Signals.Signal{} = signal) do
    signal = CoinTracker.Repo.preload(signal, :symbol_price)

    cond do
      is_nil(signal.symbol_price) ->
        {:error, :no_symbol_price}

      is_nil(signal.initial_price_usd) ->
        {:error, :no_initial_price}

      true ->
        base_symbol = Watchlist.base_symbol(signal.symbol_price.symbol_pair)

        case get_watch_for_user_and_symbol(user_id, base_symbol) do
          nil ->
            case insert_watch(user_id, signal, base_symbol) do
              {:ok, position} ->
                {:ok, position}

              {:error, %Ecto.Changeset{errors: errors} = changeset} ->
                # Concurrent watch insert won the race — surface the existing
                # row instead of the raw constraint error so callers see the
                # idempotent contract regardless of timing.
                if Keyword.has_key?(errors, :symbol_price_id) do
                  case get_watch_for_user_and_symbol(user_id, base_symbol) do
                    %Position{} = existing -> {:ok, existing}
                    nil -> {:error, changeset}
                  end
                else
                  {:error, changeset}
                end
            end

          %Position{} = existing ->
            {:ok, existing}
        end
    end
  end

  defp insert_watch(user_id, signal, base_symbol) do
    attrs = %{
      "symbol" => base_symbol,
      "exchange" => Atom.to_string(signal.symbol_price.exchange),
      "entry_price" => signal.initial_price_usd,
      "current_threshold_zone" => @default_watch_threshold_zone,
      "source" => "watch"
    }

    entry_rank = lookup_entry_rank(base_symbol)

    %Position{}
    |> Position.watch_changeset(attrs)
    |> put_change(:user_id, user_id)
    |> put_change(:symbol_price_id, signal.symbol_price.id)
    |> put_change(:entry_rank, entry_rank)
    |> Repo.insert()
  end

  @doc """
  Permanently removes a closed position from a user's history by id.

  Used by the Closed Positions screen's Remove CTA so users can prune
  their PnL history. The query is scoped to the user and to closed
  positions only — active or watched positions are untouched.

  Returns `{:ok, position}` on success or `{:error, :not_found}` when
  no matching closed position exists for that user.
  """
  def delete_closed_position_for_user(user_id, position_id) do
    query =
      from p in Position,
        where: p.id == ^position_id and p.user_id == ^user_id and p.status == :closed

    case Repo.one(query) do
      %Position{} = position -> Repo.delete(position)
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Removes a watched position by id, verifying it belongs to the user and is
  actually a watch. Used by the Watched tab's Unwatch button so it keeps
  working for coins whose live signal has expired (no `current_signal`).

  Returns `{:ok, position}` on success or `{:error, :not_found}`.
  """
  def unwatch_position_for_user(user_id, position_id) do
    query =
      from p in Position,
        where:
          p.id == ^position_id and p.user_id == ^user_id and p.kind == :watched and
            p.status == :active

    case Repo.one(query) do
      %Position{} = position -> Repo.delete(position)
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Removes the user's watch for the given signal's base symbol. Returns
  `{:ok, position}` on success or `{:error, :not_found}` if no watch exists.
  Closed positions are not affected.
  """
  def unwatch_signal(user_id, %CoinTracker.Signals.Signal{} = signal) do
    signal = CoinTracker.Repo.preload(signal, :symbol_price)
    base_symbol = signal.symbol_price && Watchlist.base_symbol(signal.symbol_price.symbol_pair)

    case base_symbol && get_watch_for_user_and_symbol(user_id, base_symbol) do
      %Position{} = position -> Repo.delete(position)
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Lists the user's active watched positions with `:symbol_price` preloaded.
  """
  def list_watched_positions_for_user(user_id) do
    from(p in Position,
      where: p.user_id == ^user_id and p.status == :active and p.kind == :watched,
      order_by: [desc: p.inserted_at],
      preload: [:symbol_price]
    )
    |> Repo.all()
  end

  @doc """
  Returns a `MapSet` of base symbols (e.g., `"ETH"`) that the user is
  currently watching. Used by the signals UI to render filled vs empty stars.
  """
  def watched_base_symbols_for_user(user_id) do
    from(p in Position,
      join: sp in SymbolPrice,
      on: p.symbol_price_id == sp.id,
      where: p.user_id == ^user_id and p.status == :active and p.kind == :watched,
      select: sp.symbol_pair
    )
    |> Repo.all()
    |> Enum.map(&Watchlist.base_symbol/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  @doc """
  Returns true if the user has an active watch on the given base symbol.

  Single-symbol equivalent of `watched_base_symbols_for_user/1` — runs a
  targeted SELECT instead of fetching all watches and building a `MapSet`.
  """
  def watching?(user_id, base_symbol) do
    not is_nil(get_watch_for_user_and_symbol(user_id, base_symbol))
  end

  defp get_watch_for_user_and_symbol(_user_id, nil), do: nil

  defp get_watch_for_user_and_symbol(user_id, base_symbol) do
    pattern = base_symbol <> "/%"

    from(p in Position,
      join: sp in SymbolPrice,
      on: p.symbol_price_id == sp.id,
      where:
        p.user_id == ^user_id and p.status == :active and p.kind == :watched and
          ilike(sp.symbol_pair, ^pattern),
      preload: [:symbol_price],
      limit: 1
    )
    |> Repo.one()
  end

  defp add_symbol_error(attrs, message) do
    original_symbol = attrs["symbol"] || attrs[:symbol]

    changeset =
      %Position{}
      |> Position.create_changeset(attrs)
      |> add_error(:symbol, message)
      |> Map.put(:action, :insert)

    if original_symbol do
      put_change(changeset, :symbol, original_symbol)
    else
      changeset
    end
  end
end
