defmodule CoinTracker.Trading.AlertZone do
  @moduledoc """
  Pure functions for calculating position profitability and closure conditions.

  This module handles:
  - Calculating current profit/loss percentage
  - Determining take profit and stop loss thresholds
  - Detecting position closure conditions (take profit, stop loss)
  """

  @doc """
  Calculates the current profit/loss percentage for a position.

  ## Parameters
    - entry_price: The price at which the position was entered (Decimal)
    - current_price: The current market price (Decimal)

  ## Returns
    Decimal representing the percentage change (positive for profit, negative for loss)

  ## Examples

      iex> AlertZone.calculate_current_pnl(Decimal.new("100"), Decimal.new("110"))
      Decimal.new("10.00")

      iex> AlertZone.calculate_current_pnl(Decimal.new("100"), Decimal.new("95"))
      Decimal.new("-5.00")
  """
  def calculate_current_pnl(entry_price, current_price) do
    # ((current_price - entry_price) / entry_price) * 100
    current_price
    |> Decimal.sub(entry_price)
    |> Decimal.div(entry_price)
    |> Decimal.mult(100)
  end

  @doc """
  Determines all possible alert zones for a position based on its configuration.

  Alert zones include:
  - Positive zones: threshold increments (e.g., 5%, 10%, 15%, 20%)
  - Negative zones: 90% and 95% of stop loss distance
  - Take profit zone (final positive zone)
  - Stop loss zone (final negative zone)

  ## Parameters
    - threshold_zone: The increment for positive zones (e.g., 5 means alert every 5%)
    - take_profit_percent: The take profit percentage (e.g., 25)
    - stop_loss_percent: The stop loss percentage (e.g., -25)

  ## Returns
    Map with:
      - :positive_zones - List of positive threshold percentages
      - :negative_zones - List of negative warning percentages
      - :take_profit - Take profit percentage
      - :stop_loss - Stop loss percentage

  ## Examples

      iex> AlertZone.determine_alert_zones(5, Decimal.new("25"), Decimal.new("-25"))
      %{
        positive_zones: [Decimal.new("5"), Decimal.new("10"), Decimal.new("15"), Decimal.new("20")],
        negative_zones: [Decimal.new("-22.5"), Decimal.new("-23.75")],
        take_profit: Decimal.new("25"),
        stop_loss: Decimal.new("-25")
      }
  """
  def determine_alert_zones(threshold_zone, take_profit_percent, stop_loss_percent) do
    # Convert to Decimal if needed
    threshold = to_decimal(threshold_zone)
    take_profit = to_decimal(take_profit_percent)
    stop_loss = to_decimal(stop_loss_percent)

    # Generate positive zones (threshold increments up to but not including take profit)
    positive_zones = generate_positive_zones(threshold, take_profit)

    # Generate negative zones (90% and 95% of the way to stop loss)
    negative_zones = generate_negative_zones(stop_loss)

    %{
      positive_zones: positive_zones,
      negative_zones: negative_zones,
      take_profit: take_profit,
      stop_loss: stop_loss
    }
  end

  @doc """
  Determines if a position should be closed based on current PnL.

  ## Parameters
    - current_pnl: Current profit/loss percentage (Decimal)
    - alert_zones: Map from determine_alert_zones/3

  ## Returns
    `{:close, reason}` where reason is :take_profit or :stop_loss, or `:no_close`

  ## Examples

      iex> zones = AlertZone.determine_alert_zones(5, Decimal.new("25"), Decimal.new("-25"))
      iex> AlertZone.should_close_position?(Decimal.new("26"), zones)
      {:close, :take_profit}

      iex> AlertZone.should_close_position?(Decimal.new("20"), zones)
      :no_close
  """
  def should_close_position?(current_pnl, alert_zones) do
    current = to_decimal(current_pnl)

    cond do
      Decimal.compare(current, alert_zones.take_profit) in [:eq, :gt] ->
        {:close, :take_profit}

      Decimal.compare(current, alert_zones.stop_loss) in [:eq, :lt] ->
        {:close, :stop_loss}

      true ->
        :no_close
    end
  end

  # Private functions

  defp generate_positive_zones(threshold, take_profit) do
    # Start at threshold and increment until we reach take_profit
    Stream.iterate(threshold, &Decimal.add(&1, threshold))
    |> Enum.take_while(&(Decimal.compare(&1, take_profit) == :lt))
  end

  defp generate_negative_zones(stop_loss) do
    # 90% of the way to stop loss
    ninety_percent = Decimal.mult(stop_loss, Decimal.new("0.90"))

    # 95% of the way to stop loss
    ninety_five_percent = Decimal.mult(stop_loss, Decimal.new("0.95"))

    [ninety_percent, ninety_five_percent]
  end

  defp to_decimal(%Decimal{} = decimal), do: decimal
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)
end
