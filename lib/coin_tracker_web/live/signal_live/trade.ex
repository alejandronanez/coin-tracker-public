defmodule CoinTrackerWeb.SignalLive.Trade do
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Accounts
  alias CoinTracker.Coins.TradingClient
  alias CoinTracker.Signals
  alias CoinTracker.Trading.AutoBuy

  @default_take_profit 15
  @default_stop_loss 20

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Signals.get_signal_with_price(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Signal not found"))
         |> push_navigate(to: ~p"/signals")}

      signal ->
        has_credentials = Accounts.has_exchange_credential?(user.id, :binance_spot)

        if connected?(socket) do
          Phoenix.PubSub.subscribe(CoinTracker.PubSub, "price_updates")

          if has_credentials do
            send(self(), :fetch_balance)
          end
        end

        {:ok,
         socket
         |> assign(:page_title, gettext("Trade %{symbol}", symbol: signal.symbol))
         |> assign(:current_path, ~p"/signals/#{id}/trade")
         |> assign(:signal, signal)
         |> assign(:has_credentials, has_credentials)
         |> assign(:step, :form)
         |> assign(:current_price, signal.symbol_price && signal.symbol_price.current_price)
         |> assign(:trade_error, nil)
         |> assign(:available_balance, nil)
         |> assign_form_defaults()}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      page_title={@page_title}
      current_path={@current_path}
    >
      <div class="max-w-lg mx-auto">
        <%!-- Header --%>
        <div class="mb-6">
          <.link
            navigate={~p"/signals/#{@signal.id}"}
            class="text-sm text-zinc-500 dark:text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200 flex items-center gap-1 mb-2"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" />
            {gettext("Back to signal")}
          </.link>
          <h1 class="text-lg font-semibold text-zinc-900 dark:text-white">
            {gettext("Trade %{symbol}", symbol: @signal.symbol)}
          </h1>
          <%= if @current_price do %>
            <p class="text-sm text-zinc-500 dark:text-zinc-400 mt-1">
              {gettext("Current price:")}
              <span class="font-mono font-medium text-zinc-900 dark:text-white">
                ${format_price(@current_price)}
              </span>
            </p>
          <% end %>
        </div>

        <%!-- No Credentials Warning --%>
        <%= unless @has_credentials do %>
          <div class="rounded-lg border border-amber-200 dark:border-amber-800/50 bg-amber-50 dark:bg-amber-900/20 p-6 text-center">
            <.icon name="hero-key" class="w-8 h-8 text-amber-500 mx-auto mb-3" />
            <p class="text-sm font-medium text-amber-800 dark:text-amber-200 mb-2">
              {gettext("Exchange credentials required")}
            </p>
            <p class="text-xs text-amber-700 dark:text-amber-300 mb-4">
              {gettext("You need to set up your Binance API key before you can trade.")}
            </p>
            <.link
              navigate={~p"/settings/exchange-keys"}
              class="inline-flex items-center gap-2 rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white hover:bg-amber-700"
            >
              <.icon name="hero-key" class="w-4 h-4" />
              {gettext("Set up API keys")}
            </.link>
          </div>
        <% end %>

        <%!-- Form Step --%>
        <%= if @has_credentials && @step == :form do %>
          <.form
            for={@form}
            id="trade-form"
            phx-change="validate"
            phx-submit="preview"
            class="space-y-4"
          >
            <div>
              <.input
                field={@form[:amount]}
                type="number"
                label={gettext("Amount (USDT)")}
                step="any"
                min="0"
                placeholder="100"
              />
              <div class="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
                <%= case @available_balance do %>
                  <% nil -> %>
                    <span class="inline-flex items-center gap-1">
                      <span class="w-3 h-3 border-2 border-zinc-300 dark:border-zinc-600 border-t-zinc-500 dark:border-t-zinc-300 rounded-full animate-spin inline-block" />
                      {gettext("Loading balance...")}
                    </span>
                  <% {:ok, balance} -> %>
                    <span id="available-balance">
                      {gettext("Available:")}
                      <span class="font-mono font-medium text-zinc-700 dark:text-zinc-200">
                        ${format_price(balance)} USDT
                      </span>
                    </span>
                  <% {:error, _} -> %>
                    <span class="text-amber-500 dark:text-amber-400">
                      {gettext("Could not load balance")}
                    </span>
                <% end %>
              </div>
            </div>
            <.input
              field={@form[:take_profit]}
              type="number"
              label={gettext("Take Profit (%)")}
              step="any"
              min="0"
            />
            <.input
              field={@form[:stop_loss]}
              type="number"
              label={gettext("Stop Loss (%)")}
              step="any"
              min="0"
            />

            <button
              type="submit"
              class="w-full rounded-md bg-zinc-900 dark:bg-white px-4 py-2.5 text-sm font-semibold text-white dark:text-zinc-900 hover:bg-zinc-700 dark:hover:bg-zinc-200"
            >
              {gettext("Preview Order")}
            </button>
          </.form>
        <% end %>

        <%!-- Preview Step --%>
        <%= if @step == :preview do %>
          <div id="trade-preview" class="space-y-4">
            <div class="rounded-lg border border-zinc-200 dark:border-white/10 divide-y divide-zinc-200 dark:divide-white/10">
              <.preview_row label={gettext("Amount")} value={"$#{@form_data.amount} USDT"} />
              <.preview_row
                label={gettext("Est. Quantity")}
                value={format_quantity(@preview.estimated_qty)}
              />
              <.preview_row
                label={gettext("Take Profit")}
                value={"$#{format_price(@preview.tp_price)} (+#{@form_data.take_profit}%)"}
                class="text-green-600 dark:text-green-400"
              />
              <.preview_row
                label={gettext("Stop Loss")}
                value={"$#{format_price(@preview.sl_price)} (-#{@form_data.stop_loss}%)"}
                class="text-red-600 dark:text-red-400"
              />
              <.preview_row
                label={gettext("Est. Profit")}
                value={"+$#{format_price(@preview.est_profit)}"}
                class="text-green-600 dark:text-green-400"
              />
              <.preview_row
                label={gettext("Est. Loss")}
                value={"-$#{format_price(@preview.est_loss)}"}
                class="text-red-600 dark:text-red-400"
              />
            </div>

            <div class="rounded-md bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800/50 p-3">
              <p class="text-xs text-blue-700 dark:text-blue-300">
                {gettext(
                  "This places a real market buy + OCO sell order on Binance. The exchange manages TP/SL automatically. You will need to close the app position manually when the OCO fills."
                )}
              </p>
            </div>

            <div class="flex gap-3">
              <button
                id="edit-btn"
                phx-click="edit"
                class="flex-1 rounded-md border border-zinc-300 dark:border-white/10 px-4 py-2.5 text-sm font-medium text-zinc-700 dark:text-zinc-300 hover:bg-zinc-50 dark:hover:bg-white/5"
              >
                {gettext("Edit")}
              </button>
              <button
                id="confirm-btn"
                phx-click="confirm"
                class="flex-1 rounded-md bg-green-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-green-700"
              >
                {gettext("Confirm & Buy")}
              </button>
            </div>
          </div>
        <% end %>

        <%!-- Executing Step --%>
        <%= if @step == :executing do %>
          <div id="trade-executing" class="space-y-3">
            <div class="rounded-lg border border-zinc-200 dark:border-white/10 p-4">
              <.execution_step label={gettext("Placing market buy...")} status={:in_progress} />
              <.execution_step label={gettext("Placing OCO sell order...")} status={:pending} />
              <.execution_step label={gettext("Creating position...")} status={:pending} />
            </div>
            <p class="text-xs text-center text-zinc-500 dark:text-zinc-400">
              {gettext("Do not close this page.")}
            </p>
          </div>
        <% end %>

        <%!-- Success Result --%>
        <%!-- (handled via redirect in handle_info) --%>

        <%!-- Failure --%>
        <%= if @step == :error do %>
          <div id="trade-error" class="space-y-4">
            <div class="rounded-lg border border-red-200 dark:border-red-800/50 bg-red-50 dark:bg-red-900/20 p-4">
              <div class="flex items-start gap-3">
                <.icon name="hero-x-circle" class="w-5 h-5 text-red-500 flex-shrink-0 mt-0.5" />
                <div>
                  <p class="text-sm font-medium text-red-800 dark:text-red-200">
                    {gettext("Trade failed")}
                  </p>
                  <p class="text-xs text-red-700 dark:text-red-300 mt-1 font-mono">
                    {format_trade_error(@trade_error)}
                  </p>
                </div>
              </div>
            </div>

            <button
              id="go-back-btn"
              phx-click="edit"
              class="w-full rounded-md border border-zinc-300 dark:border-white/10 px-4 py-2.5 text-sm font-medium text-zinc-700 dark:text-zinc-300 hover:bg-zinc-50 dark:hover:bg-white/5"
            >
              {gettext("Go back")}
            </button>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # --- Components ---

  defp preview_row(assigns) do
    assigns = assign_new(assigns, :class, fn -> "text-zinc-900 dark:text-white" end)

    ~H"""
    <div class="flex justify-between items-center px-4 py-3">
      <span class="text-sm text-zinc-500 dark:text-zinc-400">{@label}</span>
      <span class={["text-sm font-medium font-mono", @class]}>{@value}</span>
    </div>
    """
  end

  defp execution_step(assigns) do
    ~H"""
    <div class="flex items-center gap-3 py-2">
      <%= case @status do %>
        <% :in_progress -> %>
          <div class="w-4 h-4 border-2 border-zinc-300 dark:border-zinc-600 border-t-zinc-900 dark:border-t-white rounded-full animate-spin" />
        <% :pending -> %>
          <div class="w-4 h-4 rounded-full border-2 border-zinc-200 dark:border-zinc-700" />
        <% :done -> %>
          <.icon name="hero-check-circle" class="w-4 h-4 text-green-500" />
      <% end %>
      <span class={[
        "text-sm",
        if(@status == :pending,
          do: "text-zinc-400 dark:text-zinc-500",
          else: "text-zinc-900 dark:text-white"
        )
      ]}>
        {@label}
      </span>
    </div>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("validate", %{"trade" => params}, socket) do
    form = to_form(params, as: :trade)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("preview", %{"trade" => params}, socket) do
    amount = parse_decimal(params["amount"])
    take_profit = parse_decimal(params["take_profit"])
    stop_loss = parse_decimal(params["stop_loss"])

    cond do
      is_nil(amount) or Decimal.lte?(amount, 0) ->
        {:noreply, put_flash(socket, :error, gettext("Amount must be a positive number"))}

      is_nil(take_profit) or Decimal.lte?(take_profit, 0) ->
        {:noreply,
         put_flash(socket, :error, gettext("Take profit must be a positive percentage"))}

      is_nil(stop_loss) or Decimal.lte?(stop_loss, 0) ->
        {:noreply, put_flash(socket, :error, gettext("Stop loss must be a positive percentage"))}

      true ->
        current_price = socket.assigns.current_price
        estimated_qty = Decimal.div(amount, current_price)
        tp_price = Decimal.mult(current_price, Decimal.add(1, Decimal.div(take_profit, 100)))
        sl_price = Decimal.mult(current_price, Decimal.sub(1, Decimal.div(stop_loss, 100)))
        est_profit = Decimal.mult(amount, Decimal.div(take_profit, 100))
        est_loss = Decimal.mult(amount, Decimal.div(stop_loss, 100))

        form_data = %{
          amount: Decimal.to_string(amount),
          take_profit: Decimal.to_string(take_profit),
          stop_loss: Decimal.to_string(stop_loss)
        }

        preview = %{
          estimated_qty: estimated_qty,
          tp_price: tp_price,
          sl_price: sl_price,
          est_profit: est_profit,
          est_loss: est_loss
        }

        {:noreply,
         socket
         |> assign(:step, :preview)
         |> assign(:form_data, form_data)
         |> assign(:preview, preview)}
    end
  end

  def handle_event("edit", _params, socket) do
    form_data = Map.get(socket.assigns, :form_data, nil)

    socket =
      if form_data do
        form =
          to_form(
            %{
              "amount" => form_data.amount,
              "take_profit" => form_data.take_profit,
              "stop_loss" => form_data.stop_loss
            },
            as: :trade
          )

        assign(socket, :form, form)
      else
        socket
      end

    {:noreply, assign(socket, :step, :form)}
  end

  def handle_event("confirm", _params, socket) do
    user = socket.assigns.current_scope.user
    signal = socket.assigns.signal
    form_data = socket.assigns.form_data

    amount = Decimal.new(form_data.amount)

    trade_params = %{
      take_profit: form_data.take_profit,
      stop_loss: form_data.stop_loss
    }

    lv_pid = self()

    Task.Supervisor.start_child(CoinTracker.TaskSupervisor, fn ->
      result = AutoBuy.execute(user, signal, amount, trade_params)
      send(lv_pid, {:trade_result, result})
    end)

    {:noreply, assign(socket, :step, :executing)}
  end

  @impl true
  def handle_info({:trade_result, {:ok, _result}}, socket) do
    symbol = socket.assigns.signal.symbol

    {:noreply,
     socket
     |> put_flash(
       :info,
       gettext("Bought %{symbol}. OCO order placed on Binance.", symbol: symbol)
     )
     |> push_navigate(to: ~p"/positions")}
  end

  def handle_info({:trade_result, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:step, :error)
     |> assign(:trade_error, reason)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, socket) do
    {:noreply,
     socket
     |> assign(:step, :error)
     |> assign(:trade_error, {:unexpected_crash, reason})}
  end

  def handle_info(:fetch_balance, socket) do
    user = socket.assigns.current_scope.user
    exchange = socket.assigns.signal.symbol_price.exchange
    lv_pid = self()

    Task.Supervisor.start_child(CoinTracker.TaskSupervisor, fn ->
      result =
        case Accounts.get_exchange_credential(user.id, exchange) do
          nil ->
            {:error, :no_credentials}

          credential ->
            case TradingClient.fetch_balance(exchange, credential, "USDT") do
              {:ok, %{free: free}} -> {:ok, free}
              {:error, _reason} -> {:error, :fetch_failed}
            end
        end

      send(lv_pid, {:balance_result, result})
    end)

    {:noreply, socket}
  end

  def handle_info({:balance_result, result}, socket) do
    {:noreply, assign(socket, :available_balance, result)}
  end

  def handle_info({:price_updated, symbol_price}, socket) do
    signal = socket.assigns.signal

    if signal.symbol_price && symbol_price.symbol_pair == signal.symbol_price.symbol_pair &&
         symbol_price.exchange == signal.symbol_price.exchange do
      {:noreply, assign(socket, :current_price, symbol_price.current_price)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp assign_form_defaults(socket) do
    form =
      to_form(
        %{
          "amount" => "",
          "take_profit" => "#{@default_take_profit}",
          "stop_loss" => "#{@default_stop_loss}"
        },
        as: :trade
      )

    socket
    |> assign(:form, form)
    |> assign(:form_data, nil)
    |> assign(:preview, nil)
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(val) when is_binary(val) do
    case Decimal.parse(val) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp format_price(nil), do: "—"
  defp format_price(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp format_quantity(nil), do: "—"
  defp format_quantity(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string(:normal)

  defp format_trade_error({:oco_failed, %{reason: reason}}) do
    "Market buy succeeded, but OCO order failed: #{format_trade_error(reason)}. " <>
      "You have an unprotected position on Binance — please place a stop-loss manually."
  end

  defp format_trade_error({:insufficient_balance, msg}), do: "Insufficient balance: #{msg}"
  defp format_trade_error({:invalid_symbol, msg}), do: "Invalid symbol: #{msg}"
  defp format_trade_error({:auth_error, msg}), do: "Authentication error: #{msg}"
  defp format_trade_error({:price_rule_violation, msg}), do: "Price rule violation: #{msg}"
  defp format_trade_error({:exchange_not_supported, msg}), do: msg
  defp format_trade_error(:no_credentials), do: "No exchange credentials found"
  defp format_trade_error(other), do: inspect(other)
end
