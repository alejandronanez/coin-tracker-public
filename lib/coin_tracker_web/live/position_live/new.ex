defmodule CoinTrackerWeb.PositionLive.New do
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Trading
  alias CoinTracker.Trading.Position

  import CoinTrackerWeb.PositionLive.Helpers,
    only: [
      format_price: 1,
      format_pnl: 1,
      format_pnl_percent: 1,
      calculate_preview_prices: 1,
      normalize_decimal_params: 1
    ]

  @exchange_options [
    {"Binance Spot", "binance_spot"},
    {"Bitget Spot", "bitget_spot"},
    {"MEXC Spot", "mexc_spot"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    # Create a changeset with defaults: threshold of 2 and binance_spot exchange
    changeset =
      Position.create_changeset(%Position{}, %{
        "current_threshold_zone" => "2",
        "exchange" => "binance_spot"
      })

    {:ok,
     socket
     |> assign(:page_title, gettext("New Position"))
     |> assign(:form, to_form(changeset))
     |> assign(:exchange_options, @exchange_options)
     |> assign(:preview_prices, nil)
     |> assign(:form_touched, false)}
  end

  @impl true
  def handle_event("validate", %{"position" => position_params}, socket) do
    position_params =
      position_params
      |> normalize_decimal_params()
      |> ensure_negative_stop_loss()

    # Only show validation errors if the form has been touched by the user
    changeset =
      %Position{}
      |> Position.create_changeset(position_params)
      |> then(fn cs ->
        if socket.assigns.form_touched do
          Map.put(cs, :action, :validate)
        else
          cs
        end
      end)

    preview_prices = calculate_preview_prices(changeset)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:preview_prices, preview_prices)
     |> assign(:form_touched, true)}
  end

  @impl true
  def handle_event("save", %{"position" => position_params}, socket) do
    position_params =
      position_params
      |> normalize_decimal_params()
      |> ensure_negative_stop_loss()

    user_id = socket.assigns.current_scope.user.id

    # Pass http_client option if in test mode (for mocking)
    opts =
      if Application.get_env(:coin_tracker, :env) == :test do
        [http_client: CoinTracker.Coins.HTTPClientMock]
      else
        []
      end

    case Trading.create_position(user_id, position_params, opts) do
      {:ok, _position} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Position created successfully"))
         |> push_navigate(to: ~p"/positions")}

      {:error, %Ecto.Changeset{} = changeset} ->
        # Mark form as touched when there's a save error to ensure errors are shown
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> assign(:form_touched, true)}
    end
  end

  # Ensures stop_loss_percent value is negative by prepending "-" if needed.
  # Skips conversion for empty strings and "0" values.
  defp ensure_negative_stop_loss(position_params) do
    case Map.get(position_params, "stop_loss_percent") do
      nil ->
        position_params

      "" ->
        position_params

      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" or trimmed == "0" do
          position_params
        else
          normalized = "-" <> String.trim_leading(trimmed, "-")
          Map.put(position_params, "stop_loss_percent", normalized)
        end

      _ ->
        position_params
    end
  end
end
