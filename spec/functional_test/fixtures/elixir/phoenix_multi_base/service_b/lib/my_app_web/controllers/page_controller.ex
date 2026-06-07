defmodule MyAppWeb.PageController do
  use MyAppWeb, :controller

  def show(conn, _params) do
    conn.query_params["b"]
  end
end
