defmodule CoinTracker.Repo do
  use Ecto.Repo,
    otp_app: :coin_tracker,
    adapter: Ecto.Adapters.Postgres
end
