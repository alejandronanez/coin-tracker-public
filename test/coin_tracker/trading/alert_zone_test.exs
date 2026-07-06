defmodule CoinTracker.Trading.AlertZoneTest do
  use ExUnit.Case, async: true

  alias CoinTracker.Trading.AlertZone

  describe "calculate_current_pnl/2" do
    test "calculates positive profit percentage" do
      entry_price = Decimal.new("100")
      current_price = Decimal.new("110")

      result = AlertZone.calculate_current_pnl(entry_price, current_price)

      assert Decimal.eq?(result, Decimal.new("10.00"))
    end

    test "calculates negative loss percentage" do
      entry_price = Decimal.new("100")
      current_price = Decimal.new("95")

      result = AlertZone.calculate_current_pnl(entry_price, current_price)

      assert Decimal.eq?(result, Decimal.new("-5.00"))
    end

    test "calculates zero when price unchanged" do
      entry_price = Decimal.new("100")
      current_price = Decimal.new("100")

      result = AlertZone.calculate_current_pnl(entry_price, current_price)

      assert Decimal.eq?(result, Decimal.new("0"))
    end

    test "handles fractional percentages" do
      entry_price = Decimal.new("100")
      current_price = Decimal.new("102.50")

      result = AlertZone.calculate_current_pnl(entry_price, current_price)

      assert Decimal.eq?(result, Decimal.new("2.50"))
    end

    test "handles large price movements" do
      entry_price = Decimal.new("100")
      current_price = Decimal.new("250")

      result = AlertZone.calculate_current_pnl(entry_price, current_price)

      assert Decimal.eq?(result, Decimal.new("150.00"))
    end
  end

  describe "determine_alert_zones/3" do
    test "generates positive zones with 5% threshold up to 25% take profit" do
      zones = AlertZone.determine_alert_zones(5, Decimal.new("25"), Decimal.new("-25"))

      assert length(zones.positive_zones) == 4
      assert Decimal.eq?(Enum.at(zones.positive_zones, 0), Decimal.new("5"))
      assert Decimal.eq?(Enum.at(zones.positive_zones, 1), Decimal.new("10"))
      assert Decimal.eq?(Enum.at(zones.positive_zones, 2), Decimal.new("15"))
      assert Decimal.eq?(Enum.at(zones.positive_zones, 3), Decimal.new("20"))
    end

    test "generates negative zones at 90% and 95% of stop loss" do
      zones = AlertZone.determine_alert_zones(5, Decimal.new("25"), Decimal.new("-25"))

      assert length(zones.negative_zones) == 2
      # 90% of -25 = -22.5
      assert Decimal.eq?(Enum.at(zones.negative_zones, 0), Decimal.new("-22.5"))
      # 95% of -25 = -23.75
      assert Decimal.eq?(Enum.at(zones.negative_zones, 1), Decimal.new("-23.75"))
    end

    test "includes take profit and stop loss in result" do
      zones = AlertZone.determine_alert_zones(5, Decimal.new("25"), Decimal.new("-25"))

      assert Decimal.eq?(zones.take_profit, Decimal.new("25"))
      assert Decimal.eq?(zones.stop_loss, Decimal.new("-25"))
    end

    test "handles different threshold zones" do
      # With 10% threshold
      zones = AlertZone.determine_alert_zones(10, Decimal.new("30"), Decimal.new("-20"))

      assert length(zones.positive_zones) == 2
      assert Decimal.eq?(Enum.at(zones.positive_zones, 0), Decimal.new("10"))
      assert Decimal.eq?(Enum.at(zones.positive_zones, 1), Decimal.new("20"))
    end

    test "handles edge case where take profit equals threshold" do
      # If take profit is 5% and threshold is 5%, no intermediate zones
      zones = AlertZone.determine_alert_zones(5, Decimal.new("5"), Decimal.new("-10"))

      assert zones.positive_zones == []
      assert Decimal.eq?(zones.take_profit, Decimal.new("5"))
    end
  end

  describe "should_close_position?/2" do
    setup do
      zones = AlertZone.determine_alert_zones(5, Decimal.new("25"), Decimal.new("-25"))
      %{zones: zones}
    end

    test "returns :no_close when in profit but below take profit", %{zones: zones} do
      result = AlertZone.should_close_position?(Decimal.new("20"), zones)

      assert result == :no_close
    end

    test "returns :no_close when at loss but above stop loss", %{zones: zones} do
      result = AlertZone.should_close_position?(Decimal.new("-20"), zones)

      assert result == :no_close
    end

    test "returns {:close, :take_profit} when reaching take profit", %{zones: zones} do
      result = AlertZone.should_close_position?(Decimal.new("25"), zones)

      assert result == {:close, :take_profit}
    end

    test "returns {:close, :take_profit} when exceeding take profit", %{zones: zones} do
      result = AlertZone.should_close_position?(Decimal.new("30"), zones)

      assert result == {:close, :take_profit}
    end

    test "returns {:close, :stop_loss} when reaching stop loss", %{zones: zones} do
      result = AlertZone.should_close_position?(Decimal.new("-25"), zones)

      assert result == {:close, :stop_loss}
    end

    test "returns {:close, :stop_loss} when below stop loss", %{zones: zones} do
      result = AlertZone.should_close_position?(Decimal.new("-30"), zones)

      assert result == {:close, :stop_loss}
    end
  end

  describe "edge cases and rounding" do
    test "handles very small price movements" do
      entry = Decimal.new("100.00")
      current = Decimal.new("100.01")

      pnl = AlertZone.calculate_current_pnl(entry, current)

      assert Decimal.eq?(pnl, Decimal.new("0.01"))
    end

    test "handles very large profit percentages" do
      zones = AlertZone.determine_alert_zones(10, Decimal.new("200"), Decimal.new("-50"))

      # 20 zones: 10, 20, 30, ..., 190
      assert length(zones.positive_zones) == 19
    end
  end
end
