import Config

# Set environment to test for runtime checks
config :coin_tracker, :env, :test

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :coin_tracker, CoinTracker.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "coin_tracker_test#{System.get_env("MIX_TEST_PARTITION")}",
  port: 5433,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :coin_tracker, CoinTrackerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false

# In test we don't send emails
config :coin_tracker, CoinTracker.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Configure API client for deterministic test behavior
config :coin_tracker, CoinTracker.Signals.CoinscanApiClient,
  base_url: "http://localhost:4002",
  api_key: "test_api_key",
  # Disable retries in tests for fast, deterministic behavior
  retry: false,
  # Reduce timeout for faster test failures
  receive_timeout: 100

config :coin_tracker, CoinTracker.Signals.CoinGeckoApiClient,
  base_url: "http://localhost:4002",
  retry: false,
  receive_timeout: 100

# Disable automatic polling in tests
config :coin_tracker, CoinTracker.Signals.Poller, enabled: false
config :coin_tracker, CoinTracker.Signals.SnapshotPoller, enabled: false
config :coin_tracker, CoinTracker.Signals.MarketStatusPoller, enabled: false
config :coin_tracker, CoinTracker.Signals.CoinGeckoPoller, enabled: false
config :coin_tracker, CoinTracker.Coins.PricePoller, enabled: false
config :coin_tracker, CoinTracker.Signals.SignalPricePoller, enabled: false
config :coin_tracker, CoinTracker.Watchlist.AlertSubscriber, enabled: false

# Print only warnings and errors during test
config :logger, level: :alert

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
