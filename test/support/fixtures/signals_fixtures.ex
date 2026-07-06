defmodule CoinTracker.SignalsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `CoinTracker.Signals` context.
  """

  alias CoinTracker.Signals.{
    Signal,
    SignalSnapshot,
    MarketStatus
  }

  alias CoinTracker.Repo

  def unique_symbol, do: "SYM#{System.unique_integer([:positive])}"

  def valid_signal_attributes(attrs \\ %{}) do
    in_top_since = Map.get(attrs, :in_top_since, DateTime.utc_now() |> DateTime.truncate(:second))

    Enum.into(attrs, %{
      symbol: unique_symbol(),
      name: "Test Coin",
      initial_volume_24h: Decimal.new("1000000"),
      current_volume_24h: Decimal.new("1500000"),
      initial_price_usd: Decimal.new("1.00"),
      current_price_usd: Decimal.new("1.50"),
      max_price_usd: Decimal.new("1.50"),
      max_increase_percentage: Decimal.new("50.00"),
      in_top: false,
      active: true,
      in_top_since: in_top_since,
      position: nil
    })
  end

  def signal_fixture(attrs \\ %{}) do
    attrs
    |> valid_signal_attributes()
    |> then(&Signal.changeset(%Signal{}, &1))
    |> Repo.insert!()
  end

  def valid_snapshot_attributes(signal, attrs \\ %{}) do
    Enum.into(attrs, %{
      signal_id: signal.id,
      snapshot_at: DateTime.utc_now() |> DateTime.truncate(:second),
      symbol: signal.symbol,
      current_volume_24h: signal.current_volume_24h,
      initial_volume_24h: signal.initial_volume_24h,
      max_price_usd: signal.max_price_usd,
      current_price_usd: signal.current_price_usd,
      in_top: signal.in_top,
      position: signal.position
    })
  end

  def snapshot_fixture(signal, attrs \\ %{}) do
    signal
    |> valid_snapshot_attributes(attrs)
    |> then(&SignalSnapshot.changeset(%SignalSnapshot{}, &1))
    |> Repo.insert!()
  end

  def signal_with_snapshots_fixture(snapshot_count \\ 3, signal_attrs \\ %{}) do
    signal = signal_fixture(signal_attrs)

    snapshots =
      for i <- 1..snapshot_count do
        # Create snapshots at different times
        snapshot_at =
          DateTime.add(DateTime.utc_now(), -i * 60, :second) |> DateTime.truncate(:second)

        snapshot_fixture(signal, %{snapshot_at: snapshot_at})
      end

    {signal, snapshots}
  end

  @doc """
  Creates a market status record for testing.

  ## Attributes

    * `:active_signals_count` - integer 0-10 (default: random)
    * `:recorded_at` - UTC datetime (default: now truncated to seconds)

  ## Examples

      market_status_fixture()
      market_status_fixture(%{active_signals_count: 5})
      market_status_fixture(%{recorded_at: ~U[2025-11-24 10:00:00Z]})
  """
  def market_status_fixture(attrs \\ %{}) do
    {:ok, market_status} =
      attrs
      |> Enum.into(%{
        active_signals_count: Enum.random(0..10),
        recorded_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> then(&MarketStatus.changeset(%MarketStatus{}, &1))
      |> Repo.insert()

    market_status
  end
end
