defmodule ElixirPlug.ApiRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/status" do
    send_resp(conn, 200, "API is running")
  end

  post "/data" do
    send_resp(conn, 200, "Data received")
  end

  get "/data/:type" do
    type = conn.path_params["type"]
    send_resp(conn, 200, "Data type: #{type}")
  end

  match _ do
    send_resp(conn, 404, "API endpoint not found")
  end
end