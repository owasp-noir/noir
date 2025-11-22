defmodule ElixirPhoenixWeb.FileController do
  use ElixirPhoenixWeb, :controller

  def serve(conn, %{"path" => path}) do
    # Wildcard path parameter
    send_file(conn, 200, path)
  end
end
