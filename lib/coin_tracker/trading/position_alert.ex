defmodule CoinTracker.Trading.PositionAlert do
  @moduledoc """
  Pure functions for position alert detection and validation.

  This module handles all alert checking logic without side effects:
  - Positive threshold alerts (milestone-based upward movement)
  - Recovery alerts (negative to positive transition)
  - Negative proximity alerts (approaching stop-loss)
  - Critical alerts (take-profit/stop-loss hit)
  - Volume surge alerts (window + cumulative, watch-mode only)

  All functions are pure and require no database calls.
  """

  # Volume alert tuning — global defaults, tune based on real data.
  #
  # Window tiers measure growth of current_volume_24h vs the snapshot from
  # @volume_window_lookback_minutes ago. Because current_volume_24h is itself
  # a sliding 24h window, a 25% delta over an hour reflects a meaningful
  # surge in current-hour activity (not literally "+25% in one hour").
  @volume_window_lookback_minutes 60
  @volume_window_tolerance_minutes 30
  @volume_window_tiers [10, 25, 50]

  # Cumulative tiers measure growth since the signal entered the top 10
  # (Signal.volume_increase_percentage). Mirrors the existing UI chip tiers.
  @volume_cumulative_tiers [20, 100]

  def volume_window_lookback_minutes, do: @volume_window_lookback_minutes
  def volume_window_tolerance_minutes, do: @volume_window_tolerance_minutes
  def volume_window_tiers, do: @volume_window_tiers
  def volume_cumulative_tiers, do: @volume_cumulative_tiers

  @doc """
  Checks if a position should trigger a positive threshold alert.

  Alerts when price crosses a new higher threshold based on the position's
  configured step size (e.g., 2%, 4%, 50%). Uses 30-second throttle.

  Returns `{:alert, message}` if alert should be sent, `:no_alert` otherwise.

  ## Examples

      iex> position = %{current_threshold_zone: Decimal.new("2"), last_alerted_threshold_positive: Decimal.new("2"), last_alerted_at: now}
      iex> current_pnl = Decimal.new("5.5")
      iex> PositionAlert.check_positive_alert(position, current_pnl, now)
      {:alert, "🚀 Crossed 4% profit"}

      iex> position = %{current_threshold_zone: Decimal.new("2"), last_alerted_threshold_positive: Decimal.new("4"), last_alerted_at: now}
      iex> current_pnl = Decimal.new("3.5")
      iex> PositionAlert.check_positive_alert(position, current_pnl, now)
      :no_alert
  """
  def check_positive_alert(position, current_pnl, now) do
    step = to_decimal(position.current_threshold_zone)
    current_pnl_decimal = to_decimal(current_pnl)
    last_alerted = position.last_alerted_threshold_positive || Decimal.new("0")
    last_alerted_at = position.last_alerted_at

    # Calculate current threshold (highest complete threshold crossed)
    current_threshold = calculate_current_threshold(current_pnl_decimal, step)

    # Should alert if:
    # 1. Crossed to a new higher threshold, AND
    # 2. The threshold is positive (at or above the first step), AND
    # 3. Either never alerted before OR 30+ seconds have passed
    should_alert =
      Decimal.compare(current_threshold, last_alerted) == :gt and
        Decimal.compare(current_threshold, step) in [:gt, :eq] and
        not throttled?(last_alerted_at, now)

    if should_alert do
      {:alert, "🚀 Crossed #{format_decimal(current_threshold)}% profit"}
    else
      :no_alert
    end
  end

  @doc """
  Watch-mode variant of `check_positive_alert/3`.

  Identical step-bucket logic, but **without** the "must be ≥ first step"
  gate. A stepwise upward crossing fires even when the threshold is still
  negative (e.g., -20% → -15%), so users can be alerted to recoveries from
  drawdowns before the coin breaks even.

  Returns `{:alert, current_threshold}` so the caller can render its own
  message (positive/zero/negative wording differs). Returns `:no_alert`
  otherwise.

  Drops are not alerted here — the caller is expected to persist a
  downward baseline update separately, mirroring the real-money path.
  """
  def check_watch_surge_alert(position, current_pnl, now) do
    step = to_decimal(position.current_threshold_zone)
    current_pnl_decimal = to_decimal(current_pnl)
    last_alerted = position.last_alerted_threshold_positive || Decimal.new("0")
    last_alerted_at = position.last_alerted_at

    current_threshold = calculate_current_threshold(current_pnl_decimal, step)

    should_alert =
      Decimal.compare(current_threshold, last_alerted) == :gt and
        not throttled?(last_alerted_at, now)

    if should_alert do
      {:alert, current_threshold}
    else
      :no_alert
    end
  end

  @doc """
  Builds the Telegram-facing message for a watch-mode surge.

  Wording depends on the sign of `current_threshold` — a coin still in the
  red shouldn't say "Up X%". Pure formatter; safe to unit-test in isolation.
  """
  def watch_surge_message(current_threshold) do
    threshold = to_decimal(current_threshold)
    zero = Decimal.new("0")

    cond do
      Decimal.compare(threshold, zero) == :gt ->
        "📈 Up #{format_decimal(threshold)}% since entering the top 10"

      Decimal.compare(threshold, zero) == :eq ->
        "🔄 Back to break-even since entering the top 10"

      true ->
        "🔼 Recovering to #{format_decimal(threshold)}% since entering the top 10"
    end
  end

  @doc """
  Checks if a watched position should fire a short-window volume surge alert.

  Compares `current_volume_24h` against the volume from
  `@volume_window_lookback_minutes` ago. If the growth crosses a new (higher)
  tier in `@volume_window_tiers`, returns `{:alert, tier}` where `tier` is a
  Decimal matching one of the tier integers. Otherwise `:no_alert`.

  Skips silently when `baseline_volume` is nil or zero (no surge signal
  possible). Drops in volume never alert — only upward crossings.

  Throttled by `position.last_alerted_at` (shared 30s gate across all
  watch-mode alert kinds).
  """
  def check_volume_window_surge(position, current_volume, baseline_volume, now) do
    cond do
      is_nil(baseline_volume) ->
        :no_alert

      decimal_zero?(baseline_volume) ->
        :no_alert

      is_nil(current_volume) ->
        :no_alert

      true ->
        growth_pct = percentage_change(current_volume, baseline_volume)
        last_alerted = position.last_alerted_volume_window_tier
        last_alerted_at = position.last_alerted_at

        evaluate_tier_crossing(
          growth_pct,
          @volume_window_tiers,
          last_alerted,
          last_alerted_at,
          now
        )
    end
  end

  @doc """
  Checks if a watched position should fire a cumulative volume tier alert.

  `cumulative_growth_pct` is the precomputed % growth since the signal
  entered the top 10 (typically `Signal.volume_increase_percentage/1`).
  When growth crosses a new (higher) tier in `@volume_cumulative_tiers`,
  returns `{:alert, tier}`; otherwise `:no_alert`.

  Throttled by `position.last_alerted_at`.
  """
  def check_volume_cumulative_tier(position, cumulative_growth_pct, now) do
    if is_nil(cumulative_growth_pct) do
      :no_alert
    else
      last_alerted = position.last_alerted_volume_cumulative_tier
      last_alerted_at = position.last_alerted_at

      evaluate_tier_crossing(
        cumulative_growth_pct,
        @volume_cumulative_tiers,
        last_alerted,
        last_alerted_at,
        now
      )
    end
  end

  @doc """
  Returns the largest tier in `tiers` that is ≤ `growth_pct`, as a Decimal,
  or `nil` if `growth_pct` is below the smallest tier (or non-positive).

  `tiers` is a list of integers in ascending order.

  ## Examples

      iex> PositionAlert.highest_crossed_tier(Decimal.new("30"), [10, 25, 50])
      Decimal.new("25")

      iex> PositionAlert.highest_crossed_tier(Decimal.new("5"), [10, 25, 50])
      nil

      iex> PositionAlert.highest_crossed_tier(Decimal.new("-3"), [10, 25, 50])
      nil
  """
  def highest_crossed_tier(growth_pct, tiers) do
    growth_decimal = to_decimal(growth_pct)

    tiers
    |> Enum.sort()
    |> Enum.map(&Decimal.new/1)
    |> Enum.filter(fn tier -> Decimal.compare(growth_decimal, tier) in [:gt, :eq] end)
    |> List.last()
  end

  @doc """
  Telegram message for a short-window volume surge tier crossing.
  """
  def volume_window_surge_message(tier) do
    "🔊 Volume surging: +#{format_decimal(to_decimal(tier))}% in the last hour"
  end

  @doc """
  Telegram message for a cumulative since-signal volume tier crossing.
  """
  def volume_cumulative_tier_message(tier) do
    "📊 Volume up #{format_decimal(to_decimal(tier))}% since entering the top 10"
  end

  @doc """
  Checks if a position should trigger a recovery alert.

  Alerts when position transitions from negative to positive profit.
  Returns `:no_alert` if last_pnl is nil (no historical data to compare).
  Uses 30-second throttle.

  Returns `{:alert, message}` if alert should be sent, `:no_alert` otherwise.

  ## Examples

      iex> PositionAlert.check_recovery_alert(Decimal.new("-2"), Decimal.new("2"), now, nil)
      {:alert, "🔄 Position recovered to positive!"}

      iex> PositionAlert.check_recovery_alert(Decimal.new("2"), Decimal.new("5"), now, nil)
      :no_alert

      iex> PositionAlert.check_recovery_alert(nil, Decimal.new("5"), now, nil)
      :no_alert
  """
  def check_recovery_alert(nil, _current_pnl, _now, _last_alerted_at) do
    # No historical data to compare, can't detect recovery
    :no_alert
  end

  def check_recovery_alert(last_pnl, current_pnl, now, last_alerted_at) do
    last_pnl_decimal = to_decimal(last_pnl)
    current_pnl_decimal = to_decimal(current_pnl)

    # Recovery happens when: was negative, now positive
    is_recovery =
      Decimal.compare(last_pnl_decimal, Decimal.new("0")) == :lt and
        Decimal.compare(current_pnl_decimal, Decimal.new("0")) in [:gt, :eq]

    if is_recovery and not throttled?(last_alerted_at, now) do
      {:alert, "🔄 Position recovered to positive!"}
    else
      :no_alert
    end
  end

  @doc """
  Checks if a position should trigger a negative proximity alert.

  Warns when position approaches stop-loss at 80%, 85%, 90%, 95% levels.
  Returns most negative proximity level currently in.
  Uses 30-second throttle.

  Returns `{:alert, message, proximity}` if alert should be sent, `:no_alert` otherwise.

  ## Examples

      iex> position = %{stop_loss_percent: Decimal.new("-20"), last_alerted_negative_proximity: nil, last_alerted_at: nil}
      iex> current_pnl = Decimal.new("-17")
      iex> PositionAlert.check_negative_proximity_alert(position, current_pnl, now)
      {:alert, "⚠️ Warning: 85% toward stop-loss (-17.00%)", 85}

      iex> position = %{stop_loss_percent: Decimal.new("-20"), last_alerted_negative_proximity: 85, last_alerted_at: now}
      iex> current_pnl = Decimal.new("-15")
      iex> PositionAlert.check_negative_proximity_alert(position, current_pnl, now)
      :no_alert
  """
  def check_negative_proximity_alert(position, current_pnl, now) do
    stop_loss = to_decimal(position.stop_loss_percent)
    current_pnl_decimal = to_decimal(current_pnl)
    last_alerted_proximity = position.last_alerted_negative_proximity
    last_alerted_at = position.last_alerted_at

    # Proximity thresholds as {level, percentage}
    proximity_zones = [
      {80, Decimal.mult(stop_loss, Decimal.new("0.80"))},
      {85, Decimal.mult(stop_loss, Decimal.new("0.85"))},
      {90, Decimal.mult(stop_loss, Decimal.new("0.90"))},
      {95, Decimal.mult(stop_loss, Decimal.new("0.95"))}
    ]

    # Find which proximity zones we've crossed (entered)
    crossed =
      Enum.filter(proximity_zones, fn {_level, threshold} ->
        Decimal.compare(current_pnl_decimal, threshold) in [:lt, :eq]
      end)

    if Enum.empty?(crossed) do
      # Not in any proximity zone
      :no_alert
    else
      # Get the closest (least negative, best) threshold we've crossed
      {worst_proximity, _worst_threshold} = Enum.max_by(crossed, fn {_l, t} -> t end)

      # Should alert if:
      # 1. We've gone more negative than last alerted proximity, AND
      # 2. 30+ seconds have passed
      is_new_worse =
        case last_alerted_proximity do
          nil ->
            # First time in any proximity zone
            true

          last_level ->
            # Only alert if we've gone to a worse proximity
            worst_proximity > last_level
        end

      if is_new_worse and not throttled?(last_alerted_at, now) do
        formatted_pnl = format_decimal(current_pnl_decimal)

        {:alert, "⚠️ Warning: #{worst_proximity}% toward stop-loss (#{formatted_pnl}%)",
         worst_proximity}
      else
        :no_alert
      end
    end
  end

  @doc """
  Checks if a position should be closed due to take-profit or stop-loss.

  This is a critical alert that bypasses the 30-second throttle.
  Always returns immediately when thresholds are hit.

  Returns `{:close, :take_profit, message}`, `{:close, :stop_loss, message}`, or `:no_close`.

  ## Examples

      iex> zones = %{take_profit: Decimal.new("25"), stop_loss: Decimal.new("-20")}
      iex> current_pnl = Decimal.new("26")
      iex> PositionAlert.check_closure_alert(current_pnl, zones, Decimal.new("105"))
      {:close, :take_profit, "🎯 Take-profit hit at $105! Position closed.\\nCheck your exchange to see your PnL."}

      iex> zones = %{take_profit: Decimal.new("25"), stop_loss: Decimal.new("-20")}
      iex> current_pnl = Decimal.new("15")
      iex> PositionAlert.check_closure_alert(current_pnl, zones, Decimal.new("115"))
      :no_close
  """
  def check_closure_alert(current_pnl, alert_zones, current_price, amount_invested \\ nil) do
    current_pnl_decimal = to_decimal(current_pnl)
    current_price_decimal = to_decimal(current_price)

    cond do
      Decimal.compare(current_pnl_decimal, alert_zones.take_profit) in [:eq, :gt] ->
        formatted_price = format_price(current_price_decimal)
        pnl_line = format_pnl_line(current_pnl_decimal, amount_invested)

        {:close, :take_profit,
         "🎯 Take-profit hit at $#{formatted_price}! Position closed.\n#{pnl_line}"}

      Decimal.compare(current_pnl_decimal, alert_zones.stop_loss) in [:eq, :lt] ->
        formatted_price = format_price(current_price_decimal)
        pnl_line = format_pnl_line(current_pnl_decimal, amount_invested)

        {:close, :stop_loss,
         "🛑 Stop-loss hit at $#{formatted_price}! Position closed.\n#{pnl_line}"}

      true ->
        :no_close
    end
  end

  @doc """
  Calculates seconds elapsed since last alert.

  Returns 0 if no last alert time, otherwise seconds difference.

  ## Examples

      iex> PositionAlert.seconds_since_alert(nil)
      999999

      iex> now = DateTime.utc_now()
      iex> past = DateTime.add(now, -60, :second)
      iex> PositionAlert.seconds_since_alert(past, now)
      60
  """
  def seconds_since_alert(nil), do: 999_999

  def seconds_since_alert(last_alerted_at, now \\ DateTime.utc_now()) do
    DateTime.diff(now, last_alerted_at, :second)
  end

  # Private functions

  @doc false
  def calculate_current_threshold(current_pnl, step) do
    # floor(current_pnl / step) * step
    # e.g., if current_pnl=5.5 and step=2: floor(5.5/2)*2 = floor(2.75)*2 = 2*2 = 4
    current_pnl
    |> Decimal.div(step)
    |> Decimal.round(0, :down)
    |> Decimal.mult(step)
  end

  @doc false
  def throttled?(last_alerted_at, now \\ DateTime.utc_now())

  def throttled?(nil, _now), do: false

  def throttled?(last_alerted_at, now) do
    seconds = seconds_since_alert(last_alerted_at, now)
    seconds < 30
  end

  defp to_decimal(%Decimal{} = decimal), do: decimal
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)

  defp evaluate_tier_crossing(growth_pct, tiers, last_alerted, last_alerted_at, now) do
    case highest_crossed_tier(growth_pct, tiers) do
      nil ->
        :no_alert

      tier ->
        last = last_alerted || Decimal.new("0")

        if Decimal.compare(tier, last) == :gt and not throttled?(last_alerted_at, now) do
          {:alert, tier}
        else
          :no_alert
        end
    end
  end

  defp percentage_change(current, baseline) do
    current_d = to_decimal(current)
    baseline_d = to_decimal(baseline)

    current_d
    |> Decimal.sub(baseline_d)
    |> Decimal.div(baseline_d)
    |> Decimal.mult(100)
  end

  defp decimal_zero?(value) do
    Decimal.compare(to_decimal(value), Decimal.new(0)) == :eq
  end

  defp format_decimal(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp format_price(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp format_pnl_line(_current_pnl, nil) do
    "Check your exchange to see your PnL."
  end

  defp format_pnl_line(current_pnl, amount_invested) do
    amount_invested_decimal = to_decimal(amount_invested)

    # Calculate dollar PnL: amount_invested * (pnl_percent / 100)
    dollar_pnl =
      amount_invested_decimal
      |> Decimal.mult(current_pnl)
      |> Decimal.div(Decimal.new(100))
      |> Decimal.round(2)

    pnl_percent = format_decimal(current_pnl)

    # Format with sign prefix
    sign = if Decimal.compare(dollar_pnl, Decimal.new(0)) == :lt, do: "", else: "+"
    formatted_dollar = Decimal.abs(dollar_pnl) |> Decimal.to_string()

    dollar_sign = if Decimal.compare(dollar_pnl, Decimal.new(0)) == :lt, do: "-$", else: "+$"

    "PnL: ~#{dollar_sign}#{formatted_dollar} (#{sign}#{pnl_percent}%)"
  end
end
