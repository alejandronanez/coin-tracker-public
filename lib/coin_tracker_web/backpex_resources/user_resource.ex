defmodule CoinTrackerWeb.BackpexResources.UserResource do
  use Backpex.LiveResource,
    adapter_config: [
      schema: CoinTracker.Accounts.User,
      repo: CoinTracker.Repo,
      update_changeset: &CoinTracker.Accounts.User.admin_changeset/3,
      create_changeset: &CoinTracker.Accounts.User.admin_changeset/3
    ],
    layout: {CoinTrackerWeb.Layouts, :admin},
    per_page_default: 100

  alias CoinTracker.Accounts.User

  @impl Backpex.LiveResource
  def singular_name, do: "User"

  @impl Backpex.LiveResource
  def plural_name, do: "Users"

  def searchable, do: [:email]

  @impl Backpex.LiveResource
  def fields do
    [
      id: %{
        module: Backpex.Fields.Number,
        label: "ID",
        readonly: true
      },
      email: %{
        module: Backpex.Fields.Text,
        label: "Email"
      },
      subscription_tier: %{
        module: Backpex.Fields.Select,
        label: "Subscription Tier",
        options:
          User
          |> Ecto.Enum.values(:subscription_tier)
          |> Enum.map(fn tier ->
            {tier |> to_string() |> String.capitalize(), tier}
          end)
      },
      subscription_expires_at: %{
        module: Backpex.Fields.DateTime,
        label: "Subscription Expires At"
      },
      telegram_token: %{
        module: Backpex.Fields.Text,
        label: "Telegram Token",
        readonly: true
      },
      confirmed_at: %{
        module: Backpex.Fields.DateTime,
        label: "Confirmed At",
        readonly: true
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created",
        readonly: true
      }
    ]
  end
end
