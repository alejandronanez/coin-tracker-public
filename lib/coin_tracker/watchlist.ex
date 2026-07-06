defmodule CoinTracker.Watchlist do
  @moduledoc """
  Watchlist orchestration: joins active `Trading.Position` records with the
  most recent matching `Signals.Signal` (matched by base symbol) so the UI can
  answer "is this coin still in the top 10, and how is its rank moving?"

  This module owns no schema. It composes `Trading` (positions) and `Signals`
  (current signal + 24h snapshot history) into per-position `Entry` structs
  consumed by `CoinTrackerWeb.PositionLive.Index`.

  See `docs/context-vs-orchestration.md` for why this is a separate module
  rather than a function on either context.
  """

  alias CoinTracker.Signals
  alias CoinTracker.Trading
  alias CoinTracker.Watchlist.Entry

  @doc """
  Extracts the uppercased base symbol from a symbol pair.

      iex> Watchlist.base_symbol("ETH/USDT")
      "ETH"

      iex> Watchlist.base_symbol("eth/USDT")
      "ETH"

      iex> Watchlist.base_symbol(nil)
      nil
  """
  def base_symbol(nil), do: nil

  def base_symbol(symbol_pair) when is_binary(symbol_pair) do
    case String.split(symbol_pair, "/") do
      [base | _] when base != "" -> String.upcase(base)
      _ -> nil
    end
  end

  @doc """
  Enriches a list of positions with watchlist context (current signal, rank
  delta, status, sparkline).

  Performs at most two batched queries regardless of list length: one for
  current signals, one for snapshots in the last 24h.
  """
  def enrich(positions) when is_list(positions) do
    base_symbols =
      positions
      |> Enum.map(&position_base_symbol/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    signals_by_symbol = Signals.latest_signals_for(base_symbols)
    snapshots_by_symbol = snapshots_last_24h(base_symbols)

    Enum.map(positions, fn position ->
      base = position_base_symbol(position)
      signal = base && Map.get(signals_by_symbol, base)
      snapshots = (base && Map.get(snapshots_by_symbol, base, [])) || []

      build_entry(position, base, signal, snapshots)
    end)
  end

  @doc """
  Returns the fraction (0.0 - 1.0) of currently-active positions whose base
  symbol resolves to a current `Signal`. `1.0` if there are no active positions.

  This is the early-warning metric for symbol-matching breakage. A drop below
  ~0.7 in production indicates `base_symbol/1` is failing to extract symbols
  the way the signal feed expects, not that no positions overlap with current
  signals.
  """
  def coverage_ratio do
    positions = Trading.list_all_active_positions()

    case positions do
      [] ->
        1.0

      _ ->
        base_symbols =
          positions
          |> Enum.map(&position_base_symbol/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        signals = Signals.current_signals_for(base_symbols)

        matched =
          Enum.count(positions, fn p ->
            base = position_base_symbol(p)
            base && Map.has_key?(signals, base)
          end)

        matched / length(positions)
    end
  end

  defp position_base_symbol(%{symbol_price: %{symbol_pair: pair}}), do: base_symbol(pair)
  defp position_base_symbol(_), do: nil

  defp build_entry(position, base, signal, snapshots) do
    {status, dropped_at, grace_ended_at} = compute_status(signal)
    current_rank = if status == :in_top, do: signal && signal.position, else: nil
    entry_rank = position.entry_rank

    rank_delta =
      cond do
        is_nil(entry_rank) -> nil
        is_nil(current_rank) -> nil
        true -> entry_rank - current_rank
      end

    %Entry{
      position: position,
      base_symbol: base,
      current_signal: signal,
      entry_rank: entry_rank,
      current_rank: current_rank,
      rank_delta: rank_delta,
      status: status,
      dropped_at: dropped_at,
      grace_ended_at: grace_ended_at,
      sparkline_points: Enum.map(snapshots, & &1.position) |> Enum.reject(&is_nil/1)
    }
  end

  @grace_period_hours 24

  defp compute_status(nil), do: {:never_in_top, nil, nil}
  defp compute_status(%{in_top: true}), do: {:in_top, nil, nil}

  defp compute_status(%{in_top: false, exit_date: exit_date}) do
    grace_end = DateTime.add(exit_date, @grace_period_hours, :hour)

    case DateTime.compare(grace_end, DateTime.utc_now()) do
      :gt -> {:dropped, exit_date, nil}
      _ -> {:exited, exit_date, grace_end}
    end
  end

  defp snapshots_last_24h(base_symbols) do
    cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)
    Signals.snapshots_for_symbols_since(base_symbols, cutoff)
  end
end
