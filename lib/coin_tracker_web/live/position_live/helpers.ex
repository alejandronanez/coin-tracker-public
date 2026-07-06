defmodule CoinTrackerWeb.PositionLive.Helpers do
  @moduledoc """
  Shared helper functions for Position LiveViews.
  """

  @decimal_fields ~w(entry_price stop_loss_percent take_profit_percent amount_invested current_threshold_zone)

  @doc """
  Normalizes decimal inputs in position params by converting commas to periods.
  This handles locales where comma is used as decimal separator (e.g., European locales).
  """
  def normalize_decimal_params(params) do
    Enum.reduce(@decimal_fields, params, fn field, acc ->
      case Map.get(acc, field) do
        value when is_binary(value) and value != "" ->
          Map.put(acc, field, String.replace(value, ",", "."))

        _ ->
          acc
      end
    end)
  end

  @doc """
  Formats a Decimal price with comma separators and removes trailing zeroes.
  Returns "0" for nil input.
  """
  def format_price(nil), do: "0"

  def format_price(price) do
    price
    |> Decimal.to_string(:normal)
    |> remove_trailing_zeroes()
    |> format_with_commas()
  end

  @doc """
  Calculates stop loss and take profit prices from a changeset.
  Returns nil if any required field is missing or nil.

  When `amount_invested` is present, also returns projected PnL in dollars
  for each threshold. When absent, the `*_pnl` keys are nil and callers
  should fall back to rendering just the percent.
  """
  def calculate_preview_prices(changeset) do
    import Ecto.Changeset, only: [get_field: 2]

    entry_price = changeset |> get_field(:entry_price) |> to_decimal()
    stop_loss_percent = changeset |> get_field(:stop_loss_percent) |> to_decimal()
    take_profit_percent = changeset |> get_field(:take_profit_percent) |> to_decimal()
    amount_invested = changeset |> get_field(:amount_invested) |> to_decimal()

    if entry_price && stop_loss_percent && take_profit_percent do
      stop_loss_price = apply_percent_to_price(entry_price, stop_loss_percent)
      take_profit_price = apply_percent_to_price(entry_price, take_profit_percent)

      %{
        stop_loss: stop_loss_price,
        take_profit: take_profit_price,
        stop_loss_percent: stop_loss_percent,
        take_profit_percent: take_profit_percent,
        stop_loss_pnl: pnl_amount(amount_invested, stop_loss_percent),
        take_profit_pnl: pnl_amount(amount_invested, take_profit_percent)
      }
    else
      nil
    end
  end

  @doc """
  Formats a projected PnL Decimal amount as a signed dollar string, e.g.
  `+$25.00`, `-$60.00`. Rounds to 2 decimals (half-up).
  """
  def format_pnl(%Decimal{} = amount) do
    rounded = Decimal.round(amount, 2, :half_up)
    prefix = if Decimal.negative?(rounded), do: "-$", else: "+$"

    formatted =
      rounded
      |> Decimal.abs()
      |> pad_two_decimals()
      |> format_with_commas()

    prefix <> formatted
  end

  @doc """
  Formats a PnL percent Decimal as a signed percent string, e.g.
  `+25%`, `-6%`, `+0.5%`. Trailing zeros after the decimal are stripped.
  """
  def format_pnl_percent(%Decimal{} = percent) do
    sign = if Decimal.negative?(percent), do: "", else: "+"

    body =
      percent
      |> Decimal.to_string(:normal)
      |> remove_trailing_zeroes()

    sign <> body <> "%"
  end

  # Edit flow stuffs string-formatted values back into the Position struct
  # before building the changeset, so get_field can return strings rather
  # than Decimals. Coerce so downstream helpers stay strict.
  defp to_decimal(nil), do: nil
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)

  defp to_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp apply_percent_to_price(price, percent) do
    multiplier =
      Decimal.new(100)
      |> Decimal.add(percent)
      |> Decimal.div(100)

    Decimal.mult(price, multiplier)
  end

  defp pnl_amount(nil, _percent), do: nil

  defp pnl_amount(%Decimal{} = amount_invested, %Decimal{} = percent) do
    amount_invested
    |> Decimal.mult(percent)
    |> Decimal.div(100)
  end

  defp pad_two_decimals(%Decimal{} = dec) do
    case dec |> Decimal.to_string(:normal) |> String.split(".") do
      [int_part] -> int_part <> ".00"
      [int_part, dec_part] -> int_part <> "." <> String.pad_trailing(dec_part, 2, "0")
    end
  end

  # Removes trailing zeroes from a numeric string, including the decimal point if no decimals remain.
  # Only removes trailing zeros after a decimal point, preserving significant zeros in the integer part.
  defp remove_trailing_zeroes(str) do
    if String.contains?(str, ".") do
      str
      |> String.replace(~r/0+$/, "")
      |> String.replace(~r/\.$/, "")
    else
      str
    end
  end

  # Adds thousand separators to a numeric string.
  # Handles both decimal and whole number inputs.
  defp format_with_commas(str) do
    case String.split(str, ".") do
      [integer_part, decimal_part] ->
        formatted_integer = add_commas_to_integer(integer_part)
        "#{formatted_integer}.#{decimal_part}"

      [integer_part] ->
        add_commas_to_integer(integer_part)
    end
  end

  defp add_commas_to_integer(integer_str) do
    integer_str
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
  end
end
