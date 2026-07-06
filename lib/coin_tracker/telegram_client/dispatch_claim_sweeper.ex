defmodule CoinTracker.TelegramClient.DispatchClaimSweeper do
  @moduledoc """
  Periodically prunes expired rows from `telegram_dispatch_claims`.

  The dedup window is `DispatchClaim.window_seconds/0`. Rows older than
  `window_seconds * 4` are no longer useful for suppression and can be deleted.
  Every clustered node runs its own sweeper; the DELETE is idempotent and
  cheap with the `inserted_at` index.
  """
  use GenServer

  alias CoinTracker.Log
  alias CoinTracker.TelegramClient.DispatchClaim

  @default_sweep_interval :timer.minutes(10)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :sweep_interval, sweep_interval())
    schedule_sweep(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:sweep, %{interval: interval} = state) do
    case DispatchClaim.prune(DispatchClaim.window_seconds() * 4) do
      {:ok, deleted} when deleted > 0 ->
        Log.debug("Pruned #{deleted} dispatch claim rows",
          module: :telegram,
          operation: :sweep_dispatch_claims
        )

      _ ->
        :ok
    end

    schedule_sweep(interval)
    {:noreply, state}
  end

  defp schedule_sweep(interval) do
    Process.send_after(self(), :sweep, interval)
  end

  defp sweep_interval do
    Application.get_env(:coin_tracker, __MODULE__, [])
    |> Keyword.get(:sweep_interval, @default_sweep_interval)
  end
end
