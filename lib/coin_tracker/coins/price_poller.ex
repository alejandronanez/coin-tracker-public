defmodule CoinTracker.Coins.PricePoller do
  @moduledoc """
  GenServer that periodically fetches and updates current prices for active positions.

  This poller efficiently batches price requests by exchange, leveraging the fact that
  exchanges like Binance support fetching up to 50 symbols in a single API call.

  ## Configuration

  Configure in your environment config files:

      # Enable polling with 5 second interval
      config :coin_tracker, CoinTracker.Coins.PricePoller,
        enabled: true,
        interval: :timer.seconds(5)

      # Disable polling (useful for test environment)
      config :coin_tracker, CoinTracker.Coins.PricePoller,
        enabled: false

  ## Options

    * `:enabled` - Whether polling is enabled (default: `true`)
    * `:interval` - Polling interval in milliseconds (default: `5_000` = 5 seconds)

  The poller will start immediately and then run at the configured interval.
  Errors during polling are logged but do not crash the poller.

  ## Error Handling

  The poller is designed to be resilient and never crash:

    * Database errors during zone updates are logged and retried on next poll
    * Position closure failures are logged with CRITICAL level for monitoring
    * Race conditions (e.g., already closed positions) are handled gracefully
    * All error paths return `:ok` to prevent GenServer crashes

  Price updates are broadcast via Phoenix.PubSub on the "price_updates" topic
  to enable real-time UI updates in LiveViews.
  """

  use GenServer

  alias CoinTracker.Coins
  alias CoinTracker.Log
  alias CoinTracker.Coins.PriceClient
  alias CoinTracker.Signals
  alias CoinTracker.Signals.Signal
  alias CoinTracker.Trading
  alias CoinTracker.Trading.AlertZone
  alias CoinTracker.Trading.PositionAlert
  alias CoinTracker.TelegramClient.TelegramService

  @default_interval :timer.seconds(5)

  # Client API

  @doc """
  Starts the poller GenServer.

  The poller can be started with custom options or will use configuration values.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers a poll immediately.

  This is useful for testing or manual operations.
  Returns `:ok` and the poll happens asynchronously.
  """
  def poll_now do
    GenServer.cast(__MODULE__, :poll)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = get_config()

    state = %{
      enabled: Keyword.get(opts, :enabled, config[:enabled]),
      interval: Keyword.get(opts, :interval, config[:interval])
    }

    if state.enabled do
      Log.info("Price poller starting with interval: #{state.interval}ms",
        module: :price_poller,
        operation: :init
      )

      # Schedule first poll immediately
      send(self(), :poll)
      {:ok, state}
    else
      Log.info("Price poller disabled via configuration",
        module: :price_poller,
        operation: :init
      )

      {:ok, Map.put(state, :enabled, false)}
    end
  end

  @impl true
  def handle_info(:poll, %{enabled: false} = state) do
    # Poller is disabled, don't schedule next poll
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, %{enabled: true, interval: interval} = state) do
    # Perform the poll
    perform_poll()

    # Schedule next poll
    Process.send_after(self(), :poll, interval)

    {:noreply, state}
  end

  @impl true
  def handle_cast(:poll, state) do
    perform_poll()
    {:noreply, state}
  end

  # Private functions

  defp perform_poll do
    Log.debug("Starting price update poll for active positions",
      module: :price_poller,
      operation: :poll
    )

    # Get all unique symbol prices grouped by exchange for active positions
    symbol_prices_by_exchange = Trading.get_symbol_prices_by_exchange_for_active_positions()

    if symbol_prices_by_exchange == %{} do
      Log.debug("No active positions found, skipping price update",
        module: :price_poller,
        operation: :poll
      )
    else
      # Process each exchange
      Enum.each(symbol_prices_by_exchange, fn {exchange, symbols} ->
        update_prices_for_exchange(exchange, symbols)
      end)
    end
  end

  defp update_prices_for_exchange(exchange, symbols) do
    Log.debug("Fetching prices for #{length(symbols)} symbols from #{exchange}",
      module: :price_poller,
      operation: :fetch_prices,
      exchange: exchange
    )

    case PriceClient.fetch_current_prices(exchange, symbols) do
      {:ok, prices} ->
        Log.debug("Successfully fetched #{length(prices)} prices from #{exchange}",
          module: :price_poller,
          operation: :fetch_prices,
          exchange: exchange
        )

        # Update each price in the database and check for alerts
        updated_count =
          Enum.reduce(prices, 0, fn price, acc ->
            case Coins.upsert_symbol_price(%{
                   exchange: exchange,
                   symbol_pair: price.symbol,
                   current_price: price.price
                 }) do
              {:ok, symbol_price} ->
                # Check for position alerts after price update
                check_position_alerts(symbol_price)
                acc + 1

              {:error, reason} ->
                Log.db_error("Failed to update price for #{price.symbol} on #{exchange}",
                  module: :price_poller,
                  operation: :update_price,
                  exchange: exchange,
                  symbol: price.symbol,
                  reason: inspect(reason)
                )

                acc
            end
          end)

        Log.info("Updated #{updated_count}/#{length(prices)} prices for #{exchange}",
          module: :price_poller,
          operation: :update_prices,
          exchange: exchange
        )

      {:error, {:api_error, message}} ->
        Log.api_error("API error fetching prices from #{exchange}: #{message}",
          module: :price_poller,
          operation: :fetch_prices,
          exchange: exchange
        )

      {:error, :network_error} ->
        Log.network_error("Network error fetching prices from #{exchange}",
          module: :price_poller,
          operation: :fetch_prices,
          exchange: exchange
        )
    end
  end

  defp check_position_alerts(symbol_price) do
    # Get all active positions for this symbol price
    positions = Trading.list_active_positions_for_symbol_price(symbol_price.id)

    # Check each position for alert conditions
    Enum.each(positions, fn position ->
      check_single_position_alerts(position, symbol_price.current_price)
    end)
  end

  @doc false
  # Public for test access only. Do not call directly from outside the poller.
  def check_single_position_alerts(%{kind: :watched} = position, current_price) do
    # Watched positions track signals only — no real money, no stop-loss /
    # take-profit. Skip closure, recovery, and proximity (they require those
    # fields). Surge milestone alerts still fire because `entry_price` was
    # set to `signal.initial_price_usd` at watch time.
    current_pnl = AlertZone.calculate_current_pnl(position.entry_price, current_price)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    check_watch_alerts(position, current_pnl, now)
  end

  def check_single_position_alerts(position, current_price) do
    # Calculate alert zones based on position configuration
    alert_zones =
      AlertZone.determine_alert_zones(
        position.current_threshold_zone,
        position.take_profit_percent,
        position.stop_loss_percent
      )

    # Calculate current PnL
    current_pnl = AlertZone.calculate_current_pnl(position.entry_price, current_price)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Priority 1: Check for critical closure alerts (take-profit / stop-loss)
    case PositionAlert.check_closure_alert(
           current_pnl,
           alert_zones,
           current_price,
           position.amount_invested
         ) do
      {:close, reason, message} ->
        handle_position_closure(position, reason, message, now)

      :no_close ->
        # Priority 2: Check non-critical alerts (only if position is not closing)
        check_non_critical_alerts(position, current_pnl, now)
    end
  end

  defp check_watch_alerts(position, current_pnl, now) do
    symbol = position.symbol_price.symbol_pair

    {position, price_alert_sent?} =
      handle_watch_price_surge(position, current_pnl, now, symbol)

    position =
      if price_alert_sent? do
        position
      else
        handle_watch_volume_alerts(position, now, symbol)
      end

    case Trading.update_position_pnl(position, Decimal.new(current_pnl)) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Log.warn("Failed to update last_known_pnl for watched position #{position.id}", :db_error,
          module: :price_poller,
          operation: :update_position_pnl,
          position_id: position.id,
          reason: inspect(reason)
        )
    end
  end

  defp handle_watch_price_surge(position, current_pnl, now, symbol) do
    case PositionAlert.check_watch_surge_alert(position, current_pnl, now) do
      {:alert, current_threshold} ->
        send_alert_message(
          position,
          symbol,
          PositionAlert.watch_surge_message(current_threshold),
          :watch_surge
        )

        position =
          apply_alert_update(position, fn ->
            Trading.update_position_alert_state(position, current_threshold, nil, now)
          end)

        {position, true}

      :no_alert ->
        current_threshold =
          PositionAlert.calculate_current_threshold(
            Decimal.new(current_pnl),
            Decimal.new(position.current_threshold_zone)
          )

        last_alerted = position.last_alerted_threshold_positive || Decimal.new("0")

        position =
          if Decimal.compare(current_threshold, last_alerted) == :lt do
            apply_alert_update(position, fn ->
              Trading.update_position_threshold(position, current_threshold)
            end)
          else
            position
          end

        {position, false}
    end
  end

  # Volume-based watch-mode alerts. Runs only when the price-surge branch did
  # not fire, preserving the existing "at most one alert per tick" contract.
  # Priority within this branch: short-window surge (more actionable) >
  # cumulative since-signal tier.
  defp handle_watch_volume_alerts(position, now, symbol) do
    base_symbol = String.replace_suffix(symbol, "/USDT", "")

    case Signals.current_signal_for(base_symbol) do
      nil ->
        position

      %Signal{} = signal ->
        case handle_window_volume_surge(position, signal, now, symbol) do
          {position, true} -> position
          {position, false} -> handle_cumulative_volume_tier(position, signal, now, symbol)
        end
    end
  end

  defp handle_window_volume_surge(position, signal, now, symbol) do
    lookback =
      DateTime.add(now, -PositionAlert.volume_window_lookback_minutes() * 60, :second)

    snapshot =
      Signals.snapshot_for_signal_at_or_before(
        signal.id,
        lookback,
        PositionAlert.volume_window_tolerance_minutes()
      )

    case snapshot do
      nil ->
        {position, false}

      %{current_volume_24h: baseline_volume} ->
        case PositionAlert.check_volume_window_surge(
               position,
               signal.current_volume_24h,
               baseline_volume,
               now
             ) do
          {:alert, tier} ->
            send_alert_message(
              position,
              symbol,
              PositionAlert.volume_window_surge_message(tier),
              :watch_volume_window_surge
            )

            position =
              apply_alert_update(position, fn ->
                Trading.update_position_volume_window_alert(position, tier, now)
              end)

            {position, true}

          :no_alert ->
            {position, false}
        end
    end
  end

  defp handle_cumulative_volume_tier(position, signal, now, symbol) do
    growth_pct = Signal.volume_increase_percentage(signal)

    case PositionAlert.check_volume_cumulative_tier(position, growth_pct, now) do
      {:alert, tier} ->
        send_alert_message(
          position,
          symbol,
          PositionAlert.volume_cumulative_tier_message(tier),
          :watch_volume_cumulative_tier
        )

        apply_alert_update(position, fn ->
          Trading.update_position_volume_cumulative_alert(position, tier, now)
        end)

      :no_alert ->
        position
    end
  end

  defp check_non_critical_alerts(position, current_pnl, now) do
    symbol = position.symbol_price.symbol_pair

    # Calculate current threshold once for both alert check and tracking
    current_threshold =
      PositionAlert.calculate_current_threshold(
        Decimal.new(current_pnl),
        Decimal.new(position.current_threshold_zone)
      )

    # Each step rebinds `position` to the freshly updated struct returned by Trading
    # so subsequent throttle checks (`position.last_alerted_at`) see post-write state.
    # `alert_sent?` short-circuits later checks: at most one Telegram message per tick,
    # otherwise a position that crosses a threshold AND recovers in the same observation
    # would fire two messages back-to-back even though the user experienced one event.
    {position, alert_sent?} =
      handle_positive_alert(position, current_pnl, now, current_threshold, symbol)

    {position, alert_sent?} =
      if alert_sent? do
        {position, true}
      else
        handle_recovery_alert(position, current_pnl, now, symbol)
      end

    position =
      if alert_sent? do
        position
      else
        handle_proximity_alert(position, current_pnl, now, symbol)
      end

    # Always update last_known_pnl after all alert checks for next cycle comparison
    case Trading.update_position_pnl(position, Decimal.new(current_pnl)) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Log.warn("Failed to update last_known_pnl for position #{position.id}", :db_error,
          module: :price_poller,
          operation: :update_position_pnl,
          position_id: position.id,
          reason: inspect(reason)
        )
    end
  end

  defp handle_positive_alert(position, current_pnl, now, current_threshold, symbol) do
    case PositionAlert.check_positive_alert(position, current_pnl, now) do
      {:alert, message} ->
        send_alert_message(position, symbol, message, :threshold)

        position =
          apply_alert_update(position, fn ->
            Trading.update_position_alert_state(position, current_threshold, nil, now)
          end)

        {position, true}

      :no_alert ->
        # Track threshold drops for re-crossing detection without resetting throttle
        last_alerted = position.last_alerted_threshold_positive || Decimal.new("0")

        position =
          if Decimal.compare(current_threshold, last_alerted) == :lt do
            apply_alert_update(position, fn ->
              Trading.update_position_threshold(position, current_threshold)
            end)
          else
            position
          end

        {position, false}
    end
  end

  defp handle_recovery_alert(position, current_pnl, now, symbol) do
    case PositionAlert.check_recovery_alert(
           position.last_known_pnl,
           current_pnl,
           now,
           position.last_alerted_at
         ) do
      {:alert, message} ->
        send_alert_message(position, symbol, message, :recovery)

        position =
          apply_alert_update(position, fn ->
            Trading.update_position_alert_state(position, nil, nil, now)
          end)

        {position, true}

      :no_alert ->
        {position, false}
    end
  end

  defp handle_proximity_alert(position, current_pnl, now, symbol) do
    case PositionAlert.check_negative_proximity_alert(position, current_pnl, now) do
      {:alert, message, proximity} ->
        send_alert_message(position, symbol, message, :proximity)

        apply_alert_update(position, fn ->
          Trading.update_position_alert_state(position, nil, proximity, now)
        end)

      :no_alert ->
        position
    end
  end

  defp send_alert_message(position, symbol, message, alert_type) do
    alert_message = "#{symbol}: #{message}"

    case TelegramService.send_message(position.user_id, alert_message,
           kind: alert_kind(alert_type)
         ) do
      {:ok, :sent} ->
        Log.info("Sent #{alert_type} alert for position #{position.id}",
          module: :price_poller,
          operation: :send_alert,
          alert_type: alert_type,
          position_id: position.id,
          user_id: position.user_id
        )

      {:ok, :suppressed} ->
        # Cluster-wide duplicate: another node already sent this alert. The user
        # IS being notified — just not by us. TelegramService logs the suppression
        # at warn level with full dispatch metadata, so no extra log here.
        :ok

      {:error, reason} ->
        Log.warn(
          "Failed to send #{alert_type} alert for position #{position.id}",
          :telegram_error,
          module: :price_poller,
          operation: :send_alert,
          alert_type: alert_type,
          position_id: position.id,
          user_id: position.user_id,
          reason: inspect(reason)
        )

      :ok ->
        :ok
    end
  end

  defp alert_kind(:threshold), do: :position_threshold
  defp alert_kind(:recovery), do: :position_recovery
  defp alert_kind(:proximity), do: :position_proximity
  defp alert_kind(:watch_surge), do: :watch_surge
  defp alert_kind(:watch_volume_window_surge), do: :watch_volume_window_surge
  defp alert_kind(:watch_volume_cumulative_tier), do: :watch_volume_cumulative_tier

  # Runs the DB update and returns the freshly persisted struct on success so
  # downstream throttle checks see the new `last_alerted_at`. On failure we keep
  # the pre-update struct (next tick will pick up fresh DB state) — but the
  # caller still treats the alert as sent so we don't double-fire in this tick.
  defp apply_alert_update(position, update_fn) do
    case update_fn.() do
      {:ok, updated} ->
        updated

      {:error, reason} ->
        Log.warn(
          "Failed to update alert tracking for position #{position.id}",
          :db_error,
          module: :price_poller,
          operation: :update_alert_state,
          position_id: position.id,
          reason: inspect(reason)
        )

        position
    end
  end

  defp handle_position_closure(position, close_reason, alert_message, _now) do
    case Trading.close_position(position, close_reason) do
      {:ok, _closed_position} ->
        # Send critical alert notification via Telegram
        symbol = position.symbol_price.symbol_pair
        alert_with_symbol = "#{symbol}: #{alert_message}"

        case TelegramService.send_message(position.user_id, alert_with_symbol,
               kind: :position_closure
             ) do
          {:ok, :sent} ->
            Log.info(
              "Position #{position.id} closed successfully. " <>
                "Reason: #{close_reason}. Alert message sent to user #{position.user_id}.",
              module: :price_poller,
              operation: :close_position,
              position_id: position.id,
              user_id: position.user_id
            )

          {:ok, :suppressed} ->
            # Another node already notified the user of this closure. The position
            # is closed in Postgres (single source of truth); the user has been
            # notified via the winning node. Info, NOT critical — no missed alert.
            Log.info(
              "Position #{position.id} closed successfully (Reason: #{close_reason}). " <>
                "Telegram alert suppressed (cluster-wide duplicate — another node sent it).",
              module: :price_poller,
              operation: :close_position,
              position_id: position.id,
              user_id: position.user_id
            )

          {:error, telegram_error} ->
            Log.critical(
              "Position #{position.id} closed (#{close_reason}) but Telegram alert failed. " <>
                "User was NOT notified of position closure.",
              module: :price_poller,
              operation: :close_position,
              position_id: position.id,
              user_id: position.user_id,
              reason: inspect(telegram_error)
            )

          :ok ->
            # User has no Telegram linked
            Log.info(
              "Position #{position.id} closed successfully (Reason: #{close_reason}). " <>
                "No Telegram alert sent (user has no Telegram linked).",
              module: :price_poller,
              operation: :close_position,
              position_id: position.id,
              user_id: position.user_id
            )
        end

        :ok

      {:error, :already_closed} ->
        # Position was already closed (possible race condition)
        Log.info(
          "Position #{position.id} was already closed when attempting to close it. " <>
            "This is likely a race condition and is safe to ignore.",
          module: :price_poller,
          operation: :close_position,
          position_id: position.id
        )

        :ok

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        # Database error during closure - this is serious
        Log.critical(
          "Failed to close position #{position.id}. " <>
            "Reason: #{close_reason}. Manual intervention may be required. Position remains open. " <>
            "See GitHub issue #25 for tracking admin notification system.",
          module: :price_poller,
          operation: :close_position,
          position_id: position.id,
          user_id: position.user_id,
          reason: inspect(changeset.errors)
        )

        # TODO: Implement admin notification system (GitHub issue #25)
        # AlertService.send_system_alert(:position_closure_failed, %{
        #   position_id: position.id,
        #   close_reason: close_reason,
        #   errors: changeset.errors
        # })

        :ok

      {:error, reason} ->
        # Unexpected error
        Log.critical(
          "Unexpected error closing position #{position.id}. Manual intervention required.",
          module: :price_poller,
          operation: :close_position,
          position_id: position.id,
          user_id: position.user_id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp get_config do
    config = Application.get_env(:coin_tracker, __MODULE__, [])

    [
      enabled: Keyword.get(config, :enabled, true),
      interval: Keyword.get(config, :interval, @default_interval)
    ]
  end
end
