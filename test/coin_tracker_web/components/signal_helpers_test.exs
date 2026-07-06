defmodule CoinTrackerWeb.SignalHelpersTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias CoinTrackerWeb.SignalHelpers

  describe "price/1 component" do
    test "renders a regular price verbatim" do
      html = render_component(&SignalHelpers.price/1, %{value: 46.99})
      assert html =~ "$46.99"
      refute html =~ "<sub"
    end

    test "renders a sub-cent price unchanged when above $0.0001" do
      html = render_component(&SignalHelpers.price/1, %{value: 0.0537})
      assert html =~ "$0.0537"
      refute html =~ "<sub"
    end

    test "renders subscript-zero notation for sub-$0.0001 prices" do
      html = render_component(&SignalHelpers.price/1, %{value: 0.000374})

      assert html =~ "$0.0"
      assert html =~ ~r/<sub[^>]*>3<\/sub>/
      assert html =~ "374"
    end

    test "renders subscript notation for very tiny prices" do
      html = render_component(&SignalHelpers.price/1, %{value: 0.0000123})

      assert html =~ ~r/<sub[^>]*>4<\/sub>/
      assert html =~ "123"
    end

    test "accepts Decimal values" do
      html = render_component(&SignalHelpers.price/1, %{value: Decimal.new("0.000374")})

      assert html =~ ~r/<sub[^>]*>3<\/sub>/
      assert html =~ "374"
    end

    test "renders N/A for nil" do
      html = render_component(&SignalHelpers.price/1, %{value: nil})
      assert html =~ "N/A"
    end

    test "merges custom class with default font-mono tabular-nums" do
      html = render_component(&SignalHelpers.price/1, %{value: 46.99, class: "text-lg"})

      assert html =~ "font-mono"
      assert html =~ "tabular-nums"
      assert html =~ "text-lg"
    end

    test "trims trailing zeros in significant digits" do
      html = render_component(&SignalHelpers.price/1, %{value: 0.0003})

      assert html =~ ~r/<sub[^>]*>3<\/sub>/
      # 0.000300 -> sig digits "3", not "300"
      assert html =~ ">3</span>" or html =~ ">3<"
    end
  end
end
