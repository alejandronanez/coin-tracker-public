defmodule CoinTrackerWeb.SignalLive.IndexTest do
  use CoinTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import CoinTracker.AccountsFixtures

  alias CoinTracker.Accounts
  alias CoinTracker.Repo
  alias CoinTracker.Signals.Signal
  alias Decimal

  setup %{conn: conn} do
    user = user_fixture()

    {:ok, pro_user} =
      Accounts.activate_pro_subscription(
        user,
        DateTime.utc_now()
        |> DateTime.add(1, :day)
      )

    %{conn: log_in_user(conn, pro_user)}
  end

  test "renders N/A for volume change when volume tracking is disabled", %{conn: conn} do
    insert_signal_with_zero_volume()

    {:ok, _view, html} = live(conn, ~p"/signals")

    assert html =~ "Volume Change"
    assert html =~ "N/A"
  end

  describe "signal watchlist (admin sees flag enabled)" do
    test "renders Watch button on top performer rows" do
      admin = admin_user_fixture()
      conn = build_conn() |> log_in_user(admin)

      signal = insert_top_signal("WCH")

      {:ok, view, _html} = live(conn, ~p"/signals")

      assert has_element?(view, "#signal-#{signal.id}-watch-toggle")
      refute has_element?(view, "#watched-entry-#{signal.id}")
    end

    test "toggle creates a watched position and re-renders as Watching" do
      admin = admin_user_fixture()
      conn = build_conn() |> log_in_user(admin)

      signal = insert_top_signal("WCH")

      {:ok, view, _html} = live(conn, ~p"/signals")

      view
      |> element("#signal-#{signal.id}-watch-toggle")
      |> render_click()

      # After toggle: button now shows "Watching" with filled star.
      html = render(view)
      assert html =~ "Watching"

      # Watched tab badge appears.
      assert has_element?(view, "#signals-tab-watched")
    end

    test "Watched tab lists the user's watches" do
      admin = admin_user_fixture()
      conn = build_conn() |> log_in_user(admin)

      signal = insert_top_signal("WCH")

      {:ok, view, _html} = live(conn, "/signals?tab=watched")

      # Empty state when no watches.
      assert render(view) =~ "Nothing watched yet"

      # Switch to top tab, watch the signal, switch back.
      {:ok, view, _html} = live(conn, ~p"/signals")

      view
      |> element("#signal-#{signal.id}-watch-toggle")
      |> render_click()

      {:ok, view, _html} = live(conn, "/signals?tab=watched")

      assert has_element?(view, "#watched-signals")
      assert render(view) =~ "WCH"
    end

    test "second click on toggle removes the watch" do
      admin = admin_user_fixture()
      conn = build_conn() |> log_in_user(admin)

      signal = insert_top_signal("WCH")

      {:ok, view, _html} = live(conn, ~p"/signals")

      view
      |> element("#signal-#{signal.id}-watch-toggle")
      |> render_click()

      view
      |> element("#signal-#{signal.id}-watch-toggle")
      |> render_click()

      assert CoinTracker.Trading.list_watched_positions_for_user(admin.id) == []
    end
  end

  describe "24h Market column" do
    test "shows the column header on the desktop top-performers table", %{conn: conn} do
      insert_top_signal("CGM")

      {:ok, _view, html} = live(conn, ~p"/signals")
      assert html =~ "24h Market"
    end

    test "renders the price change value when a snapshot exists for the signal", %{conn: conn} do
      signal = insert_top_signal_with_coingecko("CGOK", "test-cgok")

      {:ok, _} =
        CoinTracker.Signals.create_coingecko_snapshot(%{
          coingecko_id: "test-cgok",
          symbol: "CGOK",
          snapshot_at: ~U[2026-05-17 12:00:00Z],
          price_change_percentage_24h: Decimal.new("4.2")
        })

      {:ok, view, _html} = live(conn, ~p"/signals")
      html = render(view)

      assert has_element?(view, "#top-performer-24h-market-#{signal.id}")
      assert html =~ "+4.2%"
    end

    test "renders muted placeholder when signal has no coingecko_id", %{conn: conn} do
      signal = insert_top_signal("NOID")

      {:ok, view, _html} = live(conn, ~p"/signals")
      cell = element(view, "#top-performer-24h-market-#{signal.id}")

      cell_html = render(cell)
      # Both lines should fall back to the em-dash placeholder.
      # 'Vol —' on line 1 and 'Price —' on line 2.
      assert cell_html =~ "Vol"
      assert cell_html =~ "Price"
      assert cell_html =~ "—"
    end

    test "renders computed 24h volume change when snapshot history spans 24h", %{conn: conn} do
      signal = insert_top_signal_with_coingecko("VOLOK", "vol-coin")

      # Snapshot now and ~25h ago — 100 → 150 = +50%
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        CoinTracker.Signals.create_coingecko_snapshot(%{
          coingecko_id: "vol-coin",
          symbol: "VOLOK",
          snapshot_at: now,
          total_volume_usd: Decimal.new("150"),
          price_change_percentage_24h: Decimal.new("3.0")
        })

      {:ok, _} =
        CoinTracker.Signals.create_coingecko_snapshot(%{
          coingecko_id: "vol-coin",
          symbol: "VOLOK",
          snapshot_at: DateTime.add(now, -25, :hour),
          total_volume_usd: Decimal.new("100")
        })

      {:ok, view, _html} = live(conn, ~p"/signals")
      cell_html = render(element(view, "#top-performer-24h-market-#{signal.id}"))

      assert cell_html =~ "+50.0%"
      assert cell_html =~ "+3.0%"
    end

    test "mobile top-performers card includes a 24h Market line", %{conn: conn} do
      signal = insert_top_signal_with_coingecko("MOB", "mob-coin")
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        CoinTracker.Signals.create_coingecko_snapshot(%{
          coingecko_id: "mob-coin",
          symbol: "MOB",
          snapshot_at: now,
          total_volume_usd: Decimal.new("200"),
          price_change_percentage_24h: Decimal.new("5.0")
        })

      {:ok, _} =
        CoinTracker.Signals.create_coingecko_snapshot(%{
          coingecko_id: "mob-coin",
          symbol: "MOB",
          snapshot_at: DateTime.add(now, -25, :hour),
          total_volume_usd: Decimal.new("100")
        })

      {:ok, view, _html} = live(conn, ~p"/signals")
      assert has_element?(view, "#top-performer-mobile-24h-#{signal.id}")
    end
  end

  describe "sort by 24h volume change" do
    test "dropdown exposes the new sort option", %{conn: conn} do
      insert_top_signal("DUMMY")

      {:ok, _view, html} = live(conn, ~p"/signals")
      assert html =~ "volume_change_24h_desc"
      assert html =~ "Sort by 24h Volume Change"
    end

    test "?top=volume_change_24h_desc reorders top-performers by cg_volume_change_24h_pct desc",
         %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _low = insert_top_signal_with_volume("LOWVOL", "low-cg", -10, now)
      _high = insert_top_signal_with_volume("HIGHVOL", "high-cg", 80, now)
      _mid = insert_top_signal_with_volume("MIDVOL", "mid-cg", 20, now)

      {:ok, view, _html} = live(conn, ~p"/signals?top=volume_change_24h_desc")
      html = render(view)

      # The first row (highest 24h volume change) should appear before the others.
      assert html =~ ~r/HIGHVOL.*MIDVOL.*LOWVOL/s
    end

    test "nil cg_volume_change_24h_pct sorts to the bottom", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _no_data = insert_top_signal("NONE")
      _with_data = insert_top_signal_with_volume("HASIT", "hasit-cg", 25, now)

      {:ok, view, _html} = live(conn, ~p"/signals?top=volume_change_24h_desc")
      html = render(view)

      # HASIT (with data) should come before NONE (nil → bottom).
      assert html =~ ~r/HASIT.*NONE/s
    end
  end

  describe "unknown sort params" do
    test "?top=garbage falls back to position_asc instead of crashing", %{conn: conn} do
      _b = insert_top_signal_at_position("BBB", 2)
      _a = insert_top_signal_at_position("AAA", 1)

      {:ok, view, _html} = live(conn, ~p"/signals?top=not_a_real_sort")
      html = render(view)

      assert html =~ ~r/AAA.*BBB/s
    end

    test "?gp=garbage falls back to time_remaining instead of crashing", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/signals?gp=not_a_real_sort&tab=grace")
      assert html =~ "Grace Period"
    end
  end

  defp insert_top_signal_with_volume(symbol, coingecko_id, pct, now) do
    signal = insert_top_signal_with_coingecko(symbol, coingecko_id)

    # 100 → (100 + pct)
    final_volume = Decimal.add(Decimal.new(100), Decimal.new(pct))

    {:ok, _} =
      CoinTracker.Signals.create_coingecko_snapshot(%{
        coingecko_id: coingecko_id,
        symbol: symbol,
        snapshot_at: now,
        total_volume_usd: final_volume
      })

    {:ok, _} =
      CoinTracker.Signals.create_coingecko_snapshot(%{
        coingecko_id: coingecko_id,
        symbol: symbol,
        snapshot_at: DateTime.add(now, -25, :hour),
        total_volume_usd: Decimal.new("100")
      })

    signal
  end

  defp insert_top_signal(symbol) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, symbol_price} =
      CoinTracker.Coins.upsert_symbol_price(%{
        exchange: :binance_spot,
        symbol_pair: "#{symbol}/USDT",
        current_price: "1.00"
      })

    attrs = %{
      symbol: symbol,
      name: symbol,
      initial_price_usd: Decimal.new("1"),
      current_price_usd: Decimal.new("1"),
      in_top: true,
      active: true,
      position: 1,
      in_top_since: now
    }

    %Signal{}
    |> Signal.changeset(attrs)
    |> Ecto.Changeset.put_change(:symbol_price_id, symbol_price.id)
    |> Repo.insert!()
  end

  defp insert_top_signal_with_coingecko(symbol, coingecko_id) do
    signal = insert_top_signal(symbol)

    signal
    |> Ecto.Changeset.change(coingecko_id: coingecko_id)
    |> Repo.update!()
  end

  defp insert_top_signal_at_position(symbol, position) do
    symbol
    |> insert_top_signal()
    |> Ecto.Changeset.change(position: position)
    |> Repo.update!()
  end

  defp insert_signal_with_zero_volume do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      symbol: "NAA",
      name: "NotAvailable",
      initial_volume_24h: Decimal.new(0),
      current_volume_24h: Decimal.new(0),
      initial_price_usd: Decimal.new("1"),
      current_price_usd: Decimal.new("1"),
      max_price_usd: Decimal.new("1"),
      max_increase_percentage: Decimal.new("0"),
      in_top: true,
      active: true,
      in_top_since: now
    }

    %Signal{}
    |> Signal.changeset(attrs)
    |> Repo.insert!()
  end
end
