defmodule CoinTrackerWeb.SettingsLive.ExchangeKeys do
  use CoinTrackerWeb, :live_view

  alias CoinTracker.Accounts
  alias CoinTracker.Accounts.ExchangeCredential

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    credentials = Accounts.list_exchange_credentials(user.id)

    {:ok,
     socket
     |> assign(:page_title, gettext("Exchange API Keys"))
     |> assign(:current_path, ~p"/settings/exchange-keys")
     |> assign(:credentials, credentials)
     |> assign(:show_form, credentials == [])
     |> assign(:delete_id, nil)
     |> assign_form(ExchangeCredential.changeset(%ExchangeCredential{}, %{}))}
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
      <div class="max-w-2xl mx-auto space-y-8">
        <div>
          <.link
            navigate={~p"/users/settings"}
            class="inline-flex items-center gap-1 text-sm text-zinc-500 dark:text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200 mb-4"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" />
            {gettext("Back to Settings")}
          </.link>
          <h1 class="text-lg font-semibold text-zinc-900 dark:text-white">
            {gettext("Exchange API Keys")}
          </h1>
          <p class="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
            {gettext("Manage your exchange API credentials for automatic trading.")}
          </p>
        </div>

        <%!-- Existing Credentials --%>
        <%= if @credentials != [] do %>
          <div class="space-y-3">
            <h2 class="text-sm font-medium text-zinc-900 dark:text-white">
              {gettext("Saved Credentials")}
            </h2>

            <div
              :for={cred <- @credentials}
              class="flex items-center justify-between rounded-lg border border-zinc-200 dark:border-white/10 px-4 py-3"
            >
              <div>
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium text-zinc-900 dark:text-white">
                    {format_exchange(cred.exchange)}
                  </span>
                  <%= if cred.label do %>
                    <span class="text-xs text-zinc-500 dark:text-zinc-400">
                      ({cred.label})
                    </span>
                  <% end %>
                </div>
                <div class="mt-1 text-xs text-zinc-500 dark:text-zinc-400 font-mono">
                  {ExchangeCredential.api_key_prefix(cred)}
                </div>
                <%= if cred.last_used_at do %>
                  <div class="mt-1 text-xs text-zinc-400 dark:text-zinc-500">
                    {gettext("Last used: %{date}",
                      date: Calendar.strftime(cred.last_used_at, "%Y-%m-%d %H:%M UTC")
                    )}
                  </div>
                <% end %>
              </div>

              <div>
                <%= if @delete_id == cred.id do %>
                  <div class="flex items-center gap-2">
                    <button
                      id={"confirm-delete-#{cred.id}"}
                      phx-click="confirm_delete"
                      phx-value-id={cred.id}
                      class="text-xs text-red-600 dark:text-red-400 font-medium hover:underline"
                    >
                      {gettext("Confirm")}
                    </button>
                    <button
                      phx-click="cancel_delete"
                      class="text-xs text-zinc-500 hover:underline"
                    >
                      {gettext("Cancel")}
                    </button>
                  </div>
                <% else %>
                  <button
                    id={"delete-#{cred.id}"}
                    phx-click="delete"
                    phx-value-id={cred.id}
                    class="text-xs text-red-600 dark:text-red-400 hover:underline"
                  >
                    {gettext("Remove")}
                  </button>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Add Credential Form --%>
        <%= if @show_form do %>
          <div class="rounded-lg border border-zinc-200 dark:border-white/10 p-6">
            <h2 class="text-sm font-medium text-zinc-900 dark:text-white mb-4">
              {gettext("Add Exchange Credential")}
            </h2>

            <%!-- Guidance text --%>
            <div class="mb-6 rounded-md bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800/50 p-4">
              <div class="flex gap-3">
                <.icon
                  name="hero-exclamation-triangle"
                  class="h-5 w-5 text-amber-500 flex-shrink-0 mt-0.5"
                />
                <div class="text-sm text-amber-800 dark:text-amber-200 space-y-2">
                  <p class="font-medium">{gettext("Binance API Key Setup Guide")}</p>
                  <ul class="list-disc pl-4 space-y-1 text-xs">
                    <li>{gettext("Enable \"Spot Trading\" permission only")}</li>
                    <li>{gettext("Do NOT enable withdrawal permissions")}</li>
                    <li>
                      {gettext("Restrict to your IP address for maximum security (recommended)")}
                    </li>
                    <li>{gettext("Your keys are encrypted at rest with AES-256-GCM")}</li>
                  </ul>
                </div>
              </div>
            </div>

            <.form
              for={@form}
              id="credential-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-4"
            >
              <.input
                field={@form[:exchange]}
                type="select"
                label={gettext("Exchange")}
                options={[
                  {gettext("Binance Spot"), "binance_spot"}
                ]}
              />
              <.input
                field={@form[:label]}
                type="text"
                label={gettext("Label (optional)")}
                placeholder={gettext("e.g., Main account")}
              />
              <.input
                field={@form[:api_key]}
                type="password"
                label={gettext("API Key")}
                autocomplete="off"
              />
              <.input
                field={@form[:api_secret]}
                type="password"
                label={gettext("API Secret")}
                autocomplete="off"
              />

              <div class="flex items-center gap-3 pt-2">
                <button
                  type="submit"
                  class="rounded-md bg-zinc-900 dark:bg-white px-4 py-2 text-sm font-semibold text-white dark:text-zinc-900 hover:bg-zinc-700 dark:hover:bg-zinc-200"
                >
                  {gettext("Save Credential")}
                </button>
                <%= if @credentials != [] do %>
                  <button
                    type="button"
                    phx-click="toggle_form"
                    class="text-sm text-zinc-500 hover:underline"
                  >
                    {gettext("Cancel")}
                  </button>
                <% end %>
              </div>
            </.form>
          </div>
        <% else %>
          <button
            id="add-credential-btn"
            phx-click="toggle_form"
            class="flex items-center gap-2 text-sm font-medium text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-white"
          >
            <.icon name="hero-plus" class="w-4 h-4" />
            {gettext("Add Exchange Credential")}
          </button>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"exchange_credential" => params}, socket) do
    changeset =
      %ExchangeCredential{}
      |> ExchangeCredential.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"exchange_credential" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.create_exchange_credential(user.id, params) do
      {:ok, _credential} ->
        credentials = Accounts.list_exchange_credentials(user.id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Credential saved successfully."))
         |> assign(:credentials, credentials)
         |> assign(:show_form, false)
         |> assign_form(ExchangeCredential.changeset(%ExchangeCredential{}, %{}))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :delete_id, String.to_integer(id))}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_id, nil)}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    credential_id = String.to_integer(id)

    credential =
      Enum.find(socket.assigns.credentials, &(&1.id == credential_id))

    if credential && credential.user_id == user.id do
      {:ok, _} = Accounts.delete_exchange_credential(credential)
      credentials = Accounts.list_exchange_credentials(user.id)

      {:noreply,
       socket
       |> put_flash(:info, gettext("Credential removed."))
       |> assign(:credentials, credentials)
       |> assign(:delete_id, nil)
       |> assign(:show_form, credentials == [])}
    else
      {:noreply, put_flash(socket, :error, gettext("Credential not found."))}
    end
  end

  def handle_event("toggle_form", _params, socket) do
    {:noreply, assign(socket, :show_form, !socket.assigns.show_form)}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp format_exchange("binance_spot"), do: "Binance Spot"
  defp format_exchange("bitget_spot"), do: "Bitget Spot"
  defp format_exchange("mexc_spot"), do: "MEXC Spot"
  defp format_exchange(other), do: other
end
