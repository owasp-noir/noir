defmodule ElixirPhoenixCalleesWeb.UserController do
  use ElixirPhoenixCalleesWeb, :controller

  def index(conn, _params) do
    page = conn.query_params["page"]
    users = UserService.list(page)
    AuditLog.write("users")
    json(conn, JsonPresenter.render(users))
  end

  def create(conn, _params) do
    payload = UserPayload.from_conn(conn)
    created = UserService.create(payload)
    conn
    |> put_status(:created)
    |> json(render_user(created))
  end
end
