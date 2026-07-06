defmodule CoinTrackerWeb.BackpexResources.PositionResource do
  use Backpex.LiveResource,
    adapter_config: [
      schema: CoinTracker.Trading.Position,
      repo: CoinTracker.Repo
    ],
    layout: {CoinTrackerWeb.Layouts, :admin},
    per_page_default: 100

  @impl Backpex.LiveResource
  def singular_name, do: "Position"

  @impl Backpex.LiveResource
  def plural_name, do: "Positions"

  def searchable, do: [:closed_reason]

  @impl Backpex.LiveResource
  def fields do
    [
      id: %{
        module: Backpex.Fields.Number,
        label: "ID"
      },
      entry_price: %{
        module: Backpex.Fields.Number,
        label: "Entry Price"
      },
      stop_loss_percent: %{
        module: Backpex.Fields.Number,
        label: "Stop Loss %"
      },
      take_profit_percent: %{
        module: Backpex.Fields.Number,
        label: "Take Profit %"
      },
      status: %{
        module: Backpex.Fields.Select,
        label: "Status",
        options: [active: "Active", closed: "Closed"]
      },
      last_known_pnl: %{
        module: Backpex.Fields.Number,
        label: "Last PnL"
      },
      closed_reason: %{
        module: Backpex.Fields.Text,
        label: "Closed Reason"
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created"
      }
    ]
  end
end
