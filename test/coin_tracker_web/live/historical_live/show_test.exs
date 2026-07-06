defmodule CoinTrackerWeb.HistoricalLive.ShowTest do
  use CoinTrackerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoinTracker.AccountsFixtures
  import CoinTracker.SignalsFixtures

  # Historical routes are now public. Pro users see full unfiltered data.
  setup %{conn: conn} do
    user = pro_user_fixture()
    %{conn: log_in_user(conn, user)}
  end

  describe "redirect behaviour" do
    test "redirects to /historical with a flash error when symbol has no signals", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/historical"}}} =
               live(conn, ~p"/historical/NOSUCHSYMBOL")
    end

    test "redirects regardless of case when symbol is unknown", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/historical"}}} =
               live(conn, ~p"/historical/zzznever")
    end
  end

  describe "page load" do
    test "renders when the symbol has at least one signal", %{conn: conn} do
      signal_fixture(%{symbol: "LOAD"})

      {:ok, _view, _html} = live(conn, ~p"/historical/LOAD")
    end

    test "renders the occurrence list container", %{conn: conn} do
      signal_fixture(%{symbol: "CONTAINER"})

      {:ok, view, _html} = live(conn, ~p"/historical/CONTAINER")

      assert has_element?(view, "#historical-occurrences")
    end

    test "renders one occurrence card per signal for the symbol", %{conn: conn} do
      base = ~U[2025-01-01 00:00:00Z]

      sig1 = signal_fixture(%{symbol: "TWOROWS", in_top_since: base})
      sig2 = signal_fixture(%{symbol: "TWOROWS", in_top_since: DateTime.add(base, 1, :day)})

      {:ok, view, _html} = live(conn, ~p"/historical/TWOROWS")

      assert has_element?(view, "#occurrence-#{sig1.id}")
      assert has_element?(view, "#occurrence-#{sig2.id}")
    end

    test "does not render cards for signals belonging to a different symbol", %{conn: conn} do
      sig_a = signal_fixture(%{symbol: "OURS"})
      sig_b = signal_fixture(%{symbol: "THEIRS"})

      {:ok, view, _html} = live(conn, ~p"/historical/OURS")

      assert has_element?(view, "#occurrence-#{sig_a.id}")
      refute has_element?(view, "#occurrence-#{sig_b.id}")
    end

    test "shows the occurrence count in the page", %{conn: conn} do
      base = ~U[2025-01-01 00:00:00Z]

      signal_fixture(%{symbol: "COUNTCHECK", in_top_since: base})
      signal_fixture(%{symbol: "COUNTCHECK", in_top_since: DateTime.add(base, 1, :day)})

      {:ok, _view, html} = live(conn, ~p"/historical/COUNTCHECK")

      assert html =~ "2 occurrences"
    end

    test "renders '1 occurrence' (singular) when exactly one signal exists", %{conn: conn} do
      signal_fixture(%{symbol: "SINGULAR"})

      {:ok, _view, html} = live(conn, ~p"/historical/SINGULAR")

      assert html =~ "1 occurrence"
    end

    test "renders the symbol name in the page heading", %{conn: conn} do
      signal_fixture(%{symbol: "HEADCHECK"})

      {:ok, _view, html} = live(conn, ~p"/historical/HEADCHECK")

      # The template calls String.upcase on the symbol
      assert html =~ "HEADCHECK"
    end

    test "includes a back-link to /historical", %{conn: conn} do
      signal_fixture(%{symbol: "BACKLINK"})

      {:ok, view, _html} = live(conn, ~p"/historical/BACKLINK")

      assert has_element?(view, "a[href='/historical']")
    end
  end

  describe "active signal card" do
    test "shows the active signal card when the symbol has an active signal", %{conn: conn} do
      signal_fixture(%{symbol: "LIVE", active: true, exit_date: nil})

      {:ok, view, _html} = live(conn, ~p"/historical/LIVE")

      assert has_element?(view, "#active-signal-card")
    end

    test "does not show the active signal card when all signals for the symbol are inactive", %{
      conn: conn
    } do
      signal_fixture(%{symbol: "DEAD", active: false, exit_date: DateTime.utc_now()})

      {:ok, view, _html} = live(conn, ~p"/historical/DEAD")

      refute has_element?(view, "#active-signal-card")
    end

    test "active signal card mentions the symbol is currently active", %{conn: conn} do
      signal_fixture(%{symbol: "SHOWCARD", active: true, exit_date: nil})

      {:ok, view, _html} = live(conn, ~p"/historical/SHOWCARD")

      assert has_element?(view, "#active-signal-card", "SHOWCARD")
    end

    test "active signal card links to the signal show page", %{conn: conn} do
      sig = signal_fixture(%{symbol: "LINKCARD", active: true, exit_date: nil})

      {:ok, view, _html} = live(conn, ~p"/historical/LINKCARD")

      assert has_element?(view, "#active-signal-card a[href='/signals/#{sig.id}']")
    end

    test "symbol with mixed active and inactive signals shows the active card", %{conn: conn} do
      base = ~U[2025-01-01 00:00:00Z]

      # One inactive past occurrence, one active current occurrence
      signal_fixture(%{
        symbol: "MIXED",
        in_top_since: base,
        active: false,
        exit_date: DateTime.add(base, 1, :day)
      })

      signal_fixture(%{
        symbol: "MIXED",
        in_top_since: DateTime.add(base, 7, :day),
        active: true,
        exit_date: nil
      })

      {:ok, view, _html} = live(conn, ~p"/historical/MIXED")

      assert has_element?(view, "#active-signal-card")
    end
  end

  describe "occurrence cards content" do
    test "shows 'still active' for an occurrence with no exit date", %{conn: conn} do
      signal_fixture(%{symbol: "NOEX", active: true, exit_date: nil})

      {:ok, view, _html} = live(conn, ~p"/historical/NOEX")

      assert has_element?(view, "#historical-occurrences", "still active")
    end

    test "shows entry price for an occurrence", %{conn: conn} do
      signal_fixture(%{
        symbol: "ENTRYPRICE",
        initial_price_usd: Decimal.new("3.14")
      })

      {:ok, _view, html} = live(conn, ~p"/historical/ENTRYPRICE")

      assert html =~ "3.14"
    end

    test "cards are ordered by most recent entry first", %{conn: conn} do
      base = ~U[2025-01-01 00:00:00Z]

      older = signal_fixture(%{symbol: "ORDER", in_top_since: DateTime.add(base, -5, :day)})
      newer = signal_fixture(%{symbol: "ORDER", in_top_since: base})

      {:ok, _view, html} = live(conn, ~p"/historical/ORDER")

      # The newer occurrence's card should appear before the older one in the HTML
      newer_pos = :binary.match(html, "occurrence-#{newer.id}") |> elem(0)
      older_pos = :binary.match(html, "occurrence-#{older.id}") |> elem(0)

      assert newer_pos < older_pos
    end
  end

  describe "free user access" do
    test "free user can access the show page with qualifying occurrences" do
      free_user = user_fixture()
      conn = build_conn() |> log_in_user(free_user)

      # Create a signal that qualifies for public view (inactive + exited > 7 days ago)
      signal_fixture(%{
        symbol: "FREEVIEW",
        active: false,
        exit_date: DateTime.add(DateTime.utc_now(), -8, :day)
      })

      # Create an active+in_top signal so the upsell banner appears
      signal_fixture(%{symbol: "ACTIVEBANNER", active: true, in_top: true})

      {:ok, view, _html} = live(conn, ~p"/historical/FREEVIEW")

      assert has_element?(view, "#historical-occurrences")
      assert has_element?(view, "#pro-upsell-banner")
    end

    test "free user is redirected when symbol only has active signals" do
      free_user = user_fixture()
      conn = build_conn() |> log_in_user(free_user)

      # Active signal is filtered out by get_all_occurrences_public, leaving 0 occurrences
      signal_fixture(%{symbol: "FREEBLOCK", active: true})

      assert {:error, {:live_redirect, %{to: "/historical"}}} =
               live(conn, ~p"/historical/FREEBLOCK")
    end
  end
end
