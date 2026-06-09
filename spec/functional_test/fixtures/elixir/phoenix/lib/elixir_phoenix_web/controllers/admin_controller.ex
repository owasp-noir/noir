defmodule ElixirPhoenixWeb.AdminController do
  use ElixirPhoenixWeb, :controller

  def dashboard(conn, _params) do
    AdminAudit.record(conn)
    json(conn, %{ok: true})
  end

  def preflight(conn, _params) do
    send_resp(conn, 204, "")
  end
end
