defmodule CoinTrackerWeb.SettingsLive.ExchangeKeysTest do
  use CoinTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import CoinTracker.AccountsFixtures

  describe "ExchangeKeys" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders page with empty form when no credentials", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/settings/exchange-keys")

      assert html =~ "Exchange API Keys"
      assert has_element?(view, "#credential-form")
      assert html =~ "Binance API Key Setup Guide"
    end

    test "renders existing credentials masked", %{conn: conn, user: user} do
      _cred = exchange_credential_fixture(user, %{"label" => "Main"})

      {:ok, view, html} = live(conn, ~p"/settings/exchange-keys")

      assert html =~ "Binance Spot"
      assert html =~ "Main"
      # Form should be hidden when credentials exist
      refute has_element?(view, "#credential-form")
      # Add button should show
      assert has_element?(view, "#add-credential-btn")
    end

    test "add credential flow", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/exchange-keys")

      # Submit the form
      view
      |> form("#credential-form", %{
        "exchange_credential" => %{
          "exchange" => "binance_spot",
          "api_key" => "test_api_key_12345678",
          "api_secret" => "test_api_secret_12345678"
        }
      })
      |> render_submit()

      assert render(view) =~ "Credential saved successfully"
      assert render(view) =~ "Binance Spot"
    end

    test "delete credential flow", %{conn: conn, user: user} do
      cred = exchange_credential_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/settings/exchange-keys")

      # Click delete - shows confirmation
      view |> element("#delete-#{cred.id}") |> render_click()
      assert has_element?(view, "#confirm-delete-#{cred.id}")

      # Confirm delete
      view |> element("#confirm-delete-#{cred.id}") |> render_click()
      assert render(view) =~ "Credential removed"
    end

    test "validation errors on invalid input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/exchange-keys")

      view
      |> form("#credential-form", %{
        "exchange_credential" => %{
          "exchange" => "binance_spot",
          "api_key" => "short",
          "api_secret" => "short"
        }
      })
      |> render_change()

      html = render(view)
      assert html =~ "should be at least 8 character"
    end

    test "redirects if user is not logged in" do
      conn = Phoenix.ConnTest.build_conn()
      {:error, {:redirect, redirect_info}} = live(conn, ~p"/settings/exchange-keys")
      assert redirect_info.to == ~p"/users/log-in"
    end
  end
end
