defmodule ElixirPhoenixWeb.Api.UserController do
  use ElixirPhoenixWeb, :controller

  def show(conn, %{"id" => id}) do
    include = conn.query_params["include"]
    version = get_req_header(conn, "x-api-version")

    render(conn, :show, id: id, include: include, version: version)
  end
end
