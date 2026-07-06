defmodule CoinTracker.Log do
  @moduledoc """
  Structured logging helpers for consistent error categorization.

  All functions add metadata for Grafana/Loki querying. In production,
  logs are JSON-formatted via logger_json. In dev, metadata appears
  in the standard log format.

  ## Error Types
  - `:api_error` - External API failures (exchanges, Coinscan)
  - `:db_error` - Database operation failures
  - `:telegram_error` - Telegram message delivery failures
  - `:network_error` - Network/connection issues
  - `:validation_error` - Data validation failures
  - `:critical` - Critical failures requiring immediate attention

  ## Severity Levels
  - `:critical` - Position closures, money-related failures
  - `:high` - API errors, database errors
  - `:medium` - Network issues, warnings
  - `:low` - Validation errors, minor issues

  ## Example Usage

      CoinTracker.Log.api_error("Binance API error: rate limited",
        exchange: :binance,
        operation: :fetch_prices
      )

      CoinTracker.Log.critical("Failed to close position",
        position_id: position.id,
        user_id: position.user_id,
        reason: inspect(changeset.errors)
      )

  ## Grafana/Loki Queries

      # All critical errors
      {app="coin_tracker"} | json | severity="critical"

      # API errors by exchange
      {app="coin_tracker"} | json | error_type="api_error" | exchange="binance"
  """
  require Logger

  @allowed_metadata [
    :module,
    :operation,
    :exchange,
    :symbol,
    :position_id,
    :user_id,
    :reason,
    :token_prefix,
    :alert_type,
    :fingerprint,
    :dispatch_id,
    :notification_kind,
    :result
  ]

  # Error logging functions

  @doc """
  Logs an API error with high severity.
  Use for external API failures (exchanges, Coinscan, etc).
  """
  def api_error(message, opts \\ []) do
    Logger.error(message, build_meta(:api_error, :high, opts))
  end

  @doc """
  Logs a database error with high severity.
  Use for Ecto/database operation failures.
  """
  def db_error(message, opts \\ []) do
    Logger.error(message, build_meta(:db_error, :high, opts))
  end

  @doc """
  Logs a Telegram error with high severity.
  Use for message delivery failures.
  """
  def telegram_error(message, opts \\ []) do
    Logger.error(message, build_meta(:telegram_error, :high, opts))
  end

  @doc """
  Logs a network error with medium severity.
  Use for connection timeouts, DNS failures, etc.
  """
  def network_error(message, opts \\ []) do
    Logger.error(message, build_meta(:network_error, :medium, opts))
  end

  @doc """
  Logs a validation error with low severity.
  Use for data validation failures.
  """
  def validation_error(message, opts \\ []) do
    Logger.error(message, build_meta(:validation_error, :low, opts))
  end

  @doc """
  Logs a critical error requiring immediate attention.
  Use for position closures, money-related failures.
  """
  def critical(message, opts \\ []) do
    Logger.error(message, build_meta(:critical, :critical, opts))
  end

  # Warning logging

  @doc """
  Logs a warning with the specified error type.
  """
  def warn(message, error_type, opts \\ []) do
    Logger.warning(message, build_meta(error_type, :medium, opts))
  end

  # Info logging

  @doc """
  Logs an info message with optional context metadata.
  """
  def info(message, opts \\ []) do
    Logger.info(message, Keyword.take(opts, @allowed_metadata))
  end

  @doc """
  Logs a debug message with optional context metadata.
  """
  def debug(message, opts \\ []) do
    Logger.debug(message, Keyword.take(opts, @allowed_metadata))
  end

  # Private helpers

  defp build_meta(error_type, severity, opts) do
    base = [error_type: error_type, severity: severity]
    Keyword.merge(base, Keyword.take(opts, @allowed_metadata))
  end
end
