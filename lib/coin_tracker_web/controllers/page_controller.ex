defmodule CoinTrackerWeb.PageController do
  use CoinTrackerWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_scope] do
      redirect(conn, to: ~p"/signals")
    else
      conn
      |> assign(:current_scope, nil)
      |> assign(:current_path, conn.request_path)
      |> render(:home)
    end
  end
end
