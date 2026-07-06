import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/coin_tracker start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :coin_tracker, CoinTrackerWeb.Endpoint, server: true
end

# ---------------------------------------------------------------------------
# Identity & secrets required in EVERY environment (dev, test, prod).
#
# There are deliberately NO in-repo defaults: a missing value raises at boot
# rather than silently shipping a placeholder. See `.env.example` for the full
# list and copy it to `.env` for local development (`set -a; source .env; set +a`).
# ---------------------------------------------------------------------------

secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    raise """
    environment variable SECRET_KEY_BASE is missing.
    Generate one with: mix phx.gen.secret
    """

signing_salt =
  System.get_env("LIVE_VIEW_SIGNING_SALT") ||
    raise """
    environment variable LIVE_VIEW_SIGNING_SALT is missing.
    Generate one with: mix phx.gen.secret 32
    """

config :coin_tracker, CoinTrackerWeb.Endpoint,
  secret_key_base: secret_key_base,
  live_view: [signing_salt: signing_salt]

# Cloak Vault — derive a 32-byte AES-GCM key from SECRET_KEY_BASE.
config :coin_tracker, CoinTracker.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: :crypto.hash(:sha256, secret_key_base)}
  ]

# Public deployment identity — no brand/PII hard-coded in the source tree.
config :coin_tracker,
  app_name: System.fetch_env!("APP_NAME"),
  sender_email: System.fetch_env!("SENDER_EMAIL"),
  support_email: System.fetch_env!("SUPPORT_EMAIL"),
  admin_notification_email: System.fetch_env!("ADMIN_NOTIFICATION_EMAIL")

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :coin_tracker, CoinTracker.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "8080")
  fly_app = System.get_env("FLY_APP_NAME")

  config :coin_tracker, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Build list of allowed origins - include both custom domain and fly.dev domain
  allowed_origins =
    ["https://#{host}"] ++
      if fly_app, do: ["https://#{fly_app}.fly.dev"], else: []

  config :coin_tracker, CoinTrackerWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: allowed_origins,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :coin_tracker, CoinTrackerWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :coin_tracker, CoinTrackerWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :coin_tracker, CoinTracker.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.

  # ## API Client Configuration for CoinScanX
  #
  # TODO: Set this environment variable in your production environment:
  # - COINSCANX_API_KEY: Your CoinScanX API key
  config :coin_tracker, CoinTracker.Signals.CoinscanApiClient,
    base_url: "https://api.coinscanx.com",
    api_key: System.get_env("COINSCANX_API_KEY")

  config :ex_gram, token: System.get_env("TELEGRAM_BOT_TOKEN")
  config :coin_tracker, :telegram_bot_username, "coin_tracker_prod_bot"

  # Telegram webhook configuration for production
  # ExGram will automatically append /telegram/<token_hash> to this URL
  config :ex_gram, :webhook, url: "https://#{host}"

  # Flag to enable webhook mode (vs polling in dev)
  config :coin_tracker, :telegram_use_webhook, true

  # Resend mailer configuration
  resend_api_key =
    System.get_env("RESEND_API_KEY") ||
      raise """
      environment variable RESEND_API_KEY is missing.
      You can generate one at https://resend.com/api-keys
      """

  config :coin_tracker, CoinTracker.Mailer,
    adapter: Resend.Swoosh.Adapter,
    api_key: resend_api_key
end
