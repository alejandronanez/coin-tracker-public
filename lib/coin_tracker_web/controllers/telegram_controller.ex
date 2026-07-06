defmodule CoinTrackerWeb.TelegramController do
  use CoinTrackerWeb, :controller

  require Logger

  def webhook(conn, %{"token_hash" => token_hash} = params) do
    # Body is already parsed by Plug.Parsers - use params directly
    # Remove the token_hash from route params to get just the Telegram update
    update_params = Map.delete(params, "token_hash")

    # Debug: Check if the webhook process exists
    process_name = Module.concat(ExGram.Updates.Webhook, token_hash)
    process_exists = GenServer.whereis(process_name) != nil

    Logger.info("Telegram webhook received",
      token_hash: token_hash,
      process_name: inspect(process_name),
      process_exists: process_exists
    )

    # Convert string keys to atoms for ExGram.Cast
    update_map = atomize_keys(update_params)
    update = ExGram.Cast.cast(update_map, ExGram.Model.Update)

    Logger.info("Dispatching update to bot", update_id: update.update_id)
    ExGram.Updates.Webhook.update(update, token_hash)

    json(conn, %{ok: true})
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = if is_binary(k), do: String.to_existing_atom(k), else: k
      {key, atomize_keys(v)}
    end)
  rescue
    ArgumentError ->
      # If atom doesn't exist, use safe conversion for known Telegram fields
      Map.new(map, fn {k, v} ->
        key = if is_binary(k), do: String.to_atom(k), else: k
        {key, atomize_keys(v)}
      end)
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value
end
