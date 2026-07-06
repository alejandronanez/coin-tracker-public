# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     CoinTracker.Repo.insert!(%CoinTracker.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias CoinTracker.Repo
alias CoinTracker.Signals.MarketStatus

IO.puts("🌱 Seeding market status data...")

# Clear existing market status data
{deleted_count, _} = Repo.delete_all(MarketStatus)
IO.puts("   Deleted #{deleted_count} existing records")

# Generate 30 days of data ending at NOW
now = DateTime.utc_now() |> DateTime.truncate(:second)

# Calculate total records: 6 per hour × 24 hours × 30 days = 4,320
total_records = 6 * 24 * 30

IO.puts("   Generating #{total_records} records...")

# Generate records starting from NOW and going backwards
# This ensures the most recent data point is at the current time
records =
  Enum.map(0..(total_records - 1), fn index ->
    # Calculate timestamp (every 10 minutes going backwards from now)
    minutes_offset = index * 10

    recorded_at =
      now
      |> DateTime.add(-minutes_offset, :minute)
      |> DateTime.truncate(:second)

    # Generate semi-realistic signal count with patterns
    # Use sine wave for base trend + randomness
    # center around 5
    base_value = 5.0
    # vary by ±3
    amplitude = 3.0

    # Create slow oscillation over days (reverse index so pattern flows naturally)
    reverse_index = total_records - 1 - index
    # ~4 cycles over 30 days
    cycle_position = reverse_index / (total_records / 4)
    trend = :math.sin(cycle_position * 2 * :math.pi()) * amplitude

    # Add random variation
    # ±1
    noise = (:rand.uniform() - 0.5) * 2

    # Calculate final value and clamp to 0-10
    value =
      (base_value + trend + noise)
      |> round()
      |> max(0)
      |> min(10)

    %{
      active_signals_count: value,
      recorded_at: recorded_at,
      inserted_at: recorded_at,
      updated_at: recorded_at
    }
  end)

# Bulk insert for performance
{inserted_count, _} = Repo.insert_all(MarketStatus, records)

days_ago_30 = DateTime.add(now, -30, :day)
IO.puts("✅ Inserted #{inserted_count} market status records")
IO.puts("   Time range: #{DateTime.to_string(days_ago_30)} to #{DateTime.to_string(now)}")
