defmodule AppWeb.Admin.UserController do
  use AppWeb, :controller
  def index(conn, _params) do
    conn.params["admin_q"]
  end
end
