defmodule CoinTracker.Signals.SignalTest do
  use CoinTracker.DataCase, async: true

  alias CoinTracker.Signals.Signal

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        symbol: "BTC",
        name: "Bitcoin",
        in_top_since: ~U[2025-10-04 02:00:11Z]
      }

      changeset = Signal.changeset(%Signal{}, attrs)
      assert changeset.valid?
    end

    test "requires symbol, name, and in_top_since" do
      changeset = Signal.changeset(%Signal{}, %{})

      refute changeset.valid?
      assert %{symbol: ["can't be blank"]} = errors_on(changeset)
      assert %{name: ["can't be blank"]} = errors_on(changeset)
      assert %{in_top_since: ["can't be blank"]} = errors_on(changeset)
    end

    test "casts all optional fields" do
      attrs = %{
        symbol: "ETH",
        name: "Ethereum",
        in_top_since: ~U[2025-10-04 02:00:11Z],
        initial_volume_24h: Decimal.new("15000000.50"),
        current_volume_24h: Decimal.new("18000000.75"),
        initial_price_usd: Decimal.new("2500.00"),
        max_price_usd: Decimal.new("2650.00"),
        max_increase_percentage: Decimal.new("6.0"),
        in_top: true,
        active: true
      }

      changeset = Signal.changeset(%Signal{}, attrs)
      assert changeset.valid?
      assert changeset.changes.in_top == true
    end
  end

  describe "volume_increase/1" do
    test "calculates volume increase correctly" do
      signal = %Signal{
        initial_volume_24h: Decimal.new("15000000"),
        current_volume_24h: Decimal.new("18000000")
      }

      increase = Signal.volume_increase(signal)
      assert Decimal.equal?(increase, Decimal.new("3000000"))
    end

    test "handles nil current_volume_24h without crashing" do
      signal = %Signal{
        initial_volume_24h: Decimal.new("15000000"),
        current_volume_24h: nil
      }

      increase = Signal.volume_increase(signal)
      assert Decimal.equal?(increase, Decimal.new("0"))
    end

    test "handles nil initial_volume_24h without crashing" do
      signal = %Signal{
        initial_volume_24h: nil,
        current_volume_24h: Decimal.new("18000000")
      }

      increase = Signal.volume_increase(signal)
      assert Decimal.equal?(increase, Decimal.new("0"))
    end
  end

  describe "volume_increase_percentage/1" do
    test "calculates percentage increase correctly" do
      signal = %Signal{
        initial_volume_24h: Decimal.new("10000000"),
        current_volume_24h: Decimal.new("15000000")
      }

      percentage = Signal.volume_increase_percentage(signal)
      assert Decimal.equal?(percentage, Decimal.new("50"))
    end

    test "returns zero when initial volume is zero" do
      signal = %Signal{
        initial_volume_24h: Decimal.new("0"),
        current_volume_24h: Decimal.new("15000000")
      }

      percentage = Signal.volume_increase_percentage(signal)
      assert Decimal.equal?(percentage, Decimal.new("0"))
    end

    test "returns zero when initial volume is nil" do
      signal = %Signal{
        initial_volume_24h: nil,
        current_volume_24h: Decimal.new("15000000")
      }

      percentage = Signal.volume_increase_percentage(signal)
      assert Decimal.equal?(percentage, Decimal.new("0"))
    end
  end

  describe "database constraints" do
    test "enforces unique constraint on symbol and in_top_since" do
      attrs = %{
        symbol: "BTC",
        name: "Bitcoin",
        in_top_since: ~U[2025-10-04 02:00:11Z]
      }

      # Insert first signal
      %Signal{}
      |> Signal.changeset(attrs)
      |> Repo.insert!()

      # Try to insert duplicate
      assert {:error, changeset} =
               %Signal{}
               |> Signal.changeset(attrs)
               |> Repo.insert()

      assert %{symbol: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
