# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :backpex,
  pubsub_server: CoinTracker.PubSub,
  translator_function: {CoinTrackerWeb.Gettext, :gettext}

config :coin_tracker, :scopes,
  user: [
    default: true,
    module: CoinTracker.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: CoinTracker.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :coin_tracker,
  ecto_repos: [CoinTracker.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :coin_tracker, CoinTrackerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CoinTrackerWeb.ErrorHTML, json: CoinTrackerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CoinTracker.PubSub

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :coin_tracker, CoinTracker.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  coin_tracker: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  coin_tracker: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :error_type,
    :severity,
    :module,
    :operation,
    :exchange,
    :symbol,
    :position_id,
    :user_id,
    :reason,
    :token_prefix,
    :alert_type
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Telegram ExGram
config :ex_gram, token: System.get_env("TELEGRAM_BOT_TOKEN")

# Cluster-wide Telegram dispatch deduplication window. Comfortably larger than
# all poller cadences so two clustered nodes that race on the same alert within
# a poll interval are guaranteed to fall in the same `window_bucket`.
config :coin_tracker, CoinTracker.TelegramClient.DispatchClaim, window_seconds: 300

# Suppress Tesla deprecation warning (ex_gram uses deprecated :log_level option)
config :tesla, disable_log_level_warning: true

# Cloak Vault configuration
# The encryption key is derived at runtime from SECRET_KEY_BASE (see runtime.exs and test.exs)
config :coin_tracker, CoinTracker.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: "placeholder_replaced_at_runtime"}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
