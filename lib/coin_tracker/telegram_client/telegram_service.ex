defmodule CoinTracker.TelegramClient.TelegramService do
  @moduledoc """
  Service for managing Telegram integration.

  Handles Telegram user registration, position listing, and message delivery.
  Operates independently from the Telegram bot handler to maintain clean separation of concerns.
  """

  alias CoinTracker.Accounts
  alias CoinTracker.Log
  alias CoinTracker.Signals
  alias CoinTracker.TelegramClient.DispatchClaim
  alias CoinTracker.TelegramClient.DuplicateDetector
  alias CoinTracker.Trading

  @bot :coin_tracker_bot

  @doc """
  Generates a Telegram registration deeplink for a user.

  Creates a one-time token and returns a deeplink URL that the user can click
  to open the Telegram bot and register their chat.

  ## Examples

      iex> {:ok, user} = Accounts.generate_telegram_token(user)
      iex> TelegramService.generate_deeplink(user)
      {:ok, "https://t.me/coin_tracker_dev_bot?start=abc123..."}

  """
  def generate_deeplink(%Accounts.User{} = user) do
    case Accounts.generate_telegram_token(user) do
      {:ok, updated_user} ->
        deeplink = "https://t.me/#{bot_username()}?start=#{updated_user.telegram_token}"
        {:ok, deeplink}

      {:error, reason} ->
        Log.telegram_error("Failed to generate Telegram token",
          module: :telegram,
          operation: :generate_deeplink,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Registers a Telegram chat for a user.

  Validates the registration token, creates a TelegramUser record to link
  the chat_id to the user, and invalidates the token to prevent reuse.

  ## Examples

      iex> TelegramService.register_chat(123456789, "abc123...")
      {:ok, "Welcome! Your Telegram is now linked to your account."}

      iex> TelegramService.register_chat(123456789, "invalid")
      {:error, "Invalid or expired token"}

  """
  def register_chat(chat_id, token) when is_integer(chat_id) and is_binary(token) do
    case Accounts.get_user_by_telegram_token(token) do
      nil ->
        # Only log token prefix for security - don't expose full token
        Log.warn("Invalid Telegram registration token attempted", :telegram_error,
          module: :telegram,
          operation: :register_chat,
          token_prefix: String.slice(token, 0, 8) <> "..."
        )

        {:error, "Invalid or expired token"}

      user ->
        case Accounts.create_telegram_user(%{chat_id: chat_id, user_id: user.id}) do
          {:ok, _telegram_user} ->
            # Invalidate the token so it can't be reused
            with {:ok, _} <- Accounts.invalidate_telegram_token(user) do
              {:ok, "Welcome! Your Telegram account is now linked."}
            else
              {:error, reason} ->
                Log.telegram_error("Failed to invalidate Telegram token",
                  module: :telegram,
                  operation: :register_chat,
                  user_id: user.id,
                  reason: inspect(reason)
                )

                {:error, "Setup completed but token invalidation failed"}
            end

          {:error, reason} ->
            Log.warn("Failed to create TelegramUser", :telegram_error,
              module: :telegram,
              operation: :register_chat,
              user_id: user.id,
              reason: inspect(reason)
            )

            cond do
              match?(%{errors: [user_id: _]}, reason) ->
                {:error, "This Telegram account is already linked to another account"}

              match?(%{errors: [chat_id: _]}, reason) ->
                {:error, "This Telegram account is already linked to another user"}

              true ->
                {:error, "Failed to link Telegram account"}
            end
        end
    end
  end

  @doc """
  Lists active positions for a user identified by their Telegram chat_id.

  Returns a formatted message with position details, or a message if no positions exist.

  ## Examples

      iex> TelegramService.list_positions(123456789)
      {:ok, "📊 Your Active Positions:\\n\\n1. ETH/USDT..."}

      iex> TelegramService.list_positions(999999)
      {:error, "Telegram account not linked"}

  """
  def list_positions(chat_id) when is_integer(chat_id) do
    case Accounts.get_user_by_telegram_chat_id(chat_id) do
      nil ->
        Log.warn("List positions requested from unlinked chat_id", :telegram_error,
          module: :telegram,
          operation: :list_positions
        )

        {:error, "Telegram account not linked to any user"}

      user ->
        positions = Trading.list_active_positions_for_user(user.id)

        if Enum.empty?(positions) do
          {:ok, "📊 You have no active positions yet."}
        else
          message = format_positions_message(positions)
          {:ok, message}
        end
    end
  end

  @doc """
  Gets the current market status for a user identified by their Telegram chat_id.

  Returns the market status message in the same format as market status alerts.

  ## Examples

      iex> TelegramService.get_market_status(123456789)
      {:ok, "🟢 Market: 10/10"}

      iex> TelegramService.get_market_status(999999)
      {:error, "Telegram account not linked to any user"}

  """
  def get_market_status(chat_id) when is_integer(chat_id) do
    case Accounts.get_user_by_telegram_chat_id(chat_id) do
      nil ->
        Log.warn("Market status requested from unlinked chat_id", :telegram_error,
          module: :telegram,
          operation: :get_market_status
        )

        {:error, "Telegram account not linked to any user"}

      _user ->
        count = Signals.count_active_signals()
        message = format_market_status_message(count)
        {:ok, message}
    end
  end

  defp format_market_status_message(count) when count == 10, do: "🟢 Market: 10/10"
  defp format_market_status_message(count), do: "🔴 Market: #{count}/10"

  @doc """
  Gets the list of top 10 coins ordered by rank in ascending order.

  Returns a formatted message with each coin's rank, symbol, and time in top.

  ## Examples

      iex> TelegramService.get_top_coins()
      {:ok, "🏆 Top 10 Coins\\n\\n1 - BTC - entered top 2d 5h ago\\n..."}

  """
  def get_top_coins do
    signals = Signals.list_signals(active: true, in_top: true, order_by: [asc: :position])

    if Enum.empty?(signals) do
      {:ok, "🏆 No coins in top 10 currently."}
    else
      message = format_top_coins_message(signals)
      {:ok, message}
    end
  end

  @doc """
  Sends a message to a user via Telegram.

  Looks up the user's linked Telegram chat_id and sends the message.
  Returns the actual result of the send operation.

  ## Options

    * `:kind` - atom labelling the notification type for log filtering
      (e.g. `:position_threshold`, `:watchlist_entered`). Defaults to
      `:unknown` so legacy 2-arg callers keep working.

  Every call computes a deterministic `fingerprint` from `(user_id, message)`
  plus a fresh `dispatch_id` UUID. Both are emitted as structured log
  metadata before and after the wire send so duplicates remain diagnosable
  from server logs without leaking debug data into the user-visible
  Telegram message.

  Cluster-wide deduplication is enforced via `DispatchClaim.claim/4` before
  the wire send: only the first node to insert a `(user_id, fingerprint,
  window_bucket)` row in Postgres actually sends; subsequent claims return
  `{:ok, :suppressed}`. On DB error the call fails open (sends anyway) so a
  Postgres hiccup never silences a real alert.

  Returns:
  - `:ok` - User has no Telegram linked (not an error)
  - `{:ok, :sent}` - Message sent successfully
  - `{:ok, :suppressed}` - Cluster-wide duplicate, suppressed by `DispatchClaim`
  - `{:error, reason}` - Message send failed

  Logs errors but doesn't crash if sending fails.

  ## Examples

      iex> TelegramService.send_message(123, "Alert: Position closed", kind: :position_closure)
      {:ok, :sent}

      iex> TelegramService.send_message(456, "Invalid message")
      {:error, "Telegram API error"}

      iex> TelegramService.send_message(789, "Message")
      :ok  # User has no Telegram linked

  """
  def send_message(user_id, message, opts \\ [])
      when is_integer(user_id) and is_binary(message) and is_list(opts) do
    fingerprint = compute_fingerprint(user_id, message)
    dispatch_id = generate_dispatch_id()
    kind = Keyword.get(opts, :kind, :unknown)

    DuplicateDetector.observe(user_id, fingerprint, dispatch_id, kind)

    Log.info("telegram dispatch",
      module: :telegram,
      operation: :send_message,
      user_id: user_id,
      fingerprint: fingerprint,
      dispatch_id: dispatch_id,
      notification_kind: kind
    )

    result =
      case DispatchClaim.claim(user_id, fingerprint, dispatch_id, kind) do
        :duplicate ->
          Log.warn(
            "telegram dispatch suppressed (cluster-wide duplicate)",
            :telegram_error,
            module: :telegram,
            operation: :send_message,
            user_id: user_id,
            fingerprint: fingerprint,
            dispatch_id: dispatch_id,
            notification_kind: kind
          )

          {:ok, :suppressed}

        :ok ->
          do_send(user_id, message, fingerprint, dispatch_id, kind)

        {:error, reason} ->
          # Fail open: a DB hiccup must not silence real alerts.
          Log.telegram_error("dispatch claim failed; sending anyway",
            module: :telegram,
            operation: :send_message,
            user_id: user_id,
            fingerprint: fingerprint,
            dispatch_id: dispatch_id,
            notification_kind: kind,
            reason: inspect(reason)
          )

          do_send(user_id, message, fingerprint, dispatch_id, kind)
      end

    Log.info("telegram dispatch result",
      module: :telegram,
      operation: :send_message,
      user_id: user_id,
      fingerprint: fingerprint,
      dispatch_id: dispatch_id,
      notification_kind: kind,
      result: result_tag(result)
    )

    result
  end

  defp do_send(user_id, message, fingerprint, dispatch_id, kind) do
    case Accounts.get_telegram_chat_id(user_id) do
      nil ->
        # User hasn't linked Telegram yet - skip silently
        :ok

      chat_id ->
        case ExGram.send_message(chat_id, message, bot: @bot) do
          {:ok, _response} ->
            {:ok, :sent}

          {:error, reason} ->
            Log.telegram_error("Failed to send Telegram message",
              module: :telegram,
              operation: :send_message,
              user_id: user_id,
              fingerprint: fingerprint,
              dispatch_id: dispatch_id,
              notification_kind: kind,
              reason: inspect(reason)
            )

            {:error, reason}
        end
    end
  end

  defp result_tag(:ok), do: :no_chat
  defp result_tag({:ok, :sent}), do: :sent
  defp result_tag({:ok, :suppressed}), do: :suppressed
  defp result_tag({:error, _}), do: :error

  defp compute_fingerprint(user_id, message) do
    :crypto.hash(:sha256, "#{user_id}|#{message}")
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp generate_dispatch_id do
    Ecto.UUID.generate() |> binary_part(0, 8)
  end

  @doc """
  Broadcasts a message to a list of users by their IDs.

  Sends the given message to all provided user IDs and returns the count of
  successful deliveries. Users without Telegram linked are silently skipped.

  ## Options

    * `:kind` - atom labelling the notification type, propagated to each
      underlying `send_message/3` call. See `send_message/3`.

  ## Examples

      iex> TelegramService.broadcast_message([1, 2, 3], "Hello!", kind: :market_status)
      {:ok, 2}  # 2 messages sent successfully

  """
  def broadcast_message(user_ids, message, opts \\ [])
      when is_list(user_ids) and is_binary(message) and is_list(opts) do
    results = Enum.map(user_ids, &send_message(&1, message, opts))

    success_count = Enum.count(results, &match?({:ok, :sent}, &1))

    Log.info("Broadcast complete: #{success_count}/#{length(user_ids)} messages sent",
      module: :telegram,
      operation: :broadcast_message,
      notification_kind: Keyword.get(opts, :kind, :unknown)
    )

    {:ok, success_count}
  end

  defp bot_username do
    Application.get_env(:coin_tracker, :telegram_bot_username)
  end

  defp format_positions_message(positions) do
    # Filter out positions with nil symbol_price to prevent crashes
    valid_positions = Enum.filter(positions, &(&1.symbol_price != nil))

    # Sort by gains descending (highest gains first)
    # Use {:desc, Decimal} to properly compare Decimal values numerically
    sorted_positions = Enum.sort_by(valid_positions, &position_gain_percent/1, {:desc, Decimal})

    position_lines =
      sorted_positions
      |> Enum.with_index(1)
      |> Enum.map(fn {position, index} ->
        format_position_line(position, index)
      end)

    "📊 Your Active Positions:\n\n" <> Enum.join(position_lines, "\n\n")
  end

  defp format_position_line(%{symbol_price: symbol_price} = position, index)
       when not is_nil(symbol_price) do
    symbol = symbol_price.symbol_pair
    entry = format_price(position.entry_price)
    current = format_price(symbol_price.current_price)
    change = calculate_change_percent(position.entry_price, symbol_price.current_price)
    status_indicator = position_status_indicator(position.entry_price, symbol_price.current_price)
    sl = format_decimal(position.stop_loss_percent)
    tp = format_decimal(position.take_profit_percent)

    "#{index}. #{status_indicator} #{symbol}\n" <>
      "   Entry: $#{entry}\n" <>
      "   Current: $#{current} (#{change}%)\n" <>
      "   SL: #{sl}% | TP: #{tp}%"
  end

  defp format_price(decimal) do
    decimal
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp format_decimal(decimal) do
    decimal
    |> Decimal.round(1)
    |> Decimal.to_string()
  end

  defp calculate_change_percent(entry_price, current_price) do
    change = Decimal.sub(current_price, entry_price)
    percent = Decimal.mult(Decimal.div(change, entry_price), Decimal.new(100))

    percent
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp position_gain_percent(%{
         entry_price: entry_price,
         symbol_price: %{current_price: current_price}
       }) do
    change = Decimal.sub(current_price, entry_price)
    Decimal.mult(Decimal.div(change, entry_price), Decimal.new(100))
  end

  defp position_status_indicator(entry_price, current_price) do
    case Decimal.compare(current_price, entry_price) do
      :gt -> "🟢"
      :lt -> "🔴"
      :eq -> "⚪️"
    end
  end

  defp format_top_coins_message(signals) do
    coin_lines =
      signals
      |> Enum.map(fn signal ->
        duration = format_duration_since(signal.in_top_since)
        "#{signal.position} - #{signal.symbol} - entered top #{duration} ago"
      end)
      |> Enum.join("\n")

    "🏆 Top 10 Coins\n\n#{coin_lines}"
  end

  defp format_duration_since(nil), do: "N/A"

  defp format_duration_since(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 ->
        "#{diff_seconds}s"

      diff_seconds < 3600 ->
        minutes = div(diff_seconds, 60)
        "#{minutes}m"

      diff_seconds < 86400 ->
        hours = div(diff_seconds, 3600)
        minutes = div(rem(diff_seconds, 3600), 60)

        if minutes > 0 do
          "#{hours}h #{minutes}m"
        else
          "#{hours}h"
        end

      true ->
        days = div(diff_seconds, 86400)
        hours = div(rem(diff_seconds, 86400), 3600)

        if hours > 0 do
          "#{days}d #{hours}h"
        else
          "#{days}d"
        end
    end
  end
end
