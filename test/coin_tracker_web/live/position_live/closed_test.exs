defmodule CoinTrackerWeb.PositionLive.ClosedTest do
  use CoinTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import CoinTracker.AccountsFixtures

  alias CoinTracker.Coins
  alias CoinTracker.Repo
  alias CoinTracker.Trading.Position

  describe "Closed Positions" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders empty state with no closed positions", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/positions/closed")
      assert html =~ "No closed positions"
    end

    test "renders rows for closed positions", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("ETH/USDT", :binance_spot, "2000.00")
      position = create_closed_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions/closed")
      assert has_element?(view, "#closed-position-row-#{position.id}")
    end

    test "remove CTA is present for each row on desktop and mobile", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("BTC/USDT", :binance_spot, "50000.00")
      position = create_closed_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions/closed")
      assert has_element?(view, "#closed-position-#{position.id}-remove")
      assert has_element?(view, "#closed-position-mobile-#{position.id}-remove")
    end

    test "clicking remove deletes the position and updates the list", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("ETH/USDT", :binance_spot, "2000.00")
      position = create_closed_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions/closed")

      view
      |> element("#closed-position-#{position.id}-remove")
      |> render_click()

      refute has_element?(view, "#closed-position-row-#{position.id}")
      assert is_nil(Repo.get(Position, position.id))
    end
  end

  defp create_symbol_price(symbol_pair, exchange, price) do
    {:ok, symbol_price} =
      Coins.upsert_symbol_price(%{
        symbol_pair: symbol_pair,
        exchange: exchange,
        current_price: price
      })

    symbol_price
  end

  defp create_closed_position(user_id, symbol_price_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Position{}
    |> Position.changeset(%{
      entry_price: "1000.00",
      stop_loss_percent: "-10",
      take_profit_percent: "20"
    })
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> Ecto.Changeset.put_change(:symbol_price_id, symbol_price_id)
    |> Ecto.Changeset.put_change(:status, :closed)
    |> Ecto.Changeset.put_change(:closed_reason, "manual")
    |> Ecto.Changeset.put_change(:closed_at, now)
    |> Ecto.Changeset.put_change(:exit_price, Decimal.new("1100.00"))
    |> Repo.insert!()
  end
end
