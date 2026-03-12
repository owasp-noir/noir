defmodule MyappWeb.PublicController do
  use MyappWeb, :controller

  def index(conn, _params) do
    json(conn, %{message: "public"})
  end
end
