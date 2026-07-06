defmodule CoinTrackerWeb.PositionLive.IndexTest do
  use CoinTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import CoinTracker.AccountsFixtures

  alias CoinTracker.Repo
  alias CoinTracker.Trading.Position
  alias CoinTracker.Coins

  describe "Index" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "redirects if user is not logged in", %{conn: _conn} do
      conn = Phoenix.ConnTest.build_conn()
      {:error, {:redirect, redirect_info}} = live(conn, ~p"/positions")

      assert redirect_info.to == ~p"/users/log-in"
    end

    test "renders empty state when user has no positions", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/positions")

      assert html =~ "No active positions"
      assert html =~ "You don&#39;t have any active positions yet"
      assert html =~ "Create your first position to start tracking"
    end

    test "renders positions table when user has positions", %{conn: conn, user: user} do
      # Create symbol price and position
      symbol_price = create_symbol_price("ETHUSDT", :binance_spot, "2000.00")
      _position = create_position(user.id, symbol_price.id)

      {:ok, view, html} = live(conn, ~p"/positions")

      assert has_element?(view, "#positions-grid")
      assert html =~ "ETHUSDT"
      assert html =~ "Binance"
    end

    test "displays all position data correctly", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("BTCUSDT", :binance_spot, "50000.00")

      create_position(user.id, symbol_price.id, %{
        entry_price: "48000.00",
        stop_loss_percent: "-5",
        take_profit_percent: "10"
      })

      {:ok, view, html} = live(conn, ~p"/positions")

      # Check symbol and exchange
      assert html =~ "BTCUSDT"
      assert html =~ "Binance"

      # Check prices are displayed
      assert html =~ "48000"
      assert html =~ "50000"

      # Check take profit is displayed in the Target section
      assert view |> element("#positions-grid") |> render() =~ "10.00%"

      # Check P/L percentage is displayed (should be profit since current > entry)
      assert view |> element("#positions-grid") |> render() =~ "+4.17%"
    end

    test "renders projected PnL on Stop Loss / Take Profit when amount_invested is set",
         %{conn: conn, user: user} do
      symbol_price = create_symbol_price("DOTUSDT", :binance_spot, "5.00")

      create_position(user.id, symbol_price.id, %{
        entry_price: "5.00",
        stop_loss_percent: "-10",
        take_profit_percent: "20",
        amount_invested: "500"
      })

      {:ok, view, _html} = live(conn, ~p"/positions")

      assert view |> element("[data-role=stop-loss-projection]") |> render() =~ "-$50.00"
      assert view |> element("[data-role=take-profit-projection]") |> render() =~ "+$100.00"
    end

    test "renders the invested amount when amount_invested is set", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("AVAXUSDT", :binance_spot, "30.00")

      position =
        create_position(user.id, symbol_price.id, %{
          entry_price: "25.00",
          stop_loss_percent: "-10",
          take_profit_percent: "20",
          amount_invested: "750.25"
        })

      {:ok, view, _html} = live(conn, ~p"/positions")

      assert has_element?(
               view,
               "#position-card-#{position.id} [data-role=amount-invested]"
             )

      assert view
             |> element("#position-card-#{position.id} [data-role=amount-invested]")
             |> render() =~ "$750.25"
    end

    test "omits the invested amount when amount_invested is nil", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("ATOMUSDT", :binance_spot, "10.00")

      position =
        create_position(user.id, symbol_price.id, %{
          entry_price: "10.00",
          stop_loss_percent: "-10",
          take_profit_percent: "20"
        })

      {:ok, view, _html} = live(conn, ~p"/positions")

      assert has_element?(view, "#position-card-#{position.id}")

      refute has_element?(
               view,
               "#position-card-#{position.id} [data-role=amount-invested]"
             )
    end

    test "omits projected PnL when amount_invested is nil", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("LINKUSDT", :binance_spot, "10.00")

      create_position(user.id, symbol_price.id, %{
        entry_price: "10.00",
        stop_loss_percent: "-10",
        take_profit_percent: "20"
      })

      {:ok, view, _html} = live(conn, ~p"/positions")

      stop_loss = view |> element("[data-role=stop-loss-projection]") |> render()
      take_profit = view |> element("[data-role=take-profit-projection]") |> render()

      refute stop_loss =~ "$"
      refute take_profit =~ "$"
      assert stop_loss =~ "-10"
      assert take_profit =~ "+20"
    end

    test "displays P/L percentage with correct formatting", %{conn: conn, user: user} do
      # Create a profitable position
      symbol_price = create_symbol_price("SOLUSDT", :bitget_spot, "110.00")

      create_position(user.id, symbol_price.id, %{
        entry_price: "100.00",
        stop_loss_percent: "-10",
        take_profit_percent: "20"
      })

      {:ok, _view, html} = live(conn, ~p"/positions")

      # Should show +10% profit
      assert html =~ "+10"
    end

    test "displays negative P/L with correct formatting", %{conn: conn, user: user} do
      # Create a losing position
      symbol_price = create_symbol_price("ADAUSDT", :binance_spot, "0.45")

      create_position(user.id, symbol_price.id, %{
        entry_price: "0.50",
        stop_loss_percent: "-15",
        take_profit_percent: "25"
      })

      {:ok, _view, html} = live(conn, ~p"/positions")

      # Should show -10% loss
      assert html =~ "-10"
    end

    test "only shows active positions, not closed ones", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("XRPUSDT", :binance_spot, "0.60")
      active_pos = create_position(user.id, symbol_price.id, %{status: :active})
      closed_pos = create_position(user.id, symbol_price.id, %{status: :closed})

      {:ok, view, _html} = live(conn, ~p"/positions")

      # Check the active position IS visible
      assert has_element?(view, "#position-card-#{active_pos.id}")

      # Check the closed position is NOT visible (this actually tests what you want)
      refute has_element?(view, "#position-card-#{closed_pos.id}")
    end

    test "does not show other users' positions", %{conn: conn, user: user1} do
      user2 = user_fixture(%{email: "other@example.com"})
      symbol_price = create_symbol_price("DOGEUSDT", :binance_spot, "0.08")

      user1_pos = create_position(user1.id, symbol_price.id, %{status: :active})
      user2_pos = create_position(user2.id, symbol_price.id, %{status: :active})

      {:ok, view, _html} = live(conn, ~p"/positions")

      # Check user1's position IS visible
      assert has_element?(view, "#position-card-#{user1_pos.id}")

      # Check user2's position is NOT visible
      refute has_element?(view, "#position-card-#{user2_pos.id}")
    end

    test "displays multiple positions in correct order (newest first)", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("MATICUSDT", :bitget_spot, "0.75")

      # Create positions with different timestamps
      now = DateTime.utc_now()

      pos1 =
        create_position_with_timestamp(user.id, symbol_price.id, DateTime.add(now, -2, :hour))

      pos2 =
        create_position_with_timestamp(user.id, symbol_price.id, DateTime.add(now, -1, :hour))

      pos3 = create_position_with_timestamp(user.id, symbol_price.id, now)

      {:ok, view, _html} = live(conn, ~p"/positions")

      # Get all position cards
      grid_html =
        view
        |> element("#positions-grid")
        |> render()

      # The order should be pos3, pos2, pos1 (newest first)
      # Check that pos3 appears before pos2, and pos2 appears before pos1
      pos3_index = :binary.match(grid_html, "position-card-#{pos3.id}") |> elem(0)
      pos2_index = :binary.match(grid_html, "position-card-#{pos2.id}") |> elem(0)
      pos1_index = :binary.match(grid_html, "position-card-#{pos1.id}") |> elem(0)

      assert pos3_index < pos2_index
      assert pos2_index < pos1_index
    end

    test "has link to create new position", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/positions")

      assert has_element?(view, "a[href='/positions/new']")
    end

    test "has edit link for each position", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("ETHUSDT", :binance_spot, "2000.00")
      position = create_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions")

      assert has_element?(view, "a[href='/positions/#{position.id}/edit']", "Edit")
    end

    test "displays formatted datetime with LocalTime hook", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("LINKUSDT", :binance_spot, "15.00")
      position = create_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions")

      # Check for LocalTime hook element with datetime data attribute
      assert has_element?(view, "#position-#{position.id}-created[phx-hook='LocalTime']")
      assert has_element?(view, "#position-#{position.id}-created[data-format='datetime-short']")
    end
  end

  describe "Close position functionality" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "displays Close button for each position", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("ETHUSDT", :binance_spot, "2000.00")
      position = create_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions")

      assert has_element?(view, "#close-position-btn-#{position.id}")
    end

    test "Close button has confirmation dialog", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("BTCUSDT", :binance_spot, "50000.00")
      position = create_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions")

      button_html = view |> element("#close-position-btn-#{position.id}") |> render()
      assert button_html =~ "data-confirm"
      assert button_html =~ "Are you sure you want to close this position?"
    end

    test "closing position removes it from the active list", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("ETHUSDT", :binance_spot, "2000.00")
      position = create_position(user.id, symbol_price.id)

      {:ok, view, html} = live(conn, ~p"/positions")

      # Verify position is displayed
      assert html =~ "position-card-#{position.id}"

      # Close the position
      view |> element("#close-position-btn-#{position.id}") |> render_click()

      # Verify position is no longer displayed
      refute has_element?(view, "#position-card-#{position.id}")
    end

    test "displays success message after closing position", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("SOLUSDT", :binance_spot, "100.00")
      position = create_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions")

      # Close the position
      html = view |> element("#close-position-btn-#{position.id}") |> render_click()

      assert html =~ "Position closed successfully"
    end

    test "closing the last position shows empty state", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("ADAUSDT", :binance_spot, "0.50")
      position = create_position(user.id, symbol_price.id)

      {:ok, view, html} = live(conn, ~p"/positions")

      # Initially should not show empty state
      refute html =~ "No active positions"

      # Close the only position
      view |> element("#close-position-btn-#{position.id}") |> render_click()

      # Now should show empty state
      assert render(view) =~ "No active positions"
      assert render(view) =~ "You don&#39;t have any active positions yet"
    end

    test "closing one of multiple positions keeps others visible", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("BTCUSDT", :binance_spot, "50000.00")
      position1 = create_position(user.id, symbol_price.id)
      position2 = create_position(user.id, symbol_price.id)
      position3 = create_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions")

      # Close position2
      view |> element("#close-position-btn-#{position2.id}") |> render_click()

      # position1 and position3 should still be visible
      assert has_element?(view, "#position-card-#{position1.id}")
      refute has_element?(view, "#position-card-#{position2.id}")
      assert has_element?(view, "#position-card-#{position3.id}")
    end

    test "position is marked as closed in database", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("XRPUSDT", :binance_spot, "0.60")
      position = create_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions")

      # Close the position
      view |> element("#close-position-btn-#{position.id}") |> render_click()

      # Verify in database
      closed_position = Repo.get(Position, position.id)
      assert closed_position.status == :closed
      assert closed_position.closed_reason == "manual"
      assert closed_position.closed_at != nil
    end

    test "cannot close already closed position", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("DOGEUSDT", :binance_spot, "0.08")
      position = create_position(user.id, symbol_price.id, %{status: :closed})

      # Since closed positions don't show in the list, we need to manually trigger the event
      # This tests the error handling in the LiveView
      {:ok, view, _html} = live(conn, ~p"/positions")

      # Manually send the event as if someone tried to close a closed position
      # This simulates a race condition or stale UI state
      html = render_click(view, :close_position, %{"id" => to_string(position.id)})

      # Should show error message
      assert html =~ "already closed"
    end

    test "Close button has red styling", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("LINKUSDT", :binance_spot, "15.00")
      position = create_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions")

      button_html = view |> element("#close-position-btn-#{position.id}") |> render()
      assert button_html =~ "text-red-400"
    end

    test "position disappears from UI when closed automatically via stop_loss", %{
      conn: conn,
      user: user
    } do
      symbol_price = create_symbol_price("ETH/USDT", :binance_spot, "2000.00")
      position = create_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions")

      # Verify position is displayed
      assert has_element?(view, "#position-card-#{position.id}")

      # Simulate automatic closure (as PricePoller would do)
      position = Repo.preload(position, :symbol_price)
      {:ok, _closed} = CoinTracker.Trading.close_position(position, :stop_loss)

      # Position should disappear from UI via PubSub
      refute has_element?(view, "#position-card-#{position.id}")

      # Flash message should appear with symbol and reason
      assert render(view) =~ "ETH/USDT position closed"
      assert render(view) =~ "stop loss hit"
    end

    test "position disappears from UI when closed automatically via take_profit", %{
      conn: conn,
      user: user
    } do
      symbol_price = create_symbol_price("BTC/USDT", :binance_spot, "50000.00")
      position = create_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions")

      assert has_element?(view, "#position-card-#{position.id}")

      position = Repo.preload(position, :symbol_price)
      {:ok, _closed} = CoinTracker.Trading.close_position(position, :take_profit)

      refute has_element?(view, "#position-card-#{position.id}")
      assert render(view) =~ "BTC/USDT position closed"
      assert render(view) =~ "take profit hit"
    end
  end

  describe "watchlist row" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders :in_top status badge with rank when symbol is currently in top 10", %{
      conn: conn,
      user: user
    } do
      symbol_price = create_symbol_price("ETH/USDT", :binance_spot, "2000.00")

      _signal =
        CoinTracker.SignalsFixtures.signal_fixture(%{
          symbol: "ETH",
          in_top: true,
          active: true,
          position: 3
        })

      position =
        create_position(user.id, symbol_price.id, %{entry_price: "1900.00"})
        |> Ecto.Changeset.change(%{entry_rank: 5})
        |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/positions")

      assert has_element?(view, ~s(#watchlist-row-#{position.id}[data-status="in_top"]))

      badge_html =
        view |> element("#watchlist-row-#{position.id} [data-role=watchlist-status]") |> render()

      assert badge_html =~ "In top"
      assert badge_html =~ "#3"

      delta_html =
        view |> element("#watchlist-row-#{position.id} [data-role=rank-delta]") |> render()

      # entry_rank 5 -> current 3 = +2 improvement
      assert delta_html =~ "+2"
    end

    test "renders :dropped status badge when signal is in grace period", %{
      conn: conn,
      user: user
    } do
      symbol_price = create_symbol_price("DOGE/USDT", :binance_spot, "0.10")
      exit_at = DateTime.add(DateTime.utc_now(), -10, :minute) |> DateTime.truncate(:second)

      _signal =
        CoinTracker.SignalsFixtures.signal_fixture(%{
          symbol: "DOGE",
          in_top: false,
          active: true,
          position: nil,
          exit_date: exit_at
        })

      position = create_position(user.id, symbol_price.id, %{entry_price: "0.10"})

      {:ok, view, _html} = live(conn, ~p"/positions")

      assert has_element?(view, ~s(#watchlist-row-#{position.id}[data-status="dropped"]))

      badge_html =
        view |> element("#watchlist-row-#{position.id} [data-role=watchlist-status]") |> render()

      assert badge_html =~ "Grace period"
      assert badge_html =~ "dropped"
    end

    test "renders :exited badge when grace period has ended", %{
      conn: conn,
      user: user
    } do
      symbol_price = create_symbol_price("OLD/USDT", :binance_spot, "1.00")
      exit_at = DateTime.add(DateTime.utc_now(), -25, :hour) |> DateTime.truncate(:second)

      _signal =
        CoinTracker.SignalsFixtures.signal_fixture(%{
          symbol: "OLD",
          in_top: false,
          active: false,
          position: nil,
          exit_date: exit_at
        })

      position = create_position(user.id, symbol_price.id, %{entry_price: "1.00"})

      {:ok, view, _html} = live(conn, ~p"/positions")

      assert has_element?(view, ~s(#watchlist-row-#{position.id}[data-status="exited"]))

      badge_html =
        view |> element("#watchlist-row-#{position.id} [data-role=watchlist-status]") |> render()

      assert badge_html =~ "Exited"
      refute badge_html =~ "Out of top 10"
      refute badge_html =~ "grace ended"
    end

    test "renders :never_in_top badge for symbols never tracked as signals", %{
      conn: conn,
      user: user
    } do
      symbol_price = create_symbol_price("RANDOM/USDT", :binance_spot, "1.00")
      position = create_position(user.id, symbol_price.id, %{entry_price: "1.00"})

      {:ok, view, _html} = live(conn, ~p"/positions")

      assert has_element?(view, ~s(#watchlist-row-#{position.id}[data-status="never_in_top"]))

      badge_html =
        view |> element("#watchlist-row-#{position.id} [data-role=watchlist-status]") |> render()

      assert badge_html =~ "Never in top 10"
    end

    test "renders sparkline svg when there are 24h snapshots", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("ETH/USDT", :binance_spot, "2000.00")

      signal =
        CoinTracker.SignalsFixtures.signal_fixture(%{
          symbol: "ETH",
          in_top: true,
          active: true,
          position: 4
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for {minutes_ago, pos} <- [{60, 7}, {30, 5}, {0, 4}] do
        snapshot_at = DateTime.add(now, -minutes_ago, :minute) |> DateTime.truncate(:second)

        CoinTracker.SignalsFixtures.snapshot_fixture(signal, %{
          snapshot_at: snapshot_at,
          position: pos,
          in_top: true
        })
      end

      position = create_position(user.id, symbol_price.id, %{entry_price: "1900.00"})

      {:ok, view, _html} = live(conn, ~p"/positions")

      assert has_element?(view, "#watchlist-row-#{position.id} svg[data-role=sparkline]")
    end

    test "re-renders watchlist row when :signals_updated PubSub message arrives", %{
      conn: conn,
      user: user
    } do
      symbol_price = create_symbol_price("ETH/USDT", :binance_spot, "2000.00")

      CoinTracker.SignalsFixtures.signal_fixture(%{
        symbol: "ETH",
        in_top: true,
        active: true,
        position: 8
      })

      position =
        create_position(user.id, symbol_price.id, %{entry_price: "1900.00"})
        |> Ecto.Changeset.change(%{entry_rank: 8})
        |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/positions")

      delta_before =
        view |> element("#watchlist-row-#{position.id} [data-role=rank-delta]") |> render()

      # entry_rank 8 == current 8, delta = 0 -> rendered as em-dash
      assert delta_before =~ "—"

      # Simulate the signal moving up to rank 2 and broadcasting an update.
      Repo.update_all(CoinTracker.Signals.Signal,
        set: [position: 2, updated_at: DateTime.utc_now() |> DateTime.truncate(:second)]
      )

      send(view.pid, {:signals_updated, []})

      delta_after =
        view |> element("#watchlist-row-#{position.id} [data-role=rank-delta]") |> render()

      # entry_rank 8 -> current 2 = +6 improvement
      assert delta_after =~ "+6"
    end
  end

  describe "card layout (compact)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "Edit and Remove actions live inside the overflow menu", %{conn: conn, user: user} do
      symbol_price = create_symbol_price("ETH/USDT", :binance_spot, "2000.00")
      position = create_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions")

      # Menu container exists
      assert has_element?(view, "#position-menu-#{position.id}[data-role=position-menu]")

      # Both actions are still reachable inside the menu
      menu_html = view |> element("#position-menu-#{position.id}") |> render()
      assert menu_html =~ "Edit Position"
      assert menu_html =~ "Remove"
      assert menu_html =~ ~s(href="/positions/#{position.id}/edit")
      assert menu_html =~ ~s(id="close-position-btn-#{position.id}")
    end

    test "absolute creation timestamp is rendered inside View Details", %{
      conn: conn,
      user: user
    } do
      symbol_price = create_symbol_price("ETH/USDT", :binance_spot, "2000.00")
      position = create_position(user.id, symbol_price.id)

      {:ok, view, _html} = live(conn, ~p"/positions")

      # Element still exists (LocalTime hook is preserved)
      assert has_element?(view, "#position-#{position.id}-created[phx-hook='LocalTime']")
    end
  end

  # Helper functions for creating test data
  defp create_symbol_price(symbol_pair, exchange, price) do
    {:ok, symbol_price} =
      Coins.upsert_symbol_price(%{
        symbol_pair: symbol_pair,
        exchange: exchange,
        current_price: price
      })

    symbol_price
  end

  defp create_position(user_id, symbol_price_id, attrs \\ %{}) do
    default_attrs = %{
      entry_price: "1000.00",
      stop_loss_percent: "-10",
      take_profit_percent: "20"
    }

    # Extract status separately since it's not in the changeset cast
    status = Map.get(attrs, :status, :active)
    changeset_attrs = Map.delete(attrs, :status)
    merged_attrs = Map.merge(default_attrs, changeset_attrs)

    %Position{}
    |> Position.changeset(merged_attrs)
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> Ecto.Changeset.put_change(:symbol_price_id, symbol_price_id)
    |> Ecto.Changeset.put_change(:status, status)
    |> Repo.insert!()
  end

  defp create_position_with_timestamp(user_id, symbol_price_id, timestamp) do
    # Truncate to second precision as required by :utc_datetime
    truncated_timestamp = DateTime.truncate(timestamp, :second)

    %Position{}
    |> Position.changeset(%{
      entry_price: "1000.00",
      stop_loss_percent: "-10",
      take_profit_percent: "20"
    })
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> Ecto.Changeset.put_change(:symbol_price_id, symbol_price_id)
    |> Ecto.Changeset.put_change(:status, :active)
    |> Ecto.Changeset.put_change(:inserted_at, truncated_timestamp)
    |> Ecto.Changeset.put_change(:updated_at, truncated_timestamp)
    |> Repo.insert!()
  end
end
