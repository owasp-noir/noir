defmodule ElixirPhoenixWeb.CommentController do
  use ElixirPhoenixWeb, :controller

  def index(conn, _params) do
    # Query parameters
    post_id = conn.query_params["post_id"]
    
    render(conn, :index)
  end

  def show(conn, %{"id" => id}) do
    render(conn, :show)
  end
end
