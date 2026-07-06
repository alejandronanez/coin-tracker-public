defmodule CoinTrackerWeb.BackpexResources.SignalResource do
  use Backpex.LiveResource,
    adapter_config: [
      schema: CoinTracker.Signals.Signal,
      repo: CoinTracker.Repo,
      update_changeset: &CoinTracker.Signals.Signal.admin_changeset/3,
      create_changeset: &CoinTracker.Signals.Signal.admin_changeset/3
    ],
    layout: {CoinTrackerWeb.Layouts, :admin},
    per_page_default: 100

  @impl Backpex.LiveResource
  def singular_name, do: "Signal"

  @impl Backpex.LiveResource
  def plural_name, do: "Signals"

  @impl Backpex.LiveResource
  def fields do
    [
      id: %{
        module: Backpex.Fields.Number,
        label: "ID",
        readonly: true
      },
      symbol: %{
        module: Backpex.Fields.Text,
        label: "Symbol",
        searchable: true
      },
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true
      },
      initial_price_usd: %{
        module: Backpex.Fields.Number,
        label: "Initial Price"
      },
      price_after_7d: %{
        module: Backpex.Fields.Number,
        label: "Price After 7d"
      },
      price_after_14d: %{
        module: Backpex.Fields.Number,
        label: "Price After 14d"
      },
      max_price_usd: %{
        module: Backpex.Fields.Number,
        label: "Max Price (USD)"
      },
      max_increase_percentage: %{
        module: Backpex.Fields.Number,
        label: "Max Increase %"
      },
      in_top: %{
        module: Backpex.Fields.Boolean,
        label: "In Top"
      },
      active: %{
        module: Backpex.Fields.Boolean,
        label: "Active"
      },
      in_top_since: %{
        module: Backpex.Fields.DateTime,
        label: "In Top Since"
      },
      exit_date: %{
        module: Backpex.Fields.DateTime,
        label: "Exit Date"
      },
      current_volume_24h: %{
        module: Backpex.Fields.Number,
        label: "Volume (24h)"
      }
    ]
  end
end
