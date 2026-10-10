defmodule AppWeb.Api.UserController do
  use AppWeb, :controller
  def index(conn, _params) do
    conn.params["api_q"]
  end
end
