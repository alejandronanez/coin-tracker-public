defmodule CoinTrackerWeb.BackpexResources.SignalResourceTest do
  use CoinTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import CoinTracker.AccountsFixtures
  import CoinTracker.SignalsFixtures

  alias CoinTracker.Signals

  describe "Admin signal editing" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      signal = signal_fixture()
      %{conn: log_in_user(conn, admin), signal: signal}
    end

    test "renders edit form for a signal", %{conn: conn, signal: signal} do
      {:ok, view, _html} = live(conn, ~p"/admin/signals/#{signal.id}/edit")

      assert has_element?(view, "#resource-form")
    end

    test "saves price_after_7d when submitted", %{conn: conn, signal: signal} do
      {:ok, view, _html} = live(conn, ~p"/admin/signals/#{signal.id}/edit")

      view
      |> form("#resource-form", change: %{price_after_7d: "1.23"})
      |> render_submit(%{"save-type" => "save"})

      updated = Signals.get_signal(signal.id)
      assert Decimal.equal?(updated.price_after_7d, Decimal.new("1.23"))
    end

    test "saves price_after_14d when submitted", %{conn: conn, signal: signal} do
      {:ok, view, _html} = live(conn, ~p"/admin/signals/#{signal.id}/edit")

      view
      |> form("#resource-form", change: %{price_after_14d: "2.50"})
      |> render_submit(%{"save-type" => "save"})

      updated = Signals.get_signal(signal.id)
      assert Decimal.equal?(updated.price_after_14d, Decimal.new("2.50"))
    end

    test "saves both price_after_7d and price_after_14d in a single submission", %{
      conn: conn,
      signal: signal
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/signals/#{signal.id}/edit")

      view
      |> form("#resource-form", change: %{price_after_7d: "3.14", price_after_14d: "6.28"})
      |> render_submit(%{"save-type" => "save"})

      updated = Signals.get_signal(signal.id)
      assert Decimal.equal?(updated.price_after_7d, Decimal.new("3.14"))
      assert Decimal.equal?(updated.price_after_14d, Decimal.new("6.28"))
    end

    test "can update price_after_7d from nil to a value and back to nil", %{
      conn: conn,
      signal: signal
    } do
      assert signal.price_after_7d == nil

      {:ok, view, _html} = live(conn, ~p"/admin/signals/#{signal.id}/edit")

      view
      |> form("#resource-form", change: %{price_after_7d: "5.00"})
      |> render_submit(%{"save-type" => "save"})

      assert Decimal.equal?(Signals.get_signal(signal.id).price_after_7d, Decimal.new("5.00"))

      {:ok, view, _html} = live(conn, ~p"/admin/signals/#{signal.id}/edit")

      view
      |> form("#resource-form", change: %{price_after_7d: ""})
      |> render_submit(%{"save-type" => "save"})

      assert Signals.get_signal(signal.id).price_after_7d == nil
    end
  end

  describe "Admin signal editing - access control" do
    test "redirects unauthenticated users to login", %{conn: conn} do
      signal = signal_fixture()

      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/signals/#{signal.id}/edit")
      assert path == ~p"/users/log-in"
    end

    test "redirects non-admin users away", %{conn: conn} do
      user = user_fixture()
      signal = signal_fixture()

      conn = log_in_user(conn, user)

      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/signals/#{signal.id}/edit")
    end

    test "redirects pro users away", %{conn: conn} do
      user = pro_user_fixture()
      signal = signal_fixture()

      conn = log_in_user(conn, user)

      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/signals/#{signal.id}/edit")
    end
  end
end
