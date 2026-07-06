defmodule CoinTrackerWeb.HistoricalLive.IndexTest do
  use CoinTrackerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoinTracker.AccountsFixtures
  import CoinTracker.SignalsFixtures

  # Historical routes are now public but show filtered data for non-pro users.
  # Pro users see full unfiltered data.
  setup %{conn: conn} do
    user = pro_user_fixture()
    %{conn: log_in_user(conn, user)}
  end

  describe "page load" do
    test "pro user can visit the page", %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/historical")
    end

    test "free user can access the page and sees the upsell banner" do
      free_user = user_fixture()
      conn = build_conn() |> log_in_user(free_user)

      # Create an active signal so count_total_active_signals() > 0
      signal_fixture(%{symbol: "ACTIVETOP", active: true, in_top: true})

      {:ok, view, _html} = live(conn, ~p"/historical")

      assert has_element?(view, "#pro-upsell-banner")
    end

    test "unauthenticated user can access the page" do
      conn = build_conn()

      {:ok, _view, _html} = live(conn, ~p"/historical")
    end

    test "renders the page title", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/historical")

      assert html =~ "Historical Signals"
    end

    test "renders the search form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/historical")

      assert has_element?(view, "#historical-search-form")
      assert has_element?(view, "#symbol-search-input")
    end

    test "shows existing symbols in the stream", %{conn: conn} do
      signal_fixture(%{symbol: "VISIBLE"})

      {:ok, view, _html} = live(conn, ~p"/historical")

      # Stream dom_id is &"symbol-#{&1.symbol}" — so the element id is symbol-VISIBLE
      assert has_element?(view, "#symbol-VISIBLE")
    end

    test "shows an active badge when the symbol has an active signal", %{conn: conn} do
      signal_fixture(%{symbol: "ALIVE", active: true})

      {:ok, view, _html} = live(conn, ~p"/historical")

      # The card for this symbol should contain the word "Active"
      assert has_element?(view, "#symbol-ALIVE", "Active")
    end

    test "does not show an active badge when all signals for the symbol are inactive", %{
      conn: conn
    } do
      signal_fixture(%{symbol: "GONE", active: false})

      {:ok, view, _html} = live(conn, ~p"/historical")

      assert has_element?(view, "#symbol-GONE")
      refute has_element?(view, "#symbol-GONE", "Active")
    end

    test "shows the occurrence count for a symbol with multiple entries", %{conn: conn} do
      base = ~U[2025-01-01 00:00:00Z]

      signal_fixture(%{symbol: "MULTI", in_top_since: base})
      signal_fixture(%{symbol: "MULTI", in_top_since: DateTime.add(base, 1, :day)})
      signal_fixture(%{symbol: "MULTI", in_top_since: DateTime.add(base, 2, :day)})

      {:ok, _view, html} = live(conn, ~p"/historical")

      # Template renders ngettext("1 occurrence", "%{count} occurrences", count)
      assert html =~ "3 occurrences"
    end
  end

  describe "search filtering" do
    test "filtering by exact symbol reduces the stream to matching cards", %{conn: conn} do
      signal_fixture(%{symbol: "ALPHA", name: "Alpha Coin"})
      signal_fixture(%{symbol: "BETA", name: "Beta Coin"})

      {:ok, view, _html} = live(conn, ~p"/historical")

      # Both cards visible before filtering
      assert has_element?(view, "#symbol-ALPHA")
      assert has_element?(view, "#symbol-BETA")

      view
      |> form("#historical-search-form", %{search: "ALPHA"})
      |> render_change()

      assert has_element?(view, "#symbol-ALPHA")
      refute has_element?(view, "#symbol-BETA")
    end

    test "search is case-insensitive for symbols", %{conn: conn} do
      signal_fixture(%{symbol: "CASECOIN", name: "Case Coin"})

      {:ok, view, _html} = live(conn, ~p"/historical")

      view
      |> form("#historical-search-form", %{search: "casecoin"})
      |> render_change()

      assert has_element?(view, "#symbol-CASECOIN")
    end

    test "filtering by coin name works", %{conn: conn} do
      signal_fixture(%{symbol: "NAMEDCOIN", name: "Unique Naming Corp"})
      signal_fixture(%{symbol: "OTHERCOIN", name: "Different Name"})

      {:ok, view, _html} = live(conn, ~p"/historical")

      view
      |> form("#historical-search-form", %{search: "Unique Naming"})
      |> render_change()

      assert has_element?(view, "#symbol-NAMEDCOIN")
      refute has_element?(view, "#symbol-OTHERCOIN")
    end

    test "clearing the search restores all symbols", %{conn: conn} do
      signal_fixture(%{symbol: "FIRST"})
      signal_fixture(%{symbol: "SECOND"})

      {:ok, view, _html} = live(conn, ~p"/historical")

      # Filter down to one result
      view
      |> form("#historical-search-form", %{search: "FIRST"})
      |> render_change()

      refute has_element?(view, "#symbol-SECOND")

      # Clear the search — both cards should reappear
      view
      |> form("#historical-search-form", %{search: ""})
      |> render_change()

      assert has_element?(view, "#symbol-FIRST")
      assert has_element?(view, "#symbol-SECOND")
    end

    test "searching with no matches shows no symbol cards", %{conn: conn} do
      signal_fixture(%{symbol: "PRESENT"})

      {:ok, view, _html} = live(conn, ~p"/historical")

      view
      |> form("#historical-search-form", %{search: "ZZZNOMATCH"})
      |> render_change()

      refute has_element?(view, "#symbol-PRESENT")
    end

    test "symbol count updates after filtering", %{conn: conn} do
      signal_fixture(%{symbol: "COUNTME"})
      signal_fixture(%{symbol: "SKIP"})

      {:ok, view, _html} = live(conn, ~p"/historical")

      view
      |> form("#historical-search-form", %{search: "COUNTME"})
      |> render_change()

      # Only one symbol matches; the count display should reflect that
      assert render(view) =~ "1 symbol"
    end
  end

  describe "each symbol card links to the show page" do
    test "symbol card links to the historical show page", %{conn: conn} do
      signal_fixture(%{symbol: "LINKME"})

      {:ok, view, _html} = live(conn, ~p"/historical")

      # The card is a <.link navigate=…> — verify it points to the right path
      assert has_element?(view, ~s(a[href="/historical/LINKME"]))
    end
  end

  describe "recently exited filter (pro only)" do
    test "pro users see the Recently Exited tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/historical")

      assert has_element?(view, "#filter-recently-exited")
    end

    test "free users do not see the Recently Exited tab" do
      free_user = user_fixture()
      conn = build_conn() |> log_in_user(free_user)

      {:ok, view, _html} = live(conn, ~p"/historical")

      refute has_element?(view, "#filter-recently-exited")
    end

    test "unauthenticated users do not see the Recently Exited tab" do
      conn = build_conn()

      {:ok, view, _html} = live(conn, ~p"/historical")

      refute has_element?(view, "#filter-recently-exited")
    end

    test "clicking Recently Exited keeps only symbols with recent inactive exits", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      recent_exit = DateTime.add(now, -2, :day)
      old_exit = DateTime.add(now, -30, :day)

      # Should match the filter
      signal_fixture(%{
        symbol: "RECENTOUT",
        in_top_since: DateTime.add(recent_exit, -1, :day),
        active: false,
        exit_date: recent_exit
      })

      # Old exit — should NOT match
      signal_fixture(%{
        symbol: "OLDOUT",
        in_top_since: DateTime.add(old_exit, -1, :day),
        active: false,
        exit_date: old_exit
      })

      # Still active — should NOT match
      signal_fixture(%{symbol: "STILLIN", active: true, exit_date: nil})

      {:ok, view, _html} = live(conn, ~p"/historical")

      # Before filter: all three visible
      assert has_element?(view, "#symbol-RECENTOUT")
      assert has_element?(view, "#symbol-OLDOUT")
      assert has_element?(view, "#symbol-STILLIN")

      view
      |> element("#filter-recently-exited")
      |> render_click()

      assert has_element?(view, "#symbol-RECENTOUT")
      refute has_element?(view, "#symbol-OLDOUT")
      refute has_element?(view, "#symbol-STILLIN")
    end

    test "excludes symbols that still have an active signal even if a prior signal exited recently",
         %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      recent_exit = DateTime.add(now, -2, :day)

      # Same symbol: one prior inactive signal that exited recently, plus a
      # currently-active signal. The symbol is still Active and must NOT
      # appear in Recently Exited.
      signal_fixture(%{
        symbol: "MIXEDLIVE",
        in_top_since: DateTime.add(recent_exit, -3, :day),
        active: false,
        exit_date: recent_exit
      })

      signal_fixture(%{
        symbol: "MIXEDLIVE",
        in_top_since: DateTime.add(now, -1, :day),
        active: true,
        exit_date: nil
      })

      {:ok, view, _html} = live(conn, ~p"/historical")

      view
      |> element("#filter-recently-exited")
      |> render_click()

      refute has_element?(view, "#symbol-MIXEDLIVE")
    end

    test "orders Recently Exited symbols by most recent exit date first", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Three fully-inactive symbols with distinct, recent exit dates.
      signal_fixture(%{
        symbol: "EXITOLDEST",
        in_top_since: DateTime.add(now, -7, :day),
        active: false,
        exit_date: DateTime.add(now, -6, :day)
      })

      signal_fixture(%{
        symbol: "EXITMIDDLE",
        in_top_since: DateTime.add(now, -5, :day),
        active: false,
        exit_date: DateTime.add(now, -3, :day)
      })

      signal_fixture(%{
        symbol: "EXITNEWEST",
        in_top_since: DateTime.add(now, -2, :day),
        active: false,
        exit_date: DateTime.add(now, -1, :day)
      })

      {:ok, view, _html} = live(conn, ~p"/historical")

      html =
        view
        |> element("#filter-recently-exited")
        |> render_click()

      newest_pos = :binary.match(html, "symbol-EXITNEWEST") |> elem(0)
      middle_pos = :binary.match(html, "symbol-EXITMIDDLE") |> elem(0)
      oldest_pos = :binary.match(html, "symbol-EXITOLDEST") |> elem(0)

      assert newest_pos < middle_pos
      assert middle_pos < oldest_pos
    end

    test "switching back to All restores all symbols after Recently Exited", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      recent_exit = DateTime.add(now, -2, :day)
      old_exit = DateTime.add(now, -30, :day)

      signal_fixture(%{
        symbol: "RECENT",
        in_top_since: DateTime.add(recent_exit, -1, :day),
        active: false,
        exit_date: recent_exit
      })

      signal_fixture(%{
        symbol: "STALE",
        in_top_since: DateTime.add(old_exit, -1, :day),
        active: false,
        exit_date: old_exit
      })

      {:ok, view, _html} = live(conn, ~p"/historical")

      view
      |> element("#filter-recently-exited")
      |> render_click()

      refute has_element?(view, "#symbol-STALE")

      view
      |> element("#filter-all")
      |> render_click()

      assert has_element?(view, "#symbol-RECENT")
      assert has_element?(view, "#symbol-STALE")
    end
  end

  describe "URL filter persistence" do
    test "search query param filters symbols on initial load", %{conn: conn} do
      signal_fixture(%{symbol: "ALPHA", name: "Alpha Coin"})
      signal_fixture(%{symbol: "BETA", name: "Beta Coin"})

      {:ok, view, _html} = live(conn, ~p"/historical?search=ALPHA")

      assert has_element?(view, "#symbol-ALPHA")
      refute has_element?(view, "#symbol-BETA")
      assert has_element?(view, "#symbol-search-input[value=\"ALPHA\"]")
    end

    test "status query param selects the active filter on initial load", %{conn: conn} do
      signal_fixture(%{symbol: "LIVECOIN", active: true})
      signal_fixture(%{symbol: "DEADCOIN", active: false})

      {:ok, view, _html} = live(conn, ~p"/historical?status=active")

      assert has_element?(view, "#symbol-LIVECOIN")
      refute has_element?(view, "#symbol-DEADCOIN")
    end

    test "status query param selects the inactive filter on initial load", %{conn: conn} do
      signal_fixture(%{symbol: "LIVECOIN", active: true})
      signal_fixture(%{symbol: "DEADCOIN", active: false})

      {:ok, view, _html} = live(conn, ~p"/historical?status=inactive")

      refute has_element?(view, "#symbol-LIVECOIN")
      assert has_element?(view, "#symbol-DEADCOIN")
    end

    test "invalid status query param falls back to \"all\"", %{conn: conn} do
      signal_fixture(%{symbol: "LIVECOIN", active: true})
      signal_fixture(%{symbol: "DEADCOIN", active: false})

      {:ok, view, _html} = live(conn, ~p"/historical?status=bogus")

      assert has_element?(view, "#symbol-LIVECOIN")
      assert has_element?(view, "#symbol-DEADCOIN")
    end

    test "search and status params compose on initial load", %{conn: conn} do
      signal_fixture(%{symbol: "ALPHA", name: "Alpha", active: true})
      signal_fixture(%{symbol: "ALPHABET", name: "Alphabet", active: false})
      signal_fixture(%{symbol: "BETA", name: "Beta", active: true})

      {:ok, view, _html} = live(conn, ~p"/historical?search=ALPHA&status=active")

      assert has_element?(view, "#symbol-ALPHA")
      refute has_element?(view, "#symbol-ALPHABET")
      refute has_element?(view, "#symbol-BETA")
    end

    test "typing in the search box updates the URL", %{conn: conn} do
      signal_fixture(%{symbol: "ALPHA"})

      {:ok, view, _html} = live(conn, ~p"/historical")

      view
      |> form("#historical-search-form", %{search: "ALPHA"})
      |> render_change()

      assert patched_params(view) == %{"search" => "ALPHA"}
    end

    test "clicking a status filter updates the URL", %{conn: conn} do
      signal_fixture(%{symbol: "LIVECOIN", active: true})

      {:ok, view, _html} = live(conn, ~p"/historical")

      view
      |> element("#filter-active")
      |> render_click()

      assert patched_params(view) == %{"status" => "active"}
    end

    test "clearing the search returns to the base URL without params", %{conn: conn} do
      signal_fixture(%{symbol: "ALPHA"})

      {:ok, view, _html} = live(conn, ~p"/historical?search=ALPHA")

      view
      |> form("#historical-search-form", %{search: ""})
      |> render_change()

      assert patched_params(view) == %{}
    end

    test "selecting All status drops the status param from the URL", %{conn: conn} do
      signal_fixture(%{symbol: "LIVECOIN", active: true})

      {:ok, view, _html} = live(conn, ~p"/historical?status=active")

      view
      |> element("#filter-all")
      |> render_click()

      assert patched_params(view) == %{}
    end

    test "changing search preserves the current status filter in the URL", %{conn: conn} do
      signal_fixture(%{symbol: "ALPHA", active: true})

      {:ok, view, _html} = live(conn, ~p"/historical?status=active")

      view
      |> form("#historical-search-form", %{search: "ALPHA"})
      |> render_change()

      assert patched_params(view) == %{"search" => "ALPHA", "status" => "active"}
    end

    test "changing status preserves the current search in the URL", %{conn: conn} do
      signal_fixture(%{symbol: "ALPHA", active: true})

      {:ok, view, _html} = live(conn, ~p"/historical?search=ALPHA")

      view
      |> element("#filter-active")
      |> render_click()

      assert patched_params(view) == %{"search" => "ALPHA", "status" => "active"}
    end
  end

  # Extracts the query params from the most recent push_patch for the given view,
  # avoiding flakiness from map iteration order in encoded URLs.
  defp patched_params(view) do
    url = assert_patch(view)
    uri = URI.parse(url)
    assert uri.path == "/historical"
    URI.decode_query(uri.query || "")
  end
end
