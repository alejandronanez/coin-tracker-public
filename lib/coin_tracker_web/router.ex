defmodule CoinTrackerWeb.Router do
  use CoinTrackerWeb, :router

  import Backpex.Router
  import CoinTrackerWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CoinTrackerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug CoinTrackerWeb.Plugs.LocalePlug
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/admin", CoinTrackerWeb do
    pipe_through [:browser]

    live_session :admin,
      on_mount: [
        {CoinTrackerWeb.UserAuth, :require_authenticated},
        {CoinTrackerWeb.UserAuth, :require_admin_subscription},
        {CoinTrackerWeb.UserAuth, :set_locale},
        Backpex.InitAssigns
      ] do
      live "/", AdminLive.Dashboard, :index
      backpex_routes()
      live_resources "/positions", BackpexResources.PositionResource
      live_resources "/signals", BackpexResources.SignalResource
      live_resources "/users", BackpexResources.UserResource
      live "/payments", AdminLive.PaymentsPlaceholder, :index
    end
  end

  scope "/", CoinTrackerWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Telegram webhook endpoint (unauthenticated - Telegram sends updates here)
  scope "/telegram", CoinTrackerWeb do
    pipe_through :api

    post "/:token_hash", TelegramController, :webhook
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:coin_tracker, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CoinTrackerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", CoinTrackerWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {CoinTrackerWeb.UserAuth, :require_authenticated},
        {CoinTrackerWeb.UserAuth, :set_locale}
      ] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      live "/positions", PositionLive.Index, :index
      live "/positions/closed", PositionLive.Closed, :index
      live "/positions/new", PositionLive.New, :new
      live "/positions/:id/edit", PositionLive.Edit, :edit

      live "/tutorial", TutorialLive, :index

      live "/settings/exchange-keys", SettingsLive.ExchangeKeys, :index
    end

    live_session :require_pro_subscription,
      on_mount: [
        {CoinTrackerWeb.UserAuth, :require_authenticated},
        {CoinTrackerWeb.UserAuth, :require_pro_subscription},
        {CoinTrackerWeb.UserAuth, :set_locale}
      ] do
      live "/signals", SignalLive.Index, :index
      live "/signals/:id", SignalLive.Show, :show
      live "/signals/:id/trade", SignalLive.Trade, :trade
      live "/market-status", MarketStatusLive.Index, :index
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", CoinTrackerWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [
        {CoinTrackerWeb.UserAuth, :mount_current_scope},
        {CoinTrackerWeb.UserAuth, :set_locale}
      ] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
      live "/upgrade", UpgradeLive.Index, :index
      live "/historical", HistoricalLive.Index, :index
      live "/historical/:symbol", HistoricalLive.Show, :show
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
