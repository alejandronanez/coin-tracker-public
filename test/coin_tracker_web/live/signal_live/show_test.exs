defmodule CoinTrackerWeb.SignalLive.ShowTest do
  use CoinTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import CoinTracker.AccountsFixtures
  import CoinTracker.SignalsFixtures

  alias CoinTracker.Accounts

  describe "Performance Metrics (pro users)" do
    setup %{conn: conn} do
      user = user_fixture()

      {:ok, pro_user} =
        Accounts.activate_pro_subscription(
          user,
          DateTime.utc_now() |> DateTime.add(1, :day)
        )

      %{conn: log_in_user(conn, pro_user)}
    end

    test "displays performance metrics section with all KPIs", %{conn: conn} do
      signal =
        signal_fixture(%{
          in_top: true,
          position: 3,
          initial_price_usd: Decimal.new("1.00"),
          current_price_usd: Decimal.new("1.50"),
          initial_volume_24h: Decimal.new("1000000"),
          current_volume_24h: Decimal.new("1500000"),
          max_increase_percentage: Decimal.new("75.00")
        })

      # Create snapshots with varying positions
      snapshot_fixture(signal, %{position: 5, in_top: true})
      snapshot_fixture(signal, %{position: 2, in_top: true})
      snapshot_fixture(signal, %{position: 3, in_top: true})

      {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}")

      # Check section exists
      assert has_element?(view, "h2", "Performance Metrics")

      # Check all metric labels are displayed
      assert render(view) =~ "Time in Top"
      assert render(view) =~ "Best Position"
      assert render(view) =~ "Price Performance"
      assert render(view) =~ "Volume Growth"
      assert render(view) =~ "Peak Gain"

      # Check Best Position shows #2 (minimum from snapshots)
      assert render(view) =~ "#2"

      # Check Peak Gain shows the max_increase_percentage
      assert render(view) =~ "+75"
    end

    test "calculates best position from snapshots correctly", %{conn: conn} do
      signal = signal_fixture(%{in_top: true, position: 5})

      # Create snapshots: positions 5, 3, 1, 4
      snapshot_fixture(signal, %{position: 5, in_top: true})
      snapshot_fixture(signal, %{position: 3, in_top: true})
      # Best position
      snapshot_fixture(signal, %{position: 1, in_top: true})
      snapshot_fixture(signal, %{position: 4, in_top: true})

      {:ok, _view, html} = live(conn, ~p"/signals/#{signal.id}")

      # Best position should be #1
      assert html =~ "#1"
    end

    test "ignores out-of-top positions when calculating best position", %{conn: conn} do
      signal = signal_fixture(%{in_top: true, position: 5})

      snapshot_fixture(signal, %{position: 5, in_top: true})
      # Out of top
      snapshot_fixture(signal, %{position: nil, in_top: false})
      snapshot_fixture(signal, %{position: 3, in_top: true})

      {:ok, _view, html} = live(conn, ~p"/signals/#{signal.id}")

      # Best position should be #3, ignoring out-of-top snapshots
      assert html =~ "#3"
    end

    test "displays price performance correctly", %{conn: conn} do
      # 50% increase from initial price
      signal =
        signal_fixture(%{
          in_top: true,
          position: 1,
          initial_price_usd: Decimal.new("100.00"),
          current_price_usd: Decimal.new("150.00")
        })

      # Create at least one snapshot so the page shows metrics
      snapshot_fixture(signal, %{position: 1, in_top: true})

      {:ok, _view, html} = live(conn, ~p"/signals/#{signal.id}")

      # Should show +50.0%
      assert html =~ "+50"
    end

    test "displays volume growth correctly", %{conn: conn} do
      # 50% volume increase
      signal =
        signal_fixture(%{
          in_top: true,
          position: 1,
          initial_volume_24h: Decimal.new("1000000"),
          current_volume_24h: Decimal.new("1500000")
        })

      snapshot_fixture(signal, %{position: 1, in_top: true})

      {:ok, _view, html} = live(conn, ~p"/signals/#{signal.id}")

      # Should show +50% volume growth
      assert html =~ "+50"
    end

    test "handles zero initial price gracefully", %{conn: conn} do
      # Edge case: initial price is zero (division by zero)
      signal =
        signal_fixture(%{
          in_top: true,
          position: 1,
          initial_price_usd: Decimal.new("0"),
          current_price_usd: Decimal.new("1.50")
        })

      snapshot_fixture(signal, %{position: 1, in_top: true})

      {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}")

      # Should show N/A for price performance, not crash
      assert has_element?(view, "h2", "Performance Metrics")
    end

    test "handles nil initial price gracefully", %{conn: conn} do
      signal =
        signal_fixture(%{
          in_top: true,
          position: 1,
          initial_price_usd: nil,
          current_price_usd: Decimal.new("1.50")
        })

      snapshot_fixture(signal, %{position: 1, in_top: true})

      {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}")

      # Should show N/A for price performance, not crash
      assert has_element?(view, "h2", "Performance Metrics")
    end
  end

  describe "Price card (pro users)" do
    setup %{conn: conn} do
      user = user_fixture()

      {:ok, pro_user} =
        Accounts.activate_pro_subscription(
          user,
          DateTime.utc_now() |> DateTime.add(1, :day)
        )

      %{conn: log_in_user(conn, pro_user)}
    end

    test "displays entry price and current price side by side", %{conn: conn} do
      signal =
        signal_fixture(%{
          in_top: true,
          position: 1,
          initial_price_usd: Decimal.new("1.23"),
          current_price_usd: Decimal.new("4.56")
        })

      {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}")

      assert has_element?(view, "#price-card-#{signal.id}")
      assert has_element?(view, "#entry-price-#{signal.id}", "$1.23")
      assert has_element?(view, "#current-price-#{signal.id}", "$4.56")
    end

    test "renders N/A when prices are missing", %{conn: conn} do
      signal =
        signal_fixture(%{
          in_top: true,
          position: 1,
          initial_price_usd: nil,
          current_price_usd: nil
        })

      {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}")

      assert has_element?(view, "#entry-price-#{signal.id}", "N/A")
      assert has_element?(view, "#current-price-#{signal.id}", "N/A")
    end
  end

  describe "Performance Metrics (free users)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user)}
    end

    test "redirects free users to upgrade page", %{conn: conn} do
      signal = signal_fixture(%{in_top: true, position: 3})
      snapshot_fixture(signal, %{position: 3, in_top: true})

      # Free users cannot access signal detail page - they are redirected to upgrade
      assert {:error, {:redirect, %{to: "/upgrade"}}} = live(conn, ~p"/signals/#{signal.id}")
    end
  end

  describe "Previous occurrences panel" do
    setup %{conn: conn} do
      user = user_fixture()

      {:ok, pro_user} =
        Accounts.activate_pro_subscription(
          user,
          DateTime.utc_now() |> DateTime.add(1, :day)
        )

      %{conn: log_in_user(conn, pro_user), user: pro_user}
    end

    test "panel renders with empty state when no prior occurrences exist", %{conn: conn} do
      signal = signal_fixture(%{symbol: "ONLYONE", in_top: true, position: 1})

      {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}")

      assert has_element?(view, "#previous-occurrences-panel")
      assert has_element?(view, "#previous-occurrences-empty")
    end

    test "lists prior occurrences for the same symbol and excludes the current", %{conn: conn} do
      base = ~U[2025-01-01 00:00:00Z]

      past1 =
        signal_fixture(%{
          symbol: "REPEAT",
          in_top_since: DateTime.add(base, -2, :day),
          exit_date: DateTime.add(base, -1, :day),
          initial_price_usd: Decimal.new("1.00"),
          current_price_usd: Decimal.new("1.20")
        })

      past2 =
        signal_fixture(%{
          symbol: "REPEAT",
          in_top_since: DateTime.add(base, -5, :day),
          exit_date: DateTime.add(base, -4, :day),
          initial_price_usd: Decimal.new("0.80"),
          current_price_usd: Decimal.new("0.95")
        })

      snapshot_fixture(past1, %{position: 2, in_top: true})
      snapshot_fixture(past2, %{position: 5, in_top: true})

      current =
        signal_fixture(%{
          symbol: "REPEAT",
          in_top_since: base,
          in_top: true,
          position: 1
        })

      {:ok, view, _html} = live(conn, ~p"/signals/#{current.id}")

      assert has_element?(view, "#previous-occurrences-panel")
      assert has_element?(view, "#occurrence-#{past1.id}")
      assert has_element?(view, "#occurrence-#{past2.id}")
      refute has_element?(view, "#occurrence-#{current.id}")
      refute has_element?(view, "#previous-occurrences-empty")
    end

    test "renders entry, top (with percentage) and exit prices for an occurrence", %{conn: conn} do
      base = ~U[2025-01-01 00:00:00Z]

      past =
        signal_fixture(%{
          symbol: "TOPPY",
          in_top_since: DateTime.add(base, -2, :day),
          exit_date: DateTime.add(base, -1, :day),
          initial_price_usd: Decimal.new("1.00"),
          current_price_usd: Decimal.new("1.20"),
          max_price_usd: Decimal.new("1.50")
        })

      current =
        signal_fixture(%{
          symbol: "TOPPY",
          in_top_since: base,
          in_top: true,
          position: 1
        })

      {:ok, view, _html} = live(conn, ~p"/signals/#{current.id}")

      assert has_element?(view, "#occurrence-#{past.id}")

      occurrence_html =
        view
        |> element("#occurrence-#{past.id}")
        |> render()

      # Entry price $1.00, top price $1.50 (+50%), exit price $1.20
      assert occurrence_html =~ "Entry"
      assert occurrence_html =~ "Top"
      assert occurrence_html =~ "Exit"
      assert occurrence_html =~ "$1.00"
      assert occurrence_html =~ "$1.50"
      assert occurrence_html =~ "$1.20"
      assert occurrence_html =~ "+50.00%"
    end

    test "shows 'show more' button and expands when clicked", %{conn: conn} do
      base = ~U[2025-01-01 00:00:00Z]

      # 7 prior occurrences — more than the default limit of 5
      priors =
        for i <- 1..7 do
          signal_fixture(%{
            symbol: "MANYTIMES",
            in_top_since: DateTime.add(base, -i, :day),
            exit_date: DateTime.add(base, -i, :hour),
            initial_price_usd: Decimal.new("1.00"),
            current_price_usd: Decimal.new("1.10")
          })
        end

      current = signal_fixture(%{symbol: "MANYTIMES", in_top_since: base})

      {:ok, view, _html} = live(conn, ~p"/signals/#{current.id}")

      # By default only the 5 most recent are shown (descending by in_top_since)
      # The 5 most recent = priors with i = 1..5 (smaller i means more recent)
      most_recent = Enum.take(priors, 5)
      oldest = Enum.drop(priors, 5)

      for signal <- most_recent do
        assert has_element?(view, "#occurrence-#{signal.id}")
      end

      for signal <- oldest do
        refute has_element?(view, "#occurrence-#{signal.id}")
      end

      # Show more button exists and clicking it expands the list
      assert has_element?(view, "#toggle-occurrences-btn")

      view
      |> element("#toggle-occurrences-btn")
      |> render_click()

      for signal <- priors do
        assert has_element?(view, "#occurrence-#{signal.id}")
      end
    end
  end
end
