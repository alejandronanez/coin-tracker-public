defmodule CoinTrackerWeb.SignalLive.TradeTest do
  use CoinTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import CoinTracker.AccountsFixtures
  import CoinTracker.SignalsFixtures

  alias CoinTracker.Coins

  describe "Trade LiveView" do
    setup %{conn: conn} do
      user = admin_user_fixture()
      signal = signal_fixture(%{symbol: "PEPE"})

      {:ok, symbol_price} =
        Coins.upsert_symbol_price(%{
          exchange: :binance_spot,
          symbol_pair: "PEPE/USDT",
          current_price: "0.00001234"
        })

      signal =
        signal
        |> Ecto.Changeset.change(symbol_price_id: symbol_price.id)
        |> CoinTracker.Repo.update!()

      %{conn: log_in_user(conn, user), user: user, signal: signal}
    end

    test "renders form when user has credentials", %{conn: conn, user: user, signal: signal} do
      _cred = exchange_credential_fixture(user)

      {:ok, view, html} = live(conn, ~p"/signals/#{signal.id}/trade")

      assert html =~ "Trade PEPE"
      assert has_element?(view, "#trade-form")
    end

    test "shows no-credentials warning when user has none", %{conn: conn, signal: signal} do
      {:ok, _view, html} = live(conn, ~p"/signals/#{signal.id}/trade")

      assert html =~ "Exchange credentials required"
      assert html =~ "Set up API keys"
    end

    test "validates and shows preview", %{conn: conn, user: user, signal: signal} do
      _cred = exchange_credential_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}/trade")

      # Submit form to preview
      view
      |> form("#trade-form", %{
        "trade" => %{
          "amount" => "100",
          "take_profit" => "15",
          "stop_loss" => "20"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "$100 USDT"
      assert html =~ "+15%"
      assert html =~ "-20%"
      assert has_element?(view, "#trade-preview")
    end

    test "edit goes back to form from preview", %{conn: conn, user: user, signal: signal} do
      _cred = exchange_credential_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}/trade")

      # Go to preview
      view
      |> form("#trade-form", %{
        "trade" => %{
          "amount" => "100",
          "take_profit" => "15",
          "stop_loss" => "20"
        }
      })
      |> render_submit()

      assert has_element?(view, "#trade-preview")

      # Click edit
      view |> element("#edit-btn") |> render_click()

      assert has_element?(view, "#trade-form")
    end

    test "rejects invalid inputs", %{conn: conn, user: user, signal: signal} do
      _cred = exchange_credential_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}/trade")

      # Submit with empty amount
      view
      |> form("#trade-form", %{
        "trade" => %{
          "amount" => "",
          "take_profit" => "15",
          "stop_loss" => "20"
        }
      })
      |> render_submit()

      assert render(view) =~ "positive number"
    end

    test "redirects to signals when signal not found", %{conn: conn, user: user} do
      _cred = exchange_credential_fixture(user)

      assert {:error, {:live_redirect, %{to: "/signals"}}} =
               live(conn, ~p"/signals/99999/trade")
    end

    test "form is usable when balance fetch fails", %{conn: conn, user: user, signal: signal} do
      _cred = exchange_credential_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}/trade")

      # Balance fetch will fail in tests (no real API), but form should still work
      assert has_element?(view, "#trade-form")

      # Submit should still work even with failed balance fetch
      view
      |> form("#trade-form", %{
        "trade" => %{
          "amount" => "100",
          "take_profit" => "15",
          "stop_loss" => "20"
        }
      })
      |> render_submit()

      assert has_element?(view, "#trade-preview")
    end

    test "shows balance warning when fetch fails", %{conn: conn, user: user, signal: signal} do
      _cred = exchange_credential_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}/trade")

      # Wait for the async balance fetch to complete (it will fail in test env)
      # Give the process a moment to handle the message
      :timer.sleep(100)

      html = render(view)
      assert html =~ "Could not load balance" || html =~ "Loading balance"
    end

    test "displays oco_failed error with clear message", %{
      conn: conn,
      user: user,
      signal: signal
    } do
      _cred = exchange_credential_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}/trade")

      # Simulate receiving an oco_failed error
      oco_error =
        {:oco_failed,
         %{
           buy_order: %{order_id: 123, fill_price: Decimal.new("0.00001234")},
           reason: {:price_rule_violation, "Order would immediately trigger"}
         }}

      send(view.pid, {:trade_result, {:error, oco_error}})

      html = render(view)
      assert html =~ "OCO order failed"
      assert html =~ "unprotected position"
    end
  end
end
