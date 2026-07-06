defmodule CoinTracker.Signals.MarketStatusPoller do
  @moduledoc """
  GenServer that captures market status reactively, the moment
  `CoinTracker.Signals.Poller` reports a new top-10 fingerprint.

  Market status is derived from the same data that `Poller` ingests from
  CoinScanX — the count of signals where `active: true AND in_top: true`.
  `Poller` broadcasts `{:poller_status_updated, status}` on
  `Poller.status_topic/0` only when its top-10 fingerprint actually
  changes. This GenServer subscribes to that topic and records a fresh
  `MarketStatus` row on every broadcast, plus once at boot for an initial
  baseline. There is no internal timer: captures happen exactly when the
  upstream data changed.

  ## Configuration

      config :coin_tracker, CoinTracker.Signals.MarketStatusPoller, enabled: true

  To stop captures in tests, configure `Signals.Poller, enabled: false`
  so no broadcasts fire (the boot baseline still runs unless this poller
  is also disabled — test env disables both).

  Errors during capture are logged but do not crash the GenServer.
  """

  use GenServer

  alias CoinTracker.Accounts
  alias CoinTracker.Log
  alias CoinTracker.Signals
  alias CoinTracker.Signals.Poller
  alias CoinTracker.TelegramClient.TelegramService

  # Client API

  @doc """
  Starts the market status poller GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers a market status capture immediately.

  Bypasses the reactive subscription path. Useful for manual ops and tests.
  Returns `:ok`; the capture happens asynchronously.
  """
  def capture_now do
    GenServer.cast(__MODULE__, :capture)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = get_config()
    enabled = Keyword.get(opts, :enabled, config[:enabled])

    if enabled do
      Phoenix.PubSub.subscribe(CoinTracker.PubSub, Poller.status_topic())

      Log.info("Market status poller subscribed to #{Poller.status_topic()}",
        module: :market_status_poller,
        operation: :init
      )

      send(self(), :initial_capture)
      {:ok, %{enabled: true}}
    else
      Log.info("Market status poller disabled via configuration",
        module: :market_status_poller,
        operation: :init
      )

      {:ok, %{enabled: false}}
    end
  end

  @impl true
  def handle_info(:initial_capture, state) do
    perform_capture()
    {:noreply, state}
  end

  @impl true
  def handle_info({:poller_status_updated, _status}, state) do
    perform_capture()
    {:noreply, state}
  end

  @impl true
  def handle_cast(:capture, state) do
    perform_capture()
    {:noreply, state}
  end

  # Private functions

  defp perform_capture do
    Log.debug("Starting market status capture",
      module: :market_status_poller,
      operation: :capture
    )

    previous_status = Signals.get_latest_market_status()

    case Signals.create_market_status() do
      {:ok, market_status} ->
        Log.info(
          "Market status captured: #{market_status.active_signals_count} active signals in top 10",
          module: :market_status_poller,
          operation: :capture
        )

        maybe_send_market_alert(previous_status, market_status)

      {:error, changeset} ->
        Log.db_error("Failed to capture market status",
          module: :market_status_poller,
          operation: :capture,
          reason: inspect(changeset.errors)
        )
    end
  end

  defp maybe_send_market_alert(nil, _current), do: :ok

  defp maybe_send_market_alert(previous, current) do
    prev_count = previous.active_signals_count
    curr_count = current.active_signals_count

    message =
      cond do
        prev_count != 10 and curr_count == 10 -> "🟢 Market: 10/10"
        prev_count == 10 and curr_count != 10 -> "🔴 Market: #{curr_count}/10"
        true -> nil
      end

    if message do
      user_ids = Accounts.list_pro_users_with_telegram() |> Enum.map(& &1.id)
      TelegramService.broadcast_message(user_ids, message, kind: :market_status)
    else
      :ok
    end
  end

  defp get_config do
    config = Application.get_env(:coin_tracker, __MODULE__, [])
    [enabled: Keyword.get(config, :enabled, true)]
  end
end
