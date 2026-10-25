defmodule AppWeb.RequireGuest do
  import Plug.Conn

  def init(opts), do: opts

  # Signed-in users are sent to their dashboard; anonymous callers pass.
  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> Phoenix.Controller.redirect(to: "/dashboard")
      |> halt()
    else
      conn
    end
  end
end
