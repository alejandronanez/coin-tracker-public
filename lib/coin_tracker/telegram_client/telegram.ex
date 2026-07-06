defmodule CoinTracker.TelegramClient.Telegram do
  @bot :coin_tracker_bot
  use ExGram.Bot, name: @bot, setup_commands: true

  alias CoinTracker.Log
  alias CoinTracker.TelegramClient.TelegramService

  command("start")
  command("list")
  command("market")
  command("top")

  def handle({:command, :start, msg}, context) do
    chat_id = msg.chat.id
    text = String.trim(msg.text)

    if text == "" do
      answer(context, "Please provide a token: /start YOUR_TOKEN")
    else
      case TelegramService.register_chat(chat_id, text) do
        {:ok, response_text} ->
          answer(context, response_text)

        {:error, error_message} ->
          answer(context, "❌ #{error_message}")
      end
    end
  end

  def handle({:command, :list, msg}, context) do
    chat_id = msg.chat.id

    try do
      case TelegramService.list_positions(chat_id) do
        {:ok, positions_text} ->
          answer(context, positions_text)

        {:error, error_message} ->
          answer(context, "❌ #{error_message}")
      end
    rescue
      e ->
        Log.warn("Error listing positions", :telegram_error,
          module: :telegram,
          operation: :list_positions,
          error: Exception.format(:error, e, __STACKTRACE__)
        )

        answer(context, "❌ An error occurred while fetching your positions. Please try again.")
    end
  end

  def handle({:command, :market, msg}, context) do
    chat_id = msg.chat.id

    try do
      case TelegramService.get_market_status(chat_id) do
        {:ok, status_text} ->
          answer(context, status_text)

        {:error, error_message} ->
          answer(context, "❌ #{error_message}")
      end
    rescue
      e ->
        Log.warn("Error fetching market status", :telegram_error,
          module: :telegram,
          operation: :get_market_status,
          error: Exception.format(:error, e, __STACKTRACE__)
        )

        answer(context, "❌ An error occurred while fetching market status. Please try again.")
    end
  end

  def handle({:command, :top, _msg}, context) do
    try do
      {:ok, top_coins_text} = TelegramService.get_top_coins()
      answer(context, top_coins_text)
    rescue
      e ->
        Log.warn("Error fetching top coins", :telegram_error,
          module: :telegram,
          operation: :get_top_coins,
          error: Exception.format(:error, e, __STACKTRACE__)
        )

        answer(context, "❌ An error occurred while fetching top coins. Please try again.")
    end
  end

  def handle({:command, _any, _msg}, context) do
    answer(
      context,
      "❓ Unknown command. Try /list to see your positions, /market for market status, /top for top coins, or /start to link your account."
    )
  end

  def handle({:text, _text, _msg}, context) do
    answer(
      context,
      "❓ Text messages not supported. Try /list to see your positions, /market for market status, or /top for top coins."
    )
  end

  def handle(update, _context) do
    Log.warn("Unexpected Telegram update received", :telegram_error,
      module: :telegram,
      operation: :handle_update,
      reason: inspect(update)
    )

    :ok
  end
end
