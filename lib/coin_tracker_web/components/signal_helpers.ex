defmodule CoinTrackerWeb.SignalHelpers do
  @moduledoc """
  Shared formatting and display helpers for signal-related LiveViews.

  These functions are used by both `SignalLive.Show` and `HistoricalLive.Show`
  to render prices, durations, occurrence deltas, and position breakdowns.
  """

  use Phoenix.Component
  use Gettext, backend: CoinTrackerWeb.Gettext

  # --- Price formatting ---

  def format_price(nil), do: gettext("N/A")

  def format_price(%Decimal{} = price) do
    price |> Decimal.to_float() |> format_price_float()
  end

  def format_price(price) when is_float(price), do: format_price_float(price)
  def format_price(price) when is_integer(price), do: format_price_float(price / 1)

  defp format_price_float(price) when price < 0.0001 do
    "$#{format_decimals(price, 8)}"
  end

  defp format_price_float(price) when price < 0.01 do
    "$#{format_decimals(price, 6)}"
  end

  defp format_price_float(price) when price < 1 do
    "$#{format_decimals(price, 4)}"
  end

  defp format_price_float(price) do
    "$#{:erlang.float_to_binary(price, decimals: 2)}"
  end

  defp format_decimals(value, decimals) do
    :erlang.float_to_binary(value, decimals: decimals)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  # --- Price component (CoinMarketCap-style subscript-zero notation) ---

  @doc """
  Renders a USD price with subscript-zero notation for sub-`$0.0001` values.
  The container is `font-mono tabular-nums` so prices align across rows; extra
  classes from the caller are appended.

  Examples (logical render):

      <.price value={46.99} />        => $46.99
      <.price value={0.0537} />       => $0.0537
      <.price value={0.000374} />     => $0.0₃374
      <.price value={nil} />          => N/A
  """
  attr :value, :any, required: true, doc: "Decimal | float | integer | nil"
  attr :class, :string, default: nil

  def price(assigns) do
    assigns = assign(assigns, :parts, format_price_parts(assigns.value))

    ~H"""
    <span class={["font-mono tabular-nums", @class]}>
      <%= case @parts do %>
        <% {:simple, str} -> %>
          ${str}
        <% {:subscript, prefix, zero_count, sig} -> %>
          ${prefix}<sub class="text-[0.7em] mx-0.5">{zero_count}</sub>{sig}
        <% :na -> %>
          {gettext("N/A")}
      <% end %>
    </span>
    """
  end

  # Splits a price into renderable parts. Returns one of:
  #   :na                                — nil input
  #   {:simple, "46.99"}                 — render verbatim with a leading "$"
  #   {:subscript, "0.0", 3, "374"}      — render "$0.0" + <sub>3</sub> + "374"
  #
  # All numerics are normalised through Decimal first so that IEEE-754 noise
  # (e.g. `0.000374` actually being `0.000373999…`) never leaks into the
  # rendered digits.
  defp format_price_parts(nil), do: :na
  defp format_price_parts(v) when is_integer(v), do: v |> Decimal.new() |> format_price_parts()

  defp format_price_parts(v) when is_float(v) do
    v |> Float.to_string() |> Decimal.new() |> format_price_parts()
  end

  defp format_price_parts(%Decimal{} = d) do
    cond do
      Decimal.equal?(d, 0) -> {:simple, "0"}
      Decimal.negative?(d) -> simple_parts(d)
      Decimal.lt?(d, Decimal.new("0.001")) -> subscript_parts(d)
      true -> simple_parts(d)
    end
  end

  defp subscript_parts(d) do
    "0." <> rest = Decimal.to_string(d, :normal)

    zero_count =
      rest
      |> String.graphemes()
      |> Enum.take_while(&(&1 == "0"))
      |> length()

    sig_digits =
      rest
      |> String.slice(zero_count, 3)
      |> String.trim_trailing("0")

    sig_digits = if sig_digits == "", do: "0", else: sig_digits

    {:subscript, "0.0", zero_count, sig_digits}
  end

  defp simple_parts(d) do
    decimals =
      cond do
        Decimal.gte?(d, 1) -> 2
        Decimal.gte?(d, Decimal.new("0.01")) -> 4
        true -> 6
      end

    formatted =
      d
      |> Decimal.round(decimals)
      |> Decimal.to_string(:normal)
      |> trim_trailing_zeros()

    {:simple, formatted}
  end

  defp trim_trailing_zeros(str) do
    if String.contains?(str, "."),
      do: str |> String.trim_trailing("0") |> String.trim_trailing("."),
      else: str
  end

  # --- Duration formatting ---

  @doc """
  Formats a duration in seconds into a human-readable string.
  """
  def format_seconds(diff_seconds) when is_integer(diff_seconds) and diff_seconds >= 0,
    do: format_duration(diff_seconds)

  def format_seconds(_), do: gettext("N/A")

  defp format_duration(diff_seconds) when diff_seconds < 60, do: "< 1m"

  defp format_duration(diff_seconds) when diff_seconds < 3600 do
    minutes = div(diff_seconds, 60)
    "#{minutes}m"
  end

  defp format_duration(diff_seconds) when diff_seconds < 86_400 do
    hours = div(diff_seconds, 3600)
    minutes = div(rem(diff_seconds, 3600), 60)
    if minutes > 0, do: "#{hours}h #{minutes}m", else: "#{hours}h"
  end

  defp format_duration(diff_seconds) do
    days = div(diff_seconds, 86_400)
    hours = div(rem(diff_seconds, 86_400), 3600)
    if hours > 0, do: "#{days}d #{hours}h", else: "#{days}d"
  end

  # --- Occurrence helpers ---

  @doc """
  Returns the formatted entry->top price change percentage for a previous
  occurrence, e.g. `"+18.25%"` or `"N/A"`.
  """
  def occurrence_top_delta_text(occurrence) do
    case compute_top_delta_pct(occurrence) do
      nil ->
        gettext("N/A")

      pct ->
        sign = if pct > 0, do: "+", else: ""
        "#{sign}#{:erlang.float_to_binary(pct, decimals: 2)}%"
    end
  end

  @doc """
  Returns the Tailwind color classes for an entry->top delta badge.
  """
  def occurrence_top_delta_class(occurrence) do
    case compute_top_delta_pct(occurrence) do
      nil ->
        "bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"

      pct when pct > 0 ->
        "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400"

      pct when pct < 0 ->
        "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400"

      _ ->
        "bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"
    end
  end

  defp compute_top_delta_pct(%{entry_price: %Decimal{} = entry, top_price: %Decimal{} = top}) do
    if Decimal.equal?(entry, 0) do
      nil
    else
      top
      |> Decimal.sub(entry)
      |> Decimal.div(entry)
      |> Decimal.mult(100)
      |> Decimal.to_float()
    end
  end

  defp compute_top_delta_pct(_), do: nil

  @doc """
  Sorts a `%{position => seconds}` map into a list of `{position, seconds}`
  tuples ordered ascending by position (best first), for stable rendering.
  """
  def sorted_position_durations(position_durations) when is_map(position_durations) do
    position_durations
    |> Enum.sort_by(fn {position, _seconds} -> position end)
  end

  def sorted_position_durations(_), do: []
end
