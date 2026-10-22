defmodule HelloWeb.PageController do
  use HelloWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
