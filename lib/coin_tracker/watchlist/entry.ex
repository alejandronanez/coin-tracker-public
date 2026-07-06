defmodule CoinTracker.Watchlist.Entry do
  @moduledoc """
  A position enriched with its current signal context.

  Fields:
    * `:position` - the underlying `%Trading.Position{}` (with `:symbol_price` preloaded)
    * `:base_symbol` - uppercased base symbol like `"ETH"` (matches `Signal.symbol`)
    * `:current_signal` - the most recent matching `%Signal{}`, or `nil`
    * `:entry_rank` - rank captured at position-create time (1-10), or `nil`
    * `:current_rank` - current rank from `current_signal.position`, or `nil`
    * `:rank_delta` - `entry_rank - current_rank` (positive = improved), or `nil`
    * `:status` - one of `:in_top`, `:dropped`, `:exited`, `:never_in_top`
    * `:dropped_at` - when the signal exited top 10, set on `:dropped` and `:exited`
    * `:grace_ended_at` - `dropped_at + 24h`, set on `:exited`
    * `:sparkline_points` - list of integers (positions over last 24h, oldest first)
  """
  defstruct [
    :position,
    :base_symbol,
    :current_signal,
    :entry_rank,
    :current_rank,
    :rank_delta,
    :status,
    :dropped_at,
    :grace_ended_at,
    :sparkline_points
  ]
end
