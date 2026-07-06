defmodule CoinTrackerWeb.TutorialLive do
  use CoinTrackerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Tutorial"))}
  end
end
