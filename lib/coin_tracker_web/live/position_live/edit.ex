defmodule CoinTrackerWeb.PositionLive.Edit do
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

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Trading.get_position_for_user(id, user_id) do
      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Position not found"))
         |> push_navigate(to: ~p"/positions")}

      {:ok, position} ->
        # Create changeset from existing position with formatted decimal values
        formatted_position = %{
          position
          | entry_price: format_decimal_to_value(position.entry_price),
            stop_loss_percent: format_decimal_to_value(position.stop_loss_percent),
            take_profit_percent: format_decimal_to_value(position.take_profit_percent),
            amount_invested: format_decimal_to_value(position.amount_invested),
            current_threshold_zone: format_decimal_to_value(position.current_threshold_zone)
        }

        changeset = Position.changeset(formatted_position, %{})

        preview_prices = calculate_preview_prices(changeset)

        {:ok,
         socket
         |> assign(:page_title, gettext("Edit Position"))
         |> assign(:position, position)
         |> assign(:form, to_form(changeset))
         |> assign(:preview_prices, preview_prices)}
    end
  end

  @impl true
  def handle_event("validate", %{"position" => position_params}, socket) do
    position_params = normalize_decimal_params(position_params)

    changeset =
      socket.assigns.position
      |> Position.changeset(position_params)
      |> Map.put(:action, :validate)

    preview_prices = calculate_preview_prices(changeset)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:preview_prices, preview_prices)}
  end

  @impl true
  def handle_event("save", %{"position" => position_params}, socket) do
    position_params = normalize_decimal_params(position_params)
    user_id = socket.assigns.current_scope.user.id
    position_id = socket.assigns.position.id

    case Trading.update_position(position_id, user_id, position_params) do
      {:ok, _position} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Position updated successfully"))
         |> push_navigate(to: ~p"/positions")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Position not found"))
         |> push_navigate(to: ~p"/positions")}
    end
  end

  # Helper functions for template formatting

  defp format_exchange(:binance_spot), do: "Binance"
  defp format_exchange(:bitget_spot), do: "Bitget"
  defp format_exchange(:mexc_spot), do: "MEXC"
  defp format_exchange(exchange), do: exchange |> to_string() |> String.capitalize()

  defp format_decimal_to_value(decimal) when is_struct(decimal, Decimal) do
    decimal
    |> Decimal.to_string(:normal)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp format_decimal_to_value(value), do: value
end
