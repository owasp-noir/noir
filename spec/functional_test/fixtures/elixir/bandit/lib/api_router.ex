defmodule ElixirBandit.ApiRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/status" do
    send_resp(conn, 200, "ok")
  end

  post "/items" do
    title = conn.body_params["title"]
    send_resp(conn, 201, "created")
  end

  get "/items/:id" do
    id = conn.path_params["id"]
    send_resp(conn, 200, "item #{id}")
  end
end
