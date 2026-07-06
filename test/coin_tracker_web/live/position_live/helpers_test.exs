defmodule CoinTrackerWeb.PositionLive.HelpersTest do
  use ExUnit.Case, async: true

  alias CoinTrackerWeb.PositionLive.Helpers
  alias CoinTracker.Trading.Position

  describe "format_price/1" do
    test "returns 0 for nil" do
      assert Helpers.format_price(nil) == "0"
    end

    test "preserves all decimal places" do
      assert Helpers.format_price(Decimal.new("123.456")) == "123.456"
    end

    test "formats large numbers with commas" do
      assert Helpers.format_price(Decimal.new("1234567.89")) == "1,234,567.89"
    end

    test "formats whole numbers with commas" do
      assert Helpers.format_price(Decimal.new("1000")) == "1,000"
    end

    test "preserves very small decimals" do
      assert Helpers.format_price(Decimal.new("0.001")) == "0.001"
    end

    test "formats zero" do
      assert Helpers.format_price(Decimal.new("0")) == "0"
    end

    test "handles negative prices" do
      assert Helpers.format_price(Decimal.new("-1234.56")) == "-1,234.56"
    end

    test "removes trailing decimal zeros" do
      assert Helpers.format_price(Decimal.new("97500.50")) == "97,500.5"
    end

    test "formats price with many digits" do
      assert Helpers.format_price(Decimal.new("123456789.12")) == "123,456,789.12"
    end

    test "preserves all decimals without rounding" do
      assert Helpers.format_price(Decimal.new("99.999")) == "99.999"
    end

    test "preserves decimals without rounding" do
      assert Helpers.format_price(Decimal.new("99.994")) == "99.994"
    end
  end

  describe "calculate_preview_prices/1" do
    test "returns nil when entry_price is missing" do
      changeset =
        Position.create_changeset(%Position{}, %{
          "stop_loss_percent" => "-10",
          "take_profit_percent" => "20",
          "symbol" => "ETH",
          "current_threshold_zone" => "2"
        })

      assert Helpers.calculate_preview_prices(changeset) == nil
    end

    test "returns nil when stop_loss_percent is missing" do
      changeset =
        Position.create_changeset(%Position{}, %{
          "entry_price" => "1000",
          "take_profit_percent" => "20",
          "symbol" => "ETH",
          "current_threshold_zone" => "2"
        })

      assert Helpers.calculate_preview_prices(changeset) == nil
    end

    test "returns nil when take_profit_percent is missing" do
      changeset =
        Position.create_changeset(%Position{}, %{
          "entry_price" => "1000",
          "stop_loss_percent" => "-10",
          "symbol" => "ETH",
          "current_threshold_zone" => "2"
        })

      assert Helpers.calculate_preview_prices(changeset) == nil
    end

    test "calculates correct stop loss price (10% below entry)" do
      changeset =
        Position.create_changeset(%Position{}, %{
          "entry_price" => "1000",
          "stop_loss_percent" => "-10",
          "take_profit_percent" => "20",
          "symbol" => "ETH",
          "current_threshold_zone" => "2"
        })

      result = Helpers.calculate_preview_prices(changeset)

      # 1000 * (100 + (-10)) / 100 = 1000 * 0.9 = 900
      assert Decimal.equal?(result.stop_loss, Decimal.new("900"))
    end

    test "calculates correct take profit price (20% above entry)" do
      changeset =
        Position.create_changeset(%Position{}, %{
          "entry_price" => "1000",
          "stop_loss_percent" => "-10",
          "take_profit_percent" => "20",
          "symbol" => "ETH",
          "current_threshold_zone" => "2"
        })

      result = Helpers.calculate_preview_prices(changeset)

      # 1000 * (100 + 20) / 100 = 1000 * 1.2 = 1200
      assert Decimal.equal?(result.take_profit, Decimal.new("1200"))
    end

    test "handles decimal entry prices" do
      changeset =
        Position.create_changeset(%Position{}, %{
          "entry_price" => "2345.67",
          "stop_loss_percent" => "-5",
          "take_profit_percent" => "15",
          "symbol" => "ETH",
          "current_threshold_zone" => "2"
        })

      result = Helpers.calculate_preview_prices(changeset)

      # 2345.67 * 0.95 = 2228.3865
      # 2345.67 * 1.15 = 2697.5205
      assert Decimal.equal?(result.stop_loss, Decimal.new("2228.3865"))
      assert Decimal.equal?(result.take_profit, Decimal.new("2697.5205"))
    end

    test "handles very small stop loss percentages" do
      changeset =
        Position.create_changeset(%Position{}, %{
          "entry_price" => "50000",
          "stop_loss_percent" => "-0.5",
          "take_profit_percent" => "1",
          "symbol" => "BTC",
          "current_threshold_zone" => "2"
        })

      result = Helpers.calculate_preview_prices(changeset)

      # 50000 * 0.995 = 49750
      assert Decimal.equal?(result.stop_loss, Decimal.new("49750"))
    end

    test "handles zero stop loss (entry price as stop loss)" do
      changeset =
        Position.create_changeset(%Position{}, %{
          "entry_price" => "1000",
          "stop_loss_percent" => "0",
          "take_profit_percent" => "20",
          "symbol" => "ETH",
          "current_threshold_zone" => "2"
        })

      result = Helpers.calculate_preview_prices(changeset)

      # With 0% stop loss, price equals entry
      assert Decimal.equal?(result.stop_loss, Decimal.new("1000"))
    end

    test "handles large take profit percentage" do
      changeset =
        Position.create_changeset(%Position{}, %{
          "entry_price" => "100",
          "stop_loss_percent" => "-10",
          "take_profit_percent" => "200",
          "symbol" => "ETH",
          "current_threshold_zone" => "2"
        })

      result = Helpers.calculate_preview_prices(changeset)

      # 100 * 3.0 = 300
      assert Decimal.equal?(result.take_profit, Decimal.new("300"))
    end

    test "works with Position.changeset for edit form" do
      # Simulate a position being edited (using regular changeset, not create_changeset)
      position = %Position{
        entry_price: Decimal.new("2000"),
        stop_loss_percent: Decimal.new("-10"),
        take_profit_percent: Decimal.new("20")
      }

      changeset = Position.changeset(position, %{})

      result = Helpers.calculate_preview_prices(changeset)

      assert Decimal.equal?(result.stop_loss, Decimal.new("1800"))
      assert Decimal.equal?(result.take_profit, Decimal.new("2400"))
    end

    test "coerces string-typed struct fields to Decimals (edit form input shape)" do
      # The Edit LiveView formats Decimals to strings on the Position struct
      # before building the changeset, so get_field returns raw strings.
      position = %Position{
        entry_price: "2000",
        stop_loss_percent: "-10",
        take_profit_percent: "20",
        amount_invested: "500"
      }

      changeset = Position.changeset(position, %{})

      result = Helpers.calculate_preview_prices(changeset)

      assert Decimal.equal?(result.stop_loss, Decimal.new("1800"))
      assert Decimal.equal?(result.take_profit, Decimal.new("2400"))
      assert Decimal.equal?(result.stop_loss_percent, Decimal.new("-10"))
      assert Decimal.equal?(result.take_profit_percent, Decimal.new("20"))
      assert Decimal.equal?(result.stop_loss_pnl, Decimal.new("-50"))
      assert Decimal.equal?(result.take_profit_pnl, Decimal.new("100"))
    end

    test "returns percent keys mirroring the input" do
      changeset =
        Position.create_changeset(%Position{}, %{
          "entry_price" => "1000",
          "stop_loss_percent" => "-10",
          "take_profit_percent" => "20",
          "symbol" => "ETH",
          "current_threshold_zone" => "2"
        })

      result = Helpers.calculate_preview_prices(changeset)

      assert Decimal.equal?(result.stop_loss_percent, Decimal.new("-10"))
      assert Decimal.equal?(result.take_profit_percent, Decimal.new("20"))
    end

    test "returns nil pnl values when amount_invested is blank" do
      changeset =
        Position.create_changeset(%Position{}, %{
          "entry_price" => "1000",
          "stop_loss_percent" => "-10",
          "take_profit_percent" => "20",
          "symbol" => "ETH",
          "current_threshold_zone" => "2"
        })

      result = Helpers.calculate_preview_prices(changeset)

      assert result.stop_loss_pnl == nil
      assert result.take_profit_pnl == nil
    end

    test "calculates dollar pnl when amount_invested is present" do
      changeset =
        Position.create_changeset(%Position{}, %{
          "entry_price" => "1000",
          "stop_loss_percent" => "-10",
          "take_profit_percent" => "20",
          "amount_invested" => "500",
          "symbol" => "ETH",
          "current_threshold_zone" => "2"
        })

      result = Helpers.calculate_preview_prices(changeset)

      # 500 * -10 / 100 = -50
      assert Decimal.equal?(result.stop_loss_pnl, Decimal.new("-50"))
      # 500 * 20 / 100 = 100
      assert Decimal.equal?(result.take_profit_pnl, Decimal.new("100"))
    end
  end

  describe "format_pnl/1" do
    test "prefixes positive amounts with +$ and pads to two decimals" do
      assert Helpers.format_pnl(Decimal.new("100")) == "+$100.00"
    end

    test "prefixes negative amounts with -$" do
      assert Helpers.format_pnl(Decimal.new("-50")) == "-$50.00"
    end

    test "rounds half up to 2 decimals" do
      assert Helpers.format_pnl(Decimal.new("12.345")) == "+$12.35"
    end

    test "formats thousands with comma separators" do
      assert Helpers.format_pnl(Decimal.new("1500")) == "+$1,500.00"
    end

    test "treats zero as positive" do
      assert Helpers.format_pnl(Decimal.new("0")) == "+$0.00"
    end

    test "pads single-decimal values with a trailing zero" do
      assert Helpers.format_pnl(Decimal.new("12.5")) == "+$12.50"
    end
  end

  describe "format_pnl_percent/1" do
    test "prefixes positive percentages with +" do
      assert Helpers.format_pnl_percent(Decimal.new("20")) == "+20%"
    end

    test "keeps negative sign intact" do
      assert Helpers.format_pnl_percent(Decimal.new("-6")) == "-6%"
    end

    test "strips trailing zeros from decimals" do
      assert Helpers.format_pnl_percent(Decimal.new("20.0")) == "+20%"
    end

    test "preserves significant decimal digits" do
      assert Helpers.format_pnl_percent(Decimal.new("0.5")) == "+0.5%"
    end

    test "treats zero as positive" do
      assert Helpers.format_pnl_percent(Decimal.new("0")) == "+0%"
    end
  end
end
