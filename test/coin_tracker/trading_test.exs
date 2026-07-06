defmodule CoinTracker.TradingTest do
  use CoinTracker.DataCase

  import Mox

  alias CoinTracker.Trading
  alias CoinTracker.Accounts
  alias CoinTracker.Coins.HTTPClientMock

  # Ensure mocks are verified after each test
  setup :verify_on_exit!

  describe "create_position/3" do
    setup do
      # Create a test user
      {:ok, user} =
        Accounts.register_user(%{
          email: "test@example.com",
          password: "ValidPassword123!"
        })

      {:ok, user: user}
    end

    test "creates position successfully with valid data and API response", %{user: user} do
      # Mock successful price fetch
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: [
             %{"symbol" => "ETHUSDT", "price" => "2000.50"}
           ]
         }}
      end)

      attrs = %{
        "symbol" => "ETH",
        "exchange" => "binance_spot",
        "entry_price" => "2000",
        "stop_loss_percent" => "-10",
        "take_profit_percent" => "20",
        "current_threshold_zone" => "5"
      }

      assert {:ok, position} =
               Trading.create_position(user.id, attrs, http_client: HTTPClientMock)

      assert position.entry_price == Decimal.new("2000")
      assert position.stop_loss_percent == Decimal.new("-10")
      assert position.take_profit_percent == Decimal.new("20")
      assert position.user_id == user.id
      assert position.symbol_price_id != nil
    end

    test "returns changeset error when validation fails", %{user: user} do
      attrs = %{
        "symbol" => "ETH",
        "exchange" => "binance_spot",
        "entry_price" => "-100",
        # Invalid: negative price
        "stop_loss_percent" => "-10",
        "take_profit_percent" => "20"
      }

      assert {:error, changeset} =
               Trading.create_position(user.id, attrs, http_client: HTTPClientMock)

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).entry_price
    end

    test "returns changeset error when symbol is missing", %{user: user} do
      attrs = %{
        "exchange" => "binance_spot",
        "entry_price" => "2000",
        "stop_loss_percent" => "-10",
        "take_profit_percent" => "20"
      }

      assert {:error, changeset} =
               Trading.create_position(user.id, attrs, http_client: HTTPClientMock)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).symbol
    end

    test "returns changeset error when API returns 400 error", %{user: user} do
      # Mock API error response
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 400,
           body: %{"code" => -1121, "msg" => "Invalid symbol."}
         }}
      end)

      attrs = %{
        "symbol" => "INVALID",
        "exchange" => "binance_spot",
        "entry_price" => "2000",
        "stop_loss_percent" => "-10",
        "take_profit_percent" => "20",
        "current_threshold_zone" => "5"
      }

      assert {:error, changeset} =
               Trading.create_position(user.id, attrs, http_client: HTTPClientMock)

      refute changeset.valid?
      assert ["Exchange API error: Invalid symbol."] = errors_on(changeset).symbol
    end

    test "returns changeset error on network error", %{user: user} do
      # Mock network error
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      attrs = %{
        "symbol" => "ETH",
        "exchange" => "binance_spot",
        "entry_price" => "2000",
        "stop_loss_percent" => "-10",
        "take_profit_percent" => "20",
        "current_threshold_zone" => "5"
      }

      assert {:error, changeset} =
               Trading.create_position(user.id, attrs, http_client: HTTPClientMock)

      refute changeset.valid?

      assert ["Network error. Please check your connection and try again."] =
               errors_on(changeset).symbol
    end

    test "returns changeset error when no prices returned", %{user: user} do
      # Mock empty response
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: []}}
      end)

      attrs = %{
        "symbol" => "UNKNOWN",
        "exchange" => "binance_spot",
        "entry_price" => "2000",
        "stop_loss_percent" => "-10",
        "take_profit_percent" => "20",
        "current_threshold_zone" => "5"
      }

      assert {:error, changeset} =
               Trading.create_position(user.id, attrs, http_client: HTTPClientMock)

      refute changeset.valid?
      assert ["No price data available for this symbol"] = errors_on(changeset).symbol
    end

    test "returns changeset error for invalid stop loss percent", %{user: user} do
      attrs = %{
        "symbol" => "ETH",
        "exchange" => "binance_spot",
        "entry_price" => "2000",
        "stop_loss_percent" => "10",
        # Invalid: positive
        "take_profit_percent" => "20"
      }

      assert {:error, changeset} =
               Trading.create_position(user.id, attrs, http_client: HTTPClientMock)

      refute changeset.valid?
      assert "must be less than or equal to 0" in errors_on(changeset).stop_loss_percent
    end

    test "returns changeset error for invalid take profit percent", %{user: user} do
      attrs = %{
        "symbol" => "ETH",
        "exchange" => "binance_spot",
        "entry_price" => "2000",
        "stop_loss_percent" => "-10",
        "take_profit_percent" => "-5"
        # Invalid: negative
      }

      assert {:error, changeset} =
               Trading.create_position(user.id, attrs, http_client: HTTPClientMock)

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).take_profit_percent
    end

    test "normalizes lowercase symbol before API call", %{user: user} do
      # Mock successful price fetch
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: [
             %{"symbol" => "BTCUSDT", "price" => "50000.00"}
           ]
         }}
      end)

      attrs = %{
        "symbol" => "btc",
        # lowercase
        "exchange" => "binance_spot",
        "entry_price" => "50000",
        "stop_loss_percent" => "-5",
        "take_profit_percent" => "15",
        "current_threshold_zone" => "5"
      }

      assert {:ok, position} =
               Trading.create_position(user.id, attrs, http_client: HTTPClientMock)

      assert position.entry_price == Decimal.new("50000")
    end

    test "creates position with zero stop loss (break-even)", %{user: user} do
      # Mock successful price fetch
      expect(HTTPClientMock, :get, fn _url, _opts ->
        {:ok,
         %{
           status: 200,
           body: [
             %{"symbol" => "SOLUSDT", "price" => "100.00"}
           ]
         }}
      end)

      attrs = %{
        "symbol" => "SOL",
        "exchange" => "binance_spot",
        "entry_price" => "100",
        "stop_loss_percent" => "0",
        # Break-even
        "take_profit_percent" => "25",
        "current_threshold_zone" => "5"
      }

      assert {:ok, position} =
               Trading.create_position(user.id, attrs, http_client: HTTPClientMock)

      assert position.stop_loss_percent == Decimal.new("0")
      assert position.take_profit_percent == Decimal.new("25")
    end

    test "validates that stop loss is less than take profit", %{user: user} do
      attrs = %{
        "symbol" => "ETH",
        "exchange" => "binance_spot",
        "entry_price" => "2000",
        "stop_loss_percent" => "-5",
        "take_profit_percent" => "-10"
        # Invalid: take profit less than stop loss
      }

      assert {:error, changeset} =
               Trading.create_position(user.id, attrs, http_client: HTTPClientMock)

      refute changeset.valid?
      assert "must be less than take profit percent" in errors_on(changeset).stop_loss_percent
    end

    test "returns error for invalid exchange", %{user: user} do
      attrs = %{
        "symbol" => "ETH",
        "exchange" => "invalid_exchange",
        "entry_price" => "2000",
        "stop_loss_percent" => "-10",
        "take_profit_percent" => "20",
        "current_threshold_zone" => "5"
      }

      assert {:error, changeset} =
               Trading.create_position(user.id, attrs, http_client: HTTPClientMock)

      refute changeset.valid?
      assert ["Invalid exchange"] = errors_on(changeset).symbol
    end
  end

  describe "list_active_positions_for_user/1" do
    setup do
      # Create test users
      {:ok, user1} =
        Accounts.register_user(%{
          email: "user1@example.com",
          password: "ValidPassword123!"
        })

      {:ok, user2} =
        Accounts.register_user(%{
          email: "user2@example.com",
          password: "ValidPassword123!"
        })

      {:ok, user1: user1, user2: user2}
    end

    test "returns empty list when user has no positions", %{user1: user1} do
      assert [] = Trading.list_active_positions_for_user(user1.id)
    end

    test "returns only active positions for the user", %{user1: user1} do
      # Create a symbol price
      symbol_price = create_symbol_price("ETHUSDT", :binance_spot, "2000.00")

      # Create 2 active positions and 1 closed position
      active_pos1 = create_position(user1.id, symbol_price.id, %{status: :active})
      _active_pos2 = create_position(user1.id, symbol_price.id, %{status: :active})
      _closed_pos = create_position(user1.id, symbol_price.id, %{status: :closed})

      positions = Trading.list_active_positions_for_user(user1.id)

      assert length(positions) == 2
      assert Enum.all?(positions, fn p -> p.status == :active end)
      assert Enum.any?(positions, fn p -> p.id == active_pos1.id end)
    end

    test "does not return other users' positions", %{user1: user1, user2: user2} do
      symbol_price = create_symbol_price("BTCUSDT", :binance_spot, "50000.00")

      # Create position for user1
      user1_pos = create_position(user1.id, symbol_price.id, %{status: :active})

      # Create position for user2
      _user2_pos = create_position(user2.id, symbol_price.id, %{status: :active})

      # User1 should only see their own position
      positions = Trading.list_active_positions_for_user(user1.id)

      assert length(positions) == 1
      assert hd(positions).id == user1_pos.id
      assert hd(positions).user_id == user1.id
    end

    test "preloads symbol_price association", %{user1: user1} do
      symbol_price = create_symbol_price("SOLUSDT", :bitget_spot, "100.50")
      _position = create_position(user1.id, symbol_price.id, %{status: :active})

      positions = Trading.list_active_positions_for_user(user1.id)

      assert length(positions) == 1
      position = hd(positions)

      # symbol_price should be loaded, not an Ecto.Association.NotLoaded struct
      assert %CoinTracker.Coins.SymbolPrice{} = position.symbol_price
      assert position.symbol_price.id == symbol_price.id
      assert position.symbol_price.symbol_pair == "SOLUSDT"
      assert position.symbol_price.exchange == :bitget_spot
    end

    test "orders positions by most recent first", %{user1: user1} do
      symbol_price = create_symbol_price("ADAUSDT", :binance_spot, "0.50")

      # Create positions with explicit timestamps to ensure ordering
      now = DateTime.utc_now()

      pos1 =
        create_position_with_timestamp(user1.id, symbol_price.id, DateTime.add(now, -2, :hour))

      pos2 =
        create_position_with_timestamp(user1.id, symbol_price.id, DateTime.add(now, -1, :hour))

      pos3 = create_position_with_timestamp(user1.id, symbol_price.id, now)

      positions = Trading.list_active_positions_for_user(user1.id)

      # Should be ordered newest first
      assert length(positions) == 3
      [first, second, third] = positions
      assert first.id == pos3.id
      assert second.id == pos2.id
      assert third.id == pos1.id
    end
  end

  describe "calculate_pnl_percent/2" do
    test "calculates profit percentage correctly" do
      entry_price = Decimal.new("2000")
      current_price = Decimal.new("2200")

      pnl = Trading.calculate_pnl_percent(entry_price, current_price)

      assert Decimal.equal?(pnl, Decimal.new("10.0"))
    end

    test "calculates loss percentage correctly" do
      entry_price = Decimal.new("2000")
      current_price = Decimal.new("1800")

      pnl = Trading.calculate_pnl_percent(entry_price, current_price)

      assert Decimal.equal?(pnl, Decimal.new("-10.0"))
    end

    test "returns zero for no price change" do
      entry_price = Decimal.new("1000")
      current_price = Decimal.new("1000")

      pnl = Trading.calculate_pnl_percent(entry_price, current_price)

      assert Decimal.equal?(pnl, Decimal.new("0"))
    end

    test "handles small price movements accurately" do
      entry_price = Decimal.new("100.00")
      current_price = Decimal.new("100.50")

      pnl = Trading.calculate_pnl_percent(entry_price, current_price)

      assert Decimal.equal?(pnl, Decimal.new("0.5"))
    end
  end

  # Helper functions for creating test data
  defp create_symbol_price(symbol_pair, exchange, price) do
    {:ok, symbol_price} =
      CoinTracker.Coins.upsert_symbol_price(%{
        symbol_pair: symbol_pair,
        exchange: exchange,
        current_price: price
      })

    symbol_price
  end

  defp create_position(user_id, symbol_price_id, attrs) do
    default_attrs = %{
      entry_price: "1000.00",
      stop_loss_percent: "-10",
      take_profit_percent: "20"
    }

    # Extract status separately since it's not in the changeset cast
    status = Map.get(attrs, :status, :active)
    changeset_attrs = Map.delete(attrs, :status)
    merged_attrs = Map.merge(default_attrs, changeset_attrs)

    %CoinTracker.Trading.Position{}
    |> CoinTracker.Trading.Position.changeset(merged_attrs)
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> Ecto.Changeset.put_change(:symbol_price_id, symbol_price_id)
    |> Ecto.Changeset.put_change(:status, status)
    |> CoinTracker.Repo.insert!()
  end

  defp create_position_with_timestamp(user_id, symbol_price_id, timestamp) do
    # Truncate to second precision as required by :utc_datetime
    truncated_timestamp = DateTime.truncate(timestamp, :second)

    %CoinTracker.Trading.Position{}
    |> CoinTracker.Trading.Position.changeset(%{
      entry_price: "1000.00",
      stop_loss_percent: "-10",
      take_profit_percent: "20"
    })
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> Ecto.Changeset.put_change(:symbol_price_id, symbol_price_id)
    |> Ecto.Changeset.put_change(:status, :active)
    |> Ecto.Changeset.put_change(:inserted_at, truncated_timestamp)
    |> Ecto.Changeset.put_change(:updated_at, truncated_timestamp)
    |> CoinTracker.Repo.insert!()
  end

  describe "close_position/2" do
    setup do
      {:ok, user} =
        Accounts.register_user(%{
          email: "test@example.com",
          password: "ValidPassword123!"
        })

      symbol_price = create_symbol_price("ETH/USDT", :binance_spot, "2000")
      position = create_position(user.id, symbol_price.id, %{})

      {:ok, position: position}
    end

    test "closes active position with take_profit reason", %{position: position} do
      assert {:ok, closed_position} = Trading.close_position(position, :take_profit)

      assert closed_position.status == :closed
      assert closed_position.closed_reason == "take_profit"
      assert %DateTime{} = closed_position.closed_at
      # Verify it's close to now (within 1 second)
      assert DateTime.diff(DateTime.utc_now(), closed_position.closed_at) < 2
    end

    test "closes active position with stop_loss reason", %{position: position} do
      assert {:ok, closed_position} = Trading.close_position(position, :stop_loss)

      assert closed_position.status == :closed
      assert closed_position.closed_reason == "stop_loss"
      assert %DateTime{} = closed_position.closed_at
    end

    test "closes active position with manual reason", %{position: position} do
      assert {:ok, closed_position} = Trading.close_position(position, :manual)

      assert closed_position.status == :closed
      assert closed_position.closed_reason == "manual"
      assert %DateTime{} = closed_position.closed_at
    end

    test "returns error when trying to close already closed position", %{position: position} do
      # Close it first
      {:ok, _} = Trading.close_position(position, :take_profit)

      # Try to close again
      closed_position = CoinTracker.Repo.reload(position)
      assert {:error, :already_closed} = Trading.close_position(closed_position, :stop_loss)
    end

    test "closed position no longer appears in active positions list", %{position: position} do
      # Verify it's in the list initially
      active_positions = Trading.list_active_positions_for_user(position.user_id)
      assert length(active_positions) == 1

      # Close the position
      {:ok, _} = Trading.close_position(position, :take_profit)

      # Verify it's no longer in the list
      active_positions = Trading.list_active_positions_for_user(position.user_id)
      assert active_positions == []
    end

    test "broadcasts position_closed for take_profit closure", %{position: position} do
      # Subscribe to the user's position topic
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "positions:#{position.user_id}")

      {:ok, _} = Trading.close_position(position, :take_profit)

      assert_receive {:position_closed, position_id, symbol_pair, :take_profit}
      assert position_id == position.id
      assert symbol_pair == "ETH/USDT"
    end

    test "broadcasts position_closed for stop_loss closure", %{position: position} do
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "positions:#{position.user_id}")

      {:ok, _} = Trading.close_position(position, :stop_loss)

      assert_receive {:position_closed, position_id, symbol_pair, :stop_loss}
      assert position_id == position.id
      assert symbol_pair == "ETH/USDT"
    end

    test "does not broadcast for manual closure", %{position: position} do
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, "positions:#{position.user_id}")

      {:ok, _} = Trading.close_position(position, :manual)

      refute_receive {:position_closed, _, _, _}, 100
    end
  end

  describe "signal watchlist" do
    setup do
      {:ok, user1} =
        Accounts.register_user(%{
          email: "watch1@example.com",
          password: "ValidPassword123!"
        })

      {:ok, user2} =
        Accounts.register_user(%{
          email: "watch2@example.com",
          password: "ValidPassword123!"
        })

      symbol_price = create_symbol_price("ETH/USDT", :binance_spot, "2000")
      signal = create_signal("ETH", symbol_price.id, "1000")

      {:ok, user1: user1, user2: user2, signal: signal, symbol_price: symbol_price}
    end

    test "watch_signal/2 creates a watched position with sane defaults", %{
      user1: user,
      signal: signal
    } do
      assert {:ok, position} = Trading.watch_signal(user.id, signal)

      assert position.kind == :watched
      assert position.user_id == user.id
      assert position.entry_price == Decimal.new("1000")
      assert is_nil(position.stop_loss_percent)
      assert is_nil(position.take_profit_percent)
      assert is_nil(position.amount_invested)
      assert Decimal.equal?(position.current_threshold_zone, Decimal.new("5"))
      assert position.source == "watch"
    end

    test "watch_signal/2 is idempotent", %{user1: user, signal: signal} do
      assert {:ok, first} = Trading.watch_signal(user.id, signal)
      assert {:ok, second} = Trading.watch_signal(user.id, signal)
      assert first.id == second.id
    end

    test "watch_signal/2 errors when signal has no initial price", %{
      user1: user,
      symbol_price: symbol_price
    } do
      signal = create_signal("BTC", symbol_price.id, nil)
      assert {:error, :no_initial_price} = Trading.watch_signal(user.id, signal)
    end

    test "unwatch_signal/2 removes the watched position", %{user1: user, signal: signal} do
      {:ok, _} = Trading.watch_signal(user.id, signal)
      assert {:ok, _} = Trading.unwatch_signal(user.id, signal)
      assert Trading.list_watched_positions_for_user(user.id) == []
    end

    test "unwatch_signal/2 returns :not_found when no watch exists", %{
      user1: user,
      signal: signal
    } do
      assert {:error, :not_found} = Trading.unwatch_signal(user.id, signal)
    end

    test "unwatch_position_for_user/2 deletes a watched position by id", %{
      user1: user,
      signal: signal
    } do
      {:ok, position} = Trading.watch_signal(user.id, signal)
      assert {:ok, _} = Trading.unwatch_position_for_user(user.id, position.id)
      assert Trading.list_watched_positions_for_user(user.id) == []
    end

    test "unwatch_position_for_user/2 refuses to delete other users' positions", %{
      user1: user,
      user2: other,
      signal: signal
    } do
      {:ok, position} = Trading.watch_signal(user.id, signal)
      assert {:error, :not_found} = Trading.unwatch_position_for_user(other.id, position.id)
      assert [_] = Trading.list_watched_positions_for_user(user.id)
    end

    test "unwatch_position_for_user/2 refuses to delete tracked positions", %{
      user1: user,
      symbol_price: symbol_price
    } do
      tracked = create_position(user.id, symbol_price.id, %{status: :active})
      assert {:error, :not_found} = Trading.unwatch_position_for_user(user.id, tracked.id)
    end

    test "watched_base_symbols_for_user/1 returns symbols user is watching", %{
      user1: user,
      signal: signal
    } do
      {:ok, _} = Trading.watch_signal(user.id, signal)
      assert MapSet.new(["ETH"]) == Trading.watched_base_symbols_for_user(user.id)
    end

    test "list_active_positions_for_user/1 excludes :watched", %{
      user1: user,
      signal: signal,
      symbol_price: symbol_price
    } do
      _tracked = create_position(user.id, symbol_price.id, %{status: :active})
      {:ok, _watched} = Trading.watch_signal(user.id, signal)

      assert [pos] = Trading.list_active_positions_for_user(user.id)
      assert pos.kind == :tracked
    end

    test "list_user_ids_with_active_position_for_symbol/1 includes watch-only users", %{
      user1: tracker,
      user2: watcher,
      signal: signal,
      symbol_price: symbol_price
    } do
      _tracked_pos = create_position(tracker.id, symbol_price.id, %{status: :active})
      {:ok, _} = Trading.watch_signal(watcher.id, signal)

      user_ids = Trading.list_user_ids_with_active_position_for_symbol("ETH")
      assert tracker.id in user_ids
      assert watcher.id in user_ids
    end

    test "list_all_active_positions/0 excludes :watched", %{user1: user, signal: signal} do
      {:ok, _} = Trading.watch_signal(user.id, signal)
      assert Trading.list_all_active_positions() == []
    end
  end

  describe "delete_closed_position_for_user/2" do
    setup do
      {:ok, user} =
        Accounts.register_user(%{
          email: "closed-delete@example.com",
          password: "ValidPassword123!"
        })

      {:ok, other} =
        Accounts.register_user(%{
          email: "closed-delete-other@example.com",
          password: "ValidPassword123!"
        })

      symbol_price = create_symbol_price("ETH/USDT", :binance_spot, "2000")
      closed = create_position(user.id, symbol_price.id, %{status: :closed})

      {:ok, user: user, other: other, symbol_price: symbol_price, closed: closed}
    end

    test "deletes a closed position belonging to the user", %{user: user, closed: closed} do
      assert {:ok, _} = Trading.delete_closed_position_for_user(user.id, closed.id)
      assert Trading.list_closed_positions_for_user(user.id) == []
    end

    test "refuses to delete another user's closed position", %{
      other: other,
      closed: closed
    } do
      assert {:error, :not_found} =
               Trading.delete_closed_position_for_user(other.id, closed.id)

      assert CoinTracker.Repo.get(CoinTracker.Trading.Position, closed.id)
    end

    test "refuses to delete an active position", %{user: user, symbol_price: symbol_price} do
      active = create_position(user.id, symbol_price.id, %{status: :active})

      assert {:error, :not_found} =
               Trading.delete_closed_position_for_user(user.id, active.id)

      assert CoinTracker.Repo.get(CoinTracker.Trading.Position, active.id)
    end

    test "returns :not_found when position id does not exist", %{user: user} do
      assert {:error, :not_found} =
               Trading.delete_closed_position_for_user(user.id, 0)
    end
  end

  defp create_signal(symbol, symbol_price_id, initial_price_usd) do
    initial_price =
      case initial_price_usd do
        nil -> nil
        v -> Decimal.new(v)
      end

    %CoinTracker.Signals.Signal{}
    |> CoinTracker.Signals.Signal.changeset(%{
      symbol: symbol,
      name: "#{symbol} Coin",
      in_top: true,
      active: true,
      position: 1,
      in_top_since: DateTime.utc_now() |> DateTime.truncate(:second),
      initial_price_usd: initial_price,
      current_price_usd: initial_price
    })
    |> Ecto.Changeset.put_change(:symbol_price_id, symbol_price_id)
    |> CoinTracker.Repo.insert!()
  end
end
