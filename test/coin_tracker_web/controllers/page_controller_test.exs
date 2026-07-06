defmodule CoinTrackerWeb.PageControllerTest do
  use CoinTrackerWeb.ConnCase

  describe "GET / (logged out)" do
    test "shows landing page for logged-out users", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert html_response(conn, 200) =~ "Know when to buy. Know when to sell."
    end

    test "displays features section", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert html_response(conn, 200) =~ "Everything you need to trade smarter"
    end
  end

  describe "GET / (logged in)" do
    setup :register_and_log_in_user

    test "redirects logged-in users to /signals", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert redirected_to(conn) == ~p"/signals"
    end
  end
end
