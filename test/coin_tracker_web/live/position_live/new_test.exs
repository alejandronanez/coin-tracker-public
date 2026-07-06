defmodule CoinTrackerWeb.PositionLive.NewTest do
  use CoinTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import CoinTracker.AccountsFixtures
  import Mox

  alias CoinTracker.Coins.HTTPClientMock

  # Ensure mocks are verified after each test
  setup :verify_on_exit!

  describe "New Position LiveView" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders the new position form", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/positions/new")

      assert html =~ "New Position"
      assert html =~ "Create a new trading position"
      assert has_element?(view, "#position-form")
      assert has_element?(view, "input[name='position[symbol]']")
      assert has_element?(view, "input[name='position[entry_price]']")
      assert has_element?(view, "input[name='position[amount_invested]']")
      assert has_element?(view, "input[name='position[stop_loss_percent]']")
      assert has_element?(view, "input[name='position[take_profit_percent]']")
      assert has_element?(view, "button", "Create Position")
    end

    test "validates form on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/positions/new")

      # Submit invalid data - missing symbol
      # First change touches the form, second change shows validation errors
      form_element =
        form(view, "#position-form",
          position: %{
            symbol: "",
            entry_price: "-100",
            stop_loss_percent: "10",
            take_profit_percent: "-5"
          }
        )

      render_change(form_element)
      html = render_change(form_element)

      # Form should still be present (not redirected)
      assert has_element?(view, "#position-form")

      # Should show validation errors inline
      assert html =~ "can&#39;t be blank"
    end

    test "displays inline validation error for negative entry price", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/positions/new")

      # First change touches the form, second change shows validation errors
      form_element =
        form(view, "#position-form",
          position: %{
            symbol: "ETH",
            entry_price: "-100",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )

      render_change(form_element)
      html = render_change(form_element)

      assert html =~ "must be greater than 0"
      assert has_element?(view, "#position-form")
    end

    test "auto-converts positive stop loss to negative", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/positions/new")

      # Enter a positive value - it should auto-convert to negative
      form_element =
        form(view, "#position-form",
          position: %{
            symbol: "BTC",
            entry_price: "50000",
            stop_loss_percent: "10",
            take_profit_percent: "20"
          }
        )

      render_change(form_element)
      html = render_change(form_element)

      # No validation error should be shown since positive values auto-convert to negative
      refute html =~ "must be less than or equal to 0"
      # The form should show the converted negative value
      assert has_element?(view, "#position_stop_loss_percent[value=\"-10\"]")
      assert has_element?(view, "#position-form")
    end

    test "displays inline validation error for negative take profit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/positions/new")

      # First change touches the form, second change shows validation errors
      form_element =
        form(view, "#position-form",
          position: %{
            symbol: "SOL",
            entry_price: "100",
            stop_loss_percent: "-10",
            take_profit_percent: "-5"
          }
        )

      render_change(form_element)
      html = render_change(form_element)

      assert html =~ "must be greater than 0"
      assert has_element?(view, "#position-form")
    end

    test "creates position and redirects on success", %{conn: conn} do
      # Mock successful API response
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: [
             %{"symbol" => "ETHUSDT", "price" => "2000.00"}
           ]
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/positions/new")

      # Submit valid data
      view
      |> form("#position-form",
        position: %{
          symbol: "ETH",
          entry_price: "2000",
          stop_loss_percent: "-10",
          take_profit_percent: "20"
        }
      )
      |> render_submit()

      # Should redirect to positions index
      assert_redirected(view, ~p"/positions")

      # Verify flash message (would need to follow redirect to check)
    end

    test "displays inline error when API returns error", %{conn: conn} do
      # Mock API error
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 400,
           body: %{"code" => -1121, "msg" => "Invalid symbol."}
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/positions/new")

      html =
        view
        |> form("#position-form",
          position: %{
            symbol: "INVALID",
            entry_price: "2000",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )
        |> render_submit()

      # Should show error inline with the symbol field
      assert html =~ "Exchange API error: Invalid symbol."

      # Should NOT redirect (stays on form)
      assert has_element?(view, "#position-form")

      # Should NOT have flash error (error is inline)
      refute html =~ "API Error:"
    end

    test "displays inline error when network error occurs", %{conn: conn} do
      # Mock network error
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      {:ok, view, _html} = live(conn, ~p"/positions/new")

      html =
        view
        |> form("#position-form",
          position: %{
            symbol: "ETH",
            entry_price: "2000",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )
        |> render_submit()

      # Should show error inline with the symbol field
      assert html =~ "Network error. Please check your connection and try again."

      # Should NOT redirect
      assert has_element?(view, "#position-form")
    end

    test "displays inline error when no prices returned", %{conn: conn} do
      # Mock empty price response
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: []}}
      end)

      {:ok, view, _html} = live(conn, ~p"/positions/new")

      html =
        view
        |> form("#position-form",
          position: %{
            symbol: "UNKNOWN",
            entry_price: "1000",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )
        |> render_submit()

      # Should show error inline
      assert html =~ "No price data available for this symbol"

      # Should NOT redirect
      assert has_element?(view, "#position-form")
    end

    test "preserves form data when API error occurs", %{conn: conn} do
      # Mock API error
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 400,
           body: %{"code" => -1121, "msg" => "Invalid symbol."}
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/positions/new")

      html =
        view
        |> form("#position-form",
          position: %{
            symbol: "INVALID",
            entry_price: "2500",
            stop_loss_percent: "-15",
            take_profit_percent: "25"
          }
        )
        |> render_submit()

      # Form should still contain the entered values (symbol should preserve user input on error)
      assert html =~ "value=\"INVALID\""
      assert html =~ "value=\"2500\""
      assert html =~ "value=\"-15\""
      assert html =~ "value=\"25\""
    end

    test "form accepts lowercase symbols", %{conn: conn} do
      # Mock successful API response
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: [
             %{"symbol" => "BTCUSDT", "price" => "50000.00"}
           ]
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/positions/new")

      view
      |> form("#position-form",
        position: %{
          symbol: "btc",
          entry_price: "50000",
          stop_loss_percent: "-5",
          take_profit_percent: "15"
        }
      )
      |> render_submit()

      # Should redirect successfully
      assert_redirected(view, ~p"/positions")
    end

    test "form accepts alphanumeric symbols", %{conn: conn} do
      # Mock successful API response
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: [
             %{"symbol" => "BTC2USDT", "price" => "50000.00"}
           ]
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/positions/new")

      view
      |> form("#position-form",
        position: %{
          symbol: "BTC2",
          entry_price: "50000",
          stop_loss_percent: "-5",
          take_profit_percent: "15"
        }
      )
      |> render_submit()

      # Should redirect successfully
      assert_redirected(view, ~p"/positions")
    end

    test "displays validation error for invalid symbol characters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/positions/new")

      # First change touches the form, second change shows validation errors
      form_element =
        form(view, "#position-form",
          position: %{
            symbol: "BTC/USD",
            entry_price: "50000",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )

      render_change(form_element)
      html = render_change(form_element)

      assert html =~ "must contain only letters and numbers (supports any language)"
      assert has_element?(view, "#position-form")
    end

    test "accepts Chinese characters in symbol", %{conn: conn} do
      # Mock successful API response
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: [
             %{"symbol" => "币安人生USDT", "price" => "1.00"}
           ]
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/positions/new")

      view
      |> form("#position-form",
        position: %{
          symbol: "币安人生",
          entry_price: "1",
          stop_loss_percent: "-10",
          take_profit_percent: "20"
        }
      )
      |> render_submit()

      # Should redirect successfully
      assert_redirected(view, ~p"/positions")
    end

    test "creates position with amount_invested", %{conn: conn} do
      # Mock successful API response
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: [
             %{"symbol" => "ETHUSDT", "price" => "2000.00"}
           ]
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/positions/new")

      view
      |> form("#position-form",
        position: %{
          symbol: "ETH",
          entry_price: "2000",
          stop_loss_percent: "-10",
          take_profit_percent: "20",
          amount_invested: "1000.50"
        }
      )
      |> render_submit()

      # Should redirect to positions index
      assert_redirected(view, ~p"/positions")
    end

    test "creates position without amount_invested (optional)", %{conn: conn} do
      # Mock successful API response
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: [
             %{"symbol" => "BTCUSDT", "price" => "50000.00"}
           ]
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/positions/new")

      view
      |> form("#position-form",
        position: %{
          symbol: "BTC",
          entry_price: "50000",
          stop_loss_percent: "-10",
          take_profit_percent: "20",
          amount_invested: ""
        }
      )
      |> render_submit()

      # Should redirect to positions index
      assert_redirected(view, ~p"/positions")
    end

    test "preserves amount_invested on validation error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/positions/new")

      html =
        view
        |> form("#position-form",
          position: %{
            symbol: "",
            entry_price: "2000",
            stop_loss_percent: "-10",
            take_profit_percent: "20",
            amount_invested: "500.25"
          }
        )
        |> render_change()

      # Amount invested should be preserved
      assert html =~ "value=\"500.25\""
      assert has_element?(view, "#position-form")
    end
  end

  describe "Preview Feature" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "does not show preview card on initial load", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/positions/new")

      refute html =~ "Order Preview"
    end

    test "shows preview card when all required fields are filled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/positions/new")

      html =
        view
        |> form("#position-form",
          position: %{
            symbol: "ETH",
            entry_price: "2000",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )
        |> render_change()

      assert html =~ "Order Preview"
    end

    test "displays correct stop loss price in preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/positions/new")

      html =
        view
        |> form("#position-form",
          position: %{
            symbol: "BTC",
            entry_price: "50000",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )
        |> render_change()

      # $50000 * 0.9 = $45,000
      assert html =~ "$45,000"
      assert html =~ "Stop Loss Price"
    end

    test "displays correct take profit price in preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/positions/new")

      html =
        view
        |> form("#position-form",
          position: %{
            symbol: "BTC",
            entry_price: "50000",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )
        |> render_change()

      # $50000 * 1.2 = $60,000
      assert html =~ "$60,000"
      assert html =~ "Take Profit Price"
    end

    test "hides preview card when entry_price is cleared", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/positions/new")

      # First show the preview
      view
      |> form("#position-form",
        position: %{
          symbol: "ETH",
          entry_price: "2000",
          stop_loss_percent: "-10",
          take_profit_percent: "20"
        }
      )
      |> render_change()

      # Now clear entry price
      html =
        view
        |> form("#position-form",
          position: %{
            symbol: "ETH",
            entry_price: "",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )
        |> render_change()

      refute html =~ "Order Preview"
    end

    test "updates preview in real-time as values change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/positions/new")

      # Initial values
      html1 =
        view
        |> form("#position-form",
          position: %{
            symbol: "ETH",
            entry_price: "1000",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )
        |> render_change()

      assert html1 =~ "$900"
      assert html1 =~ "$1,200"

      # Change entry price
      html2 =
        view
        |> form("#position-form",
          position: %{
            symbol: "ETH",
            entry_price: "2000",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )
        |> render_change()

      assert html2 =~ "$1,800"
      assert html2 =~ "$2,400"
    end

    test "preview handles large crypto prices with commas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/positions/new")

      html =
        view
        |> form("#position-form",
          position: %{
            symbol: "BTC",
            entry_price: "97500",
            stop_loss_percent: "-5",
            take_profit_percent: "10"
          }
        )
        |> render_change()

      # $97500 * 0.95 = $92,625
      assert html =~ "$92,625"
      # $97500 * 1.10 = $107,250
      assert html =~ "$107,250"
    end
  end

  describe "Authentication" do
    test "redirects to login when not authenticated", %{conn: conn} do
      # Don't log in
      assert {:error, redirect} = live(conn, ~p"/positions/new")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
