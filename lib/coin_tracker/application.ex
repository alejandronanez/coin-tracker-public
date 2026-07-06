defmodule CoinTracker.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    # Configure Telegram bot: webhook in production, polling in development
    use_webhook = Application.get_env(:coin_tracker, :telegram_use_webhook, false)

    bot_config = [
      token: Application.get_env(:ex_gram, :token),
      name: CoinTracker.TelegramClient.Telegram,
      method: if(use_webhook, do: :webhook, else: :polling)
    ]

    # Check runtime configuration for pollers
    enable_signal_poller =
      Application.get_env(:coin_tracker, :enable_signal_poller, true)

    enable_price_poller =
      Application.get_env(:coin_tracker, :enable_price_poller, true)

    enable_snapshot_poller =
      Application.get_env(:coin_tracker, :enable_snapshot_poller, true)

    enable_market_status_poller =
      Application.get_env(:coin_tracker, :enable_market_status_poller, true)

    enable_signal_price_poller =
      Application.get_env(:coin_tracker, :enable_signal_price_poller, true)

    enable_coin_gecko_poller =
      Application.get_env(:coin_tracker, CoinTracker.Signals.CoinGeckoPoller, [])
      |> Keyword.get(:enabled, true)

    enable_watchlist_alerts =
      Application.get_env(:coin_tracker, CoinTracker.Watchlist.AlertSubscriber, [])
      |> Keyword.get(:enabled, true)

    children =
      [
        CoinTrackerWeb.Telemetry,
        CoinTracker.Repo,
        {DNSCluster, query: Application.get_env(:coin_tracker, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: CoinTracker.PubSub},
        CoinTracker.Vault,
        {Task.Supervisor, name: CoinTracker.TaskSupervisor},
        # Telegram duplicate-notification detector (must start before any poller
        # that might call TelegramService.send_message/3)
        CoinTracker.TelegramClient.DuplicateDetector,
        # Sweeps expired rows from the cluster-wide dispatch-claim table that
        # backs duplicate suppression in TelegramService.send_message/3.
        CoinTracker.TelegramClient.DispatchClaimSweeper,
        # Start the Snapshot poller first so it subscribes to Poller's status
        # topic before Poller's first poll can broadcast a fingerprint change.
        if(enable_snapshot_poller, do: CoinTracker.Signals.SnapshotPoller, else: nil),
        # Start the Signals poller for automatic API ingestion
        if(enable_signal_poller, do: CoinTracker.Signals.Poller, else: nil),
        # Start the Market Status poller for automatic market health tracking
        if(enable_market_status_poller, do: CoinTracker.Signals.MarketStatusPoller, else: nil),
        # Start the Price poller for automatic price updates
        if(enable_price_poller, do: CoinTracker.Coins.PricePoller, else: nil),
        # Start the Signal Price poller for automatic signal price updates
        if(enable_signal_price_poller, do: CoinTracker.Signals.SignalPricePoller, else: nil),
        # Start the CoinGecko poller for top-500 market data ingestion (15-min timer)
        if(enable_coin_gecko_poller, do: CoinTracker.Signals.CoinGeckoPoller, else: nil),
        # Start the Watchlist alert subscriber to fan out top-10 transition alerts
        if(enable_watchlist_alerts, do: CoinTracker.Watchlist.AlertSubscriber, else: nil),
        # Start a worker by calling: CoinTracker.Worker.start_link(arg)
        # {CoinTracker.Worker, arg},
        # Start to serve requests, typically the last entry
        CoinTrackerWeb.Endpoint,
        # Telegram ExGram configuration
        ExGram,
        {
          CoinTracker.TelegramClient.Telegram,
          bot_config
        }
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CoinTracker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CoinTrackerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
