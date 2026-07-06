defmodule CoinTracker.DevLogFilter do
  @moduledoc """
  Logger filter for suppressing noisy Ecto SQL debug logs in development.

  Installed via `config/dev.exs`. Only active in dev — compiled but not
  installed in prod/test.

  ## Runtime toggle (in IEx)

      # Stop filtering (see SQL queries again)
      Logger.remove_handler_filter(:default, :suppress_ecto_debug)

      # Re-enable the filter
      :logger.update_handler_config(:default, :filters, [
        suppress_ecto_debug: {&CoinTracker.DevLogFilter.filter/2, :suppress_ecto_debug}
      ])
  """

  def filter(%{meta: %{domain: [:elixir, :ecto_sql]}, level: :debug}, :suppress_ecto_debug),
    do: :stop

  def filter(_log_event, :suppress_ecto_debug),
    do: :ignore
end
