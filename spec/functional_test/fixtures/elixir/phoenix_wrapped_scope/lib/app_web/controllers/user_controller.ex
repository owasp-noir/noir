defmodule AppWeb.UserController do
  use AppWeb, :controller
  def index(conn, _params) do
    conn.params["root_q"]
  end
end
