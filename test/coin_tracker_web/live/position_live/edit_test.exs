defmodule CoinTrackerWeb.PositionLive.EditTest do
  use CoinTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import CoinTracker.AccountsFixtures
  import CoinTracker.TradingFixtures

  describe "Edit Position LiveView" do
    setup %{conn: conn} do
      user = user_fixture()
      position = position_fixture(user_id: user.id)
      %{conn: log_in_user(conn, user), user: user, position: position}
    end

    test "renders the edit position form with existing values", %{
      conn: conn,
      position: position
    } do
      {:ok, view, html} = live(conn, ~p"/positions/#{position.id}/edit")

      assert html =~ "Edit Position"
      assert html =~ "Update trading parameters"
      assert has_element?(view, "#position-form")

      # Check that read-only info is displayed
      assert html =~ position.symbol_price.symbol_pair
      assert html =~ "Binance"

      # Check that form fields exist
      assert has_element?(view, "input[name='position[entry_price]']")
      assert has_element?(view, "input[name='position[amount_invested]']")
      assert has_element?(view, "input[name='position[stop_loss_percent]']")
      assert has_element?(view, "input[name='position[take_profit_percent]']")
      assert has_element?(view, "button", "Update Position")

      # Verify existing values are pre-filled (trailing zeroes removed)
      assert html =~ "value=\"2000\""
      assert html =~ "value=\"-10\""
      assert html =~ "value=\"20\""
    end

    test "validates entry price on change", %{conn: conn, position: position} do
      {:ok, view, _html} = live(conn, ~p"/positions/#{position.id}/edit")

      # Submit invalid data - negative entry price
      html =
        view
        |> form("#position-form",
          position: %{
            entry_price: "-100",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )
        |> render_change()

      # Should show validation error for entry price
      assert html =~ "must be greater than 0"
      assert has_element?(view, "#position-form")
    end

    test "displays validation error when stop loss >= take profit", %{
      conn: conn,
      position: position
    } do
      {:ok, view, _html} = live(conn, ~p"/positions/#{position.id}/edit")

      html =
        view
        |> form("#position-form",
          position: %{
            entry_price: "2500",
            stop_loss_percent: "5",
            take_profit_percent: "5"
          }
        )
        |> render_change()

      assert html =~ "must be less than take profit percent"
      assert has_element?(view, "#position-form")
    end

    test "updates position and redirects on success", %{conn: conn, position: position} do
      {:ok, view, _html} = live(conn, ~p"/positions/#{position.id}/edit")

      # Submit valid data
      view
      |> form("#position-form",
        position: %{
          entry_price: "2500",
          stop_loss_percent: "-15",
          take_profit_percent: "25"
        }
      )
      |> render_submit()

      # Should redirect to positions index
      assert_redirected(view, ~p"/positions")

      # Verify the position was actually updated in the database
      {:ok, updated_position} =
        CoinTracker.Trading.get_position_for_user(position.id, position.user_id)

      assert Decimal.equal?(updated_position.entry_price, Decimal.new("2500"))
      assert Decimal.equal?(updated_position.stop_loss_percent, Decimal.new("-15"))
      assert Decimal.equal?(updated_position.take_profit_percent, Decimal.new("25"))
    end

    test "preserves form data when validation error occurs", %{conn: conn, position: position} do
      {:ok, view, _html} = live(conn, ~p"/positions/#{position.id}/edit")

      html =
        view
        |> form("#position-form",
          position: %{
            entry_price: "-100",
            stop_loss_percent: "-15",
            take_profit_percent: "25"
          }
        )
        |> render_change()

      # Form should still contain the entered values (even invalid ones)
      assert html =~ "value=\"-100\""
      assert html =~ "value=\"-15\""
      assert html =~ "value=\"25\""

      # Should NOT redirect
      assert has_element?(view, "#position-form")
    end

    test "accepts decimal values", %{conn: conn, position: position} do
      {:ok, view, _html} = live(conn, ~p"/positions/#{position.id}/edit")

      view
      |> form("#position-form",
        position: %{
          entry_price: "2500.55",
          stop_loss_percent: "-12.5",
          take_profit_percent: "18.75"
        }
      )
      |> render_submit()

      # Should redirect successfully
      assert_redirected(view, ~p"/positions")

      # Verify the position was updated with decimal values
      {:ok, updated_position} =
        CoinTracker.Trading.get_position_for_user(position.id, position.user_id)

      assert Decimal.equal?(updated_position.entry_price, Decimal.new("2500.55"))
      assert Decimal.equal?(updated_position.stop_loss_percent, Decimal.new("-12.5"))
      assert Decimal.equal?(updated_position.take_profit_percent, Decimal.new("18.75"))
    end

    test "redirects to index with error when position not found", %{conn: conn} do
      redirect_path = ~p"/positions"

      assert {:error,
              {:live_redirect, %{to: ^redirect_path, flash: %{"error" => "Position not found"}}}} =
               live(conn, ~p"/positions/99999/edit")
    end

    test "user cannot edit another user's position", %{conn: conn} do
      # Create another user and their position
      other_user = user_fixture()
      other_position = position_fixture(user_id: other_user.id)

      # Try to access the other user's position
      redirect_path = ~p"/positions"

      assert {:error,
              {:live_redirect, %{to: ^redirect_path, flash: %{"error" => "Position not found"}}}} =
               live(conn, ~p"/positions/#{other_position.id}/edit")
    end

    test "cancel link returns to positions index", %{conn: conn, position: position} do
      {:ok, view, _html} = live(conn, ~p"/positions/#{position.id}/edit")

      assert has_element?(view, "a[href='/positions']", "Cancel")
    end

    test "pre-fills amount_invested from existing position", %{conn: conn, user: user} do
      # Create a position with amount_invested
      position =
        position_fixture(user_id: user.id, amount_invested: Decimal.new("1500.75"))

      {:ok, _view, html} = live(conn, ~p"/positions/#{position.id}/edit")

      # Verify amount_invested is pre-filled
      assert html =~ "value=\"1500.75\""
    end

    test "updates position with new amount_invested", %{conn: conn, position: position} do
      {:ok, view, _html} = live(conn, ~p"/positions/#{position.id}/edit")

      view
      |> form("#position-form",
        position: %{
          entry_price: "2000",
          stop_loss_percent: "-10",
          take_profit_percent: "20",
          amount_invested: "2500.50"
        }
      )
      |> render_submit()

      assert_redirected(view, ~p"/positions")

      # Verify the position was updated with amount_invested
      {:ok, updated_position} =
        CoinTracker.Trading.get_position_for_user(position.id, position.user_id)

      assert Decimal.equal?(updated_position.amount_invested, Decimal.new("2500.50"))
    end

    test "clears amount_invested when field emptied", %{conn: conn, user: user} do
      # Create a position with amount_invested
      position =
        position_fixture(user_id: user.id, amount_invested: Decimal.new("1000"))

      {:ok, view, _html} = live(conn, ~p"/positions/#{position.id}/edit")

      view
      |> form("#position-form",
        position: %{
          entry_price: "2000",
          stop_loss_percent: "-10",
          take_profit_percent: "20",
          amount_invested: ""
        }
      )
      |> render_submit()

      assert_redirected(view, ~p"/positions")

      # Verify the amount_invested was cleared
      {:ok, updated_position} =
        CoinTracker.Trading.get_position_for_user(position.id, position.user_id)

      assert updated_position.amount_invested == nil
    end
  end

  describe "Preview Feature" do
    setup %{conn: conn} do
      user = user_fixture()
      position = position_fixture(user_id: user.id)
      %{conn: log_in_user(conn, user), user: user, position: position}
    end

    test "shows preview card on initial load with existing position data", %{
      conn: conn,
      position: position
    } do
      {:ok, _view, html} = live(conn, ~p"/positions/#{position.id}/edit")

      # Position fixture has entry_price: 2000, stop_loss: -10%, take_profit: 20%
      # Stop loss: $2000 * 0.9 = $1,800
      # Take profit: $2000 * 1.2 = $2,400
      assert html =~ "Order Preview"
      assert html =~ "$1,800"
      assert html =~ "$2,400"
    end

    test "updates preview when entry price changes", %{conn: conn, position: position} do
      {:ok, view, _html} = live(conn, ~p"/positions/#{position.id}/edit")

      html =
        view
        |> form("#position-form",
          position: %{
            entry_price: "3000",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )
        |> render_change()

      # $3000 * 0.9 = $2,700
      # $3000 * 1.2 = $3,600
      assert html =~ "$2,700"
      assert html =~ "$3,600"
    end

    test "updates preview when stop loss percent changes", %{conn: conn, position: position} do
      {:ok, view, _html} = live(conn, ~p"/positions/#{position.id}/edit")

      html =
        view
        |> form("#position-form",
          position: %{
            entry_price: "2000",
            stop_loss_percent: "-15",
            take_profit_percent: "20"
          }
        )
        |> render_change()

      # $2000 * 0.85 = $1,700
      assert html =~ "$1,700"
    end

    test "updates preview when take profit percent changes", %{conn: conn, position: position} do
      {:ok, view, _html} = live(conn, ~p"/positions/#{position.id}/edit")

      html =
        view
        |> form("#position-form",
          position: %{
            entry_price: "2000",
            stop_loss_percent: "-10",
            take_profit_percent: "30"
          }
        )
        |> render_change()

      # $2000 * 1.3 = $2,600
      assert html =~ "$2,600"
    end

    test "preview handles decimal entry prices", %{conn: conn, position: position} do
      {:ok, view, _html} = live(conn, ~p"/positions/#{position.id}/edit")

      html =
        view
        |> form("#position-form",
          position: %{
            entry_price: "1234.56",
            stop_loss_percent: "-10",
            take_profit_percent: "20"
          }
        )
        |> render_change()

      # $1234.56 * 0.9 = $1,111.104 -> rounds to $1,111.10
      assert html =~ "$1,111.10"
    end
  end

  describe "Authentication" do
    test "redirects to login when not authenticated", %{conn: conn} do
      user = user_fixture()
      position = position_fixture(user_id: user.id)

      # Don't log in
      assert {:error, redirect} = live(conn, ~p"/positions/#{position.id}/edit")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
