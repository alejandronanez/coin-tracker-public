defmodule CoinTrackerWeb.UpgradeLiveTest do
  use CoinTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import CoinTracker.AccountsFixtures

  describe "upgrade page placeholder" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders placeholder page without payment details", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/upgrade")

      assert html =~ "Pricing"
      assert html =~ "not configured in this build"
      refute html =~ "USDT"
      refute html =~ "TRC-20"
      refute html =~ "wallet"
      refute html =~ "$50"
    end

    test "upgrade/payment route no longer exists", %{conn: conn} do
      assert_raise Phoenix.Router.NoRouteError, fn ->
        live(conn, ~p"/upgrade/payment")
      end
    end

    test "upgrade/pending route no longer exists", %{conn: conn} do
      assert_raise Phoenix.Router.NoRouteError, fn ->
        live(conn, ~p"/upgrade/pending")
      end
    end
  end
end
