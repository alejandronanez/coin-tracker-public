Mox.defmock(CoinTracker.Coins.HTTPClientMock, for: CoinTracker.Coins.HTTPClient)
Mox.defmock(CoinTracker.Signals.HTTPClientMock, for: CoinTracker.Signals.HTTPClient)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(CoinTracker.Repo, :manual)
