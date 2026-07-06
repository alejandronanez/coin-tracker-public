defmodule CoinTracker.Trading.PositionTest do
  use CoinTracker.DataCase

  alias CoinTracker.Trading.Position

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      changeset =
        %Position{}
        |> Position.changeset(%{
          entry_price: Decimal.new("100"),
          stop_loss_percent: -10,
          take_profit_percent: 10
        })

      assert changeset.valid?
    end

    test "invalid when required fields are missing" do
      changeset = Position.changeset(%Position{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).entry_price
      assert "can't be blank" in errors_on(changeset).stop_loss_percent
      assert "can't be blank" in errors_on(changeset).take_profit_percent
    end

    test "invalid when entry_price is zero or negative" do
      changeset_zero =
        Position.changeset(%Position{}, %{
          entry_price: 0,
          stop_loss_percent: -10,
          take_profit_percent: 20
        })

      changeset_negative =
        Position.changeset(%Position{}, %{
          entry_price: -100,
          stop_loss_percent: -10,
          take_profit_percent: 20
        })

      refute changeset_zero.valid?
      assert "must be greater than 0" in errors_on(changeset_zero).entry_price

      refute changeset_negative.valid?
      assert "must be greater than 0" in errors_on(changeset_negative).entry_price
    end

    test "invalid when stop_loss_percent is greater than or equal to take_profit_percent" do
      # stop_loss > take_profit
      changeset_greater =
        Position.changeset(%Position{}, %{
          entry_price: 100,
          stop_loss_percent: -5,
          take_profit_percent: -10
        })

      # stop_loss == take_profit
      changeset_equal =
        Position.changeset(%Position{}, %{
          entry_price: 100,
          stop_loss_percent: 10,
          take_profit_percent: 10
        })

      refute changeset_greater.valid?

      assert "must be less than take profit percent" in errors_on(changeset_greater).stop_loss_percent

      refute changeset_equal.valid?

      assert "must be less than take profit percent" in errors_on(changeset_equal).stop_loss_percent
    end

    test "valid when stop_loss_percent is less than take_profit_percent" do
      changeset =
        Position.changeset(%Position{}, %{
          entry_price: 100,
          stop_loss_percent: -25,
          take_profit_percent: -15
        })

      assert changeset.valid?
    end
  end

  describe "create_changeset/2" do
    test "valid changeset with proper create values" do
      changeset =
        %Position{}
        |> Position.create_changeset(%{
          symbol: "ETH",
          exchange: "binance_spot",
          entry_price: Decimal.new("100"),
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      assert changeset.valid?
    end

    test "invalid when stop_loss_percent is positive" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "BTC",
          entry_price: 100,
          stop_loss_percent: 5,
          take_profit_percent: 20
        })

      refute changeset.valid?
      assert "must be less than or equal to 0" in errors_on(changeset).stop_loss_percent
    end

    test "invalid when take_profit_percent is zero or negative" do
      changeset_zero =
        Position.create_changeset(%Position{}, %{
          symbol: "SOL",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 0
        })

      changeset_negative =
        Position.create_changeset(%Position{}, %{
          symbol: "SOL",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: -20
        })

      refute changeset_zero.valid?
      assert "must be greater than 0" in errors_on(changeset_zero).take_profit_percent

      refute changeset_negative.valid?
      assert "must be greater than 0" in errors_on(changeset_negative).take_profit_percent
    end

    test "invalid when stop_loss_percent is greater than take_profit_percent" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "ADA",
          entry_price: 100,
          stop_loss_percent: -5,
          take_profit_percent: -10
        })

      refute changeset.valid?
      assert "must be less than take profit percent" in errors_on(changeset).stop_loss_percent
    end

    test "valid with stop_loss at 0 (break-even)" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "MATIC",
          exchange: "binance_spot",
          entry_price: 100,
          stop_loss_percent: 0,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      assert changeset.valid?
    end

    test "valid with integer threshold" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "BTC",
          exchange: "binance_spot",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      assert changeset.valid?
    end

    test "valid with decimal threshold" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "ETH",
          exchange: "binance_spot",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 2.5
        })

      assert changeset.valid?
    end

    test "invalid when threshold is zero" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "ADA",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 0
        })

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).current_threshold_zone
    end

    test "invalid when threshold is negative" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "SOL",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: -5
        })

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).current_threshold_zone
    end

    test "invalid when threshold is missing" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "DOT",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).current_threshold_zone
    end
  end

  describe "create_changeset/2 symbol validation" do
    test "invalid when symbol is missing" do
      changeset =
        Position.create_changeset(%Position{}, %{
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).symbol
    end

    test "invalid when symbol is empty string" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).symbol
    end

    test "invalid when symbol has invalid characters" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "ETH/USD",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      refute changeset.valid?

      assert "must contain only letters and numbers (supports any language)" in errors_on(
               changeset
             ).symbol
    end

    test "invalid when symbol has special characters" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "BTC-USD",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      refute changeset.valid?

      assert "must contain only letters and numbers (supports any language)" in errors_on(
               changeset
             ).symbol
    end

    test "invalid when symbol is too long" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "VERYLONGSYMBOLMORETHANTWENTY",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      refute changeset.valid?
      assert "should be at most 20 character(s)" in errors_on(changeset).symbol
    end

    test "valid with single character symbol" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "X",
          exchange: "binance_spot",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      assert changeset.valid?
    end

    test "valid with alphanumeric symbol" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "BTC2",
          exchange: "binance_spot",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      assert changeset.valid?
    end

    test "valid with mixed case symbol" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "EtH",
          exchange: "binance_spot",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      assert changeset.valid?
    end

    test "valid with common crypto symbols" do
      symbols = ["BTC", "ETH", "SOL", "ADA", "MATIC", "USDT", "BNB", "XRP"]

      for symbol <- symbols do
        changeset =
          Position.create_changeset(%Position{}, %{
            symbol: symbol,
            exchange: "binance_spot",
            entry_price: 100,
            stop_loss_percent: -10,
            take_profit_percent: 20,
            current_threshold_zone: 5
          })

        assert changeset.valid?, "Expected #{symbol} to be valid"
      end
    end

    test "valid with Chinese characters" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "币安人生",
          exchange: "binance_spot",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      assert changeset.valid?
    end

    test "valid with mixed Chinese and alphanumeric characters" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "币安BTC123",
          exchange: "binance_spot",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      assert changeset.valid?
    end

    test "valid with Japanese characters" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "ビットコイン",
          exchange: "binance_spot",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      assert changeset.valid?
    end

    test "valid with Korean characters" do
      changeset =
        Position.create_changeset(%Position{}, %{
          symbol: "비트코인",
          exchange: "binance_spot",
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          current_threshold_zone: 5
        })

      assert changeset.valid?
    end
  end

  describe "highest_alert_zone_reached field" do
    test "can be set via changeset" do
      changeset =
        %Position{}
        |> Ecto.Changeset.cast(
          %{
            entry_price: 100,
            stop_loss_percent: -10,
            take_profit_percent: 20,
            highest_alert_zone_reached: Decimal.new("15.50")
          },
          [:entry_price, :stop_loss_percent, :take_profit_percent, :highest_alert_zone_reached]
        )

      assert changeset.valid?

      assert Decimal.eq?(
               Ecto.Changeset.get_change(changeset, :highest_alert_zone_reached),
               Decimal.new("15.50")
             )
    end

    test "is optional and can be nil" do
      changeset =
        %Position{}
        |> Position.changeset(%{
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :highest_alert_zone_reached) == nil
    end

    test "accepts negative values for tracking negative zones" do
      changeset =
        %Position{}
        |> Ecto.Changeset.cast(
          %{
            entry_price: 100,
            stop_loss_percent: -25,
            take_profit_percent: 20,
            highest_alert_zone_reached: Decimal.new("-22.50")
          },
          [:entry_price, :stop_loss_percent, :take_profit_percent, :highest_alert_zone_reached]
        )

      assert changeset.valid?

      assert Decimal.eq?(
               Ecto.Changeset.get_change(changeset, :highest_alert_zone_reached),
               Decimal.new("-22.50")
             )
    end
  end

  describe "amount_invested field" do
    test "accepts valid decimal amount_invested" do
      changeset =
        %Position{}
        |> Position.changeset(%{
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          amount_invested: Decimal.new("1000.50")
        })

      assert changeset.valid?

      assert Decimal.eq?(
               Ecto.Changeset.get_field(changeset, :amount_invested),
               Decimal.new("1000.50")
             )
    end

    test "accepts nil amount_invested (optional)" do
      changeset =
        %Position{}
        |> Position.changeset(%{
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :amount_invested) == nil
    end

    test "rejects zero amount_invested" do
      changeset =
        %Position{}
        |> Position.changeset(%{
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          amount_invested: 0
        })

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).amount_invested
    end

    test "rejects negative amount_invested" do
      changeset =
        %Position{}
        |> Position.changeset(%{
          entry_price: 100,
          stop_loss_percent: -10,
          take_profit_percent: 20,
          amount_invested: -500
        })

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).amount_invested
    end
  end
end
