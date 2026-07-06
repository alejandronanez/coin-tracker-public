defmodule CoinTracker.Signals.SignalPricePoller do
  @moduledoc """
  GenServer that periodically fetches and updates current prices for active signals.

  Unlike the position PricePoller which knows which exchange to query (from the position),
  this poller tries exchanges in priority order: Binance -> Bitget -> MEXC.
  It stops at the first exchange that successfully returns a price for each symbol.

  ## Configuration

  Configure in your environment config files:

      # Enable polling with 5 second interval
      config :coin_tracker, CoinTracker.Signals.SignalPricePoller,
        enabled: true,
        interval: :timer.seconds(5)

      # Disable polling (useful for test environment)
      config :coin_tracker, CoinTracker.Signals.SignalPricePoller,
        enabled: false

  ## Options

    * `:enabled` - Whether polling is enabled (default: `true`)
    * `:interval` - Polling interval in milliseconds (default: `5_000` = 5 seconds)

  The poller will start immediately and then run at the configured interval.
  Errors during polling are logged but do not crash the poller.

  Price updates are broadcast via Phoenix.PubSub on the "price_updates" topic
  to enable real-time UI updates in LiveViews.
  """

  use GenServer

  alias CoinTracker.Coins
  alias CoinTracker.Coins.PriceClient
  alias CoinTracker.Log
  alias CoinTracker.Signals

  @default_interval :timer.seconds(5)
  @exchange_priority [:binance_spot, :bitget_spot, :mexc_spot]
  # Symbols that should skip Binance due to API issues (temporary workaround).
  # PROS/USDT: Binance returns the wrong asset's price for this signal — pull
  # from Bitget/MEXC instead.
  @binance_excluded_symbols ["XMR/USDT", "PROS/USDT", "LIT/USDT"]

  # Client API

  @doc """
  Starts the poller GenServer.

  The poller can be started with custom options or will use configuration values.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers a poll immediately.

  This is useful for testing or manual operations.
  Returns `:ok` and the poll happens asynchronously.
  """
  def poll_now do
    GenServer.cast(__MODULE__, :poll)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = get_config()

    state = %{
      enabled: Keyword.get(opts, :enabled, config[:enabled]),
      interval: Keyword.get(opts, :interval, config[:interval])
    }

    if state.enabled do
      Log.info("Signal price poller starting with interval: #{state.interval}ms",
        module: :signal_price_poller,
        operation: :init
      )

      # Schedule first poll immediately
      send(self(), :poll)
      {:ok, state}
    else
      Log.info("Signal price poller disabled via configuration",
        module: :signal_price_poller,
        operation: :init
      )

      {:ok, Map.put(state, :enabled, false)}
    end
  end

  @impl true
  def handle_info(:poll, %{enabled: false} = state) do
    # Poller is disabled, don't schedule next poll
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, %{enabled: true, interval: interval} = state) do
    # Perform the poll
    perform_poll()

    # Schedule next poll
    Process.send_after(self(), :poll, interval)

    {:noreply, state}
  end

  @impl true
  def handle_cast(:poll, state) do
    perform_poll()
    {:noreply, state}
  end

  # Private functions

  defp perform_poll do
    Log.debug("Starting signal price update poll",
      module: :signal_price_poller,
      operation: :poll
    )

    # Get unique symbols from active signals
    symbols = Signals.get_unique_symbols_for_active_signals()

    if symbols == [] do
      Log.debug("No active signals found, skipping price update",
        module: :signal_price_poller,
        operation: :poll
      )
    else
      Log.debug("Fetching prices for #{length(symbols)} symbols",
        module: :signal_price_poller,
        operation: :poll,
        symbol_count: length(symbols)
      )

      # Convert symbols to USDT pairs and fetch prices
      Enum.each(symbols, fn symbol ->
        symbol_pair = "#{symbol}/USDT"
        fetch_and_update_price(symbol, symbol_pair)
      end)
    end
  end

  defp fetch_and_update_price(symbol, symbol_pair) do
    # Try exchanges in priority order (some symbols excluded from certain exchanges)
    result = try_exchanges(get_exchange_priority(symbol_pair), symbol_pair)

    case result do
      {:ok, exchange, price} ->
        # Upsert to symbol_prices table (this automatically broadcasts on "price_updates")
        case Coins.upsert_symbol_price(%{
               exchange: exchange,
               symbol_pair: symbol_pair,
               current_price: price
             }) do
          {:ok, symbol_price} ->
            # Link all signals with this symbol to this symbol_price
            Signals.link_signals_to_symbol_price(symbol, symbol_price.id)

            Log.debug("Updated price for #{symbol_pair} from #{exchange}: #{price}",
              module: :signal_price_poller,
              operation: :update_price,
              symbol: symbol_pair,
              exchange: exchange
            )

          {:error, reason} ->
            Log.db_error("Failed to upsert price for #{symbol_pair}",
              module: :signal_price_poller,
              operation: :update_price,
              symbol: symbol_pair,
              reason: inspect(reason)
            )
        end

      :not_found ->
        Log.debug("Symbol #{symbol_pair} not found on any exchange",
          module: :signal_price_poller,
          operation: :fetch_price,
          symbol: symbol_pair
        )
    end
  end

  defp try_exchanges([], _symbol_pair), do: :not_found

  defp try_exchanges([exchange | rest], symbol_pair) do
    case PriceClient.fetch_current_prices(exchange, [symbol_pair]) do
      {:ok, [price_data | _]} ->
        {:ok, exchange, price_data.price}

      {:ok, []} ->
        # No price returned, try next exchange
        try_exchanges(rest, symbol_pair)

      {:error, _} ->
        # API/network error, try next exchange
        try_exchanges(rest, symbol_pair)
    end
  end

  defp get_config do
    config = Application.get_env(:coin_tracker, __MODULE__, [])

    [
      enabled: Keyword.get(config, :enabled, true),
      interval: Keyword.get(config, :interval, @default_interval)
    ]
  end

  defp get_exchange_priority(symbol_pair) when symbol_pair in @binance_excluded_symbols do
    [:bitget_spot, :mexc_spot]
  end

  defp get_exchange_priority(_symbol_pair), do: @exchange_priority
end
