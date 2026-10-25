defmodule AppWeb.Api.Helpers do
  import Plug.Conn

  def unauthorized(conn, msg) do
    conn
    |> put_status(401)
    |> Phoenix.Controller.json(%{error: msg})
    |> halt()
  end
end
