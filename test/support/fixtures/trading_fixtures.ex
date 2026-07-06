defmodule CoinTracker.TradingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `CoinTracker.Trading` context.
  """

  alias CoinTracker.Trading
  alias CoinTracker.Coins
  alias CoinTracker.Repo

  @doc """
  Generate a position with associated symbol_price.

  This fixture creates both the symbol_price record and the position,
  mimicking what happens in production when Trading.create_position/3 is called,
  but without making external API calls.

  ## Examples

      position_fixture(user_id: 1)
      position_fixture(user_id: 1, symbol: "BTC", exchange: "binance_spot")
      position_fixture(user_id: 1, status: :closed)

  """
  def position_fixture(attrs \\ %{}) do
    # Extract user_id first (required parameter)
    user_id = attrs[:user_id] || raise "user_id is required for position_fixture"

    # Default values
    defaults = %{
      symbol: "ETH",
      exchange: "binance_spot",
      entry_price: "2000.00",
      stop_loss_percent: "-10.0",
      take_profit_percent: "20.0",
      current_threshold_zone: "5",
      status: :active
    }

    attrs = Enum.into(attrs, defaults)

    # First, create or get the symbol_price
    symbol_pair = "#{attrs.symbol}/USDT"

    # Convert exchange to atom if it's a string
    exchange_atom =
      case attrs.exchange do
        atom when is_atom(atom) -> atom
        string when is_binary(string) -> String.to_atom(string)
      end

    {:ok, symbol_price} =
      Coins.upsert_symbol_price(%{
        exchange: exchange_atom,
        symbol_pair: symbol_pair,
        # Use entry_price as initial current_price or default to 3000
        current_price: attrs[:current_price] || "3000.00"
      })

    # Build changeset attrs (only fields accepted by changeset)
    changeset_attrs = %{
      entry_price: attrs[:entry_price],
      stop_loss_percent: attrs[:stop_loss_percent],
      take_profit_percent: attrs[:take_profit_percent],
      current_threshold_zone: attrs[:current_threshold_zone]
    }

    # Create the changeset and add programmatic fields
    changeset =
      %Trading.Position{}
      |> Trading.Position.changeset(changeset_attrs)
      |> Ecto.Changeset.cast(changeset_attrs, [:current_threshold_zone])
      |> Ecto.Changeset.put_change(:user_id, user_id)
      |> Ecto.Changeset.put_change(:symbol_price_id, symbol_price.id)
      |> Ecto.Changeset.put_change(:status, attrs[:status])

    # Add optional highest_alert_zone_reached if provided
    changeset =
      if attrs[:highest_alert_zone_reached] do
        Ecto.Changeset.put_change(
          changeset,
          :highest_alert_zone_reached,
          attrs[:highest_alert_zone_reached]
        )
      else
        changeset
      end

    # Add optional last_known_pnl if provided
    changeset =
      if attrs[:last_known_pnl] do
        Ecto.Changeset.put_change(
          changeset,
          :last_known_pnl,
          attrs[:last_known_pnl]
        )
      else
        changeset
      end

    # Add optional amount_invested if provided
    changeset =
      if attrs[:amount_invested] do
        Ecto.Changeset.put_change(
          changeset,
          :amount_invested,
          attrs[:amount_invested]
        )
      else
        changeset
      end

    # Add optional entry_rank if provided (1-10 or nil)
    changeset =
      case Map.fetch(attrs, :entry_rank) do
        {:ok, nil} -> changeset
        {:ok, rank} -> Ecto.Changeset.put_change(changeset, :entry_rank, rank)
        :error -> changeset
      end

    # Handle closed positions
    changeset =
      case attrs[:status] do
        :closed ->
          changeset
          |> Ecto.Changeset.put_change(
            :closed_at,
            DateTime.utc_now() |> DateTime.truncate(:second)
          )
          |> Ecto.Changeset.put_change(:closed_reason, attrs[:closed_reason] || "manual_close")

        _ ->
          changeset
      end

    {:ok, position} = Repo.insert(changeset)

    # Preload the symbol_price association
    Repo.preload(position, :symbol_price)
  end
end
