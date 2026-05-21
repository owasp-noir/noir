defmodule ElixirBandit.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/health" do
    send_resp(conn, 200, "ok")
  end

  get "/search" do
    query = conn.query_params["q"]
    page = conn.params["page"]
    send_resp(conn, 200, "results for: #{query}")
  end

  post "/users" do
    name = conn.body_params["name"]
    email = conn.params["email"]
    send_resp(conn, 201, "created #{name}")
  end

  put "/users/:id" do
    id = conn.path_params["id"]
    send_resp(conn, 200, "updated #{id}")
  end

  delete "/users/:id" do
    send_resp(conn, 204, "")
  end

  patch "/users/:id/profile" do
    send_resp(conn, 200, "profile updated")
  end

  get "/protected" do
    auth = get_req_header(conn, "authorization")
    send_resp(conn, 200, "protected")
  end

  get "/session" do
    sid = conn.cookies["session_id"]
    send_resp(conn, 200, "session")
  end

  head "/ping" do
    send_resp(conn, 200, "")
  end

  options "/_/*path" do
    send_resp(conn, 204, "")
  end

  match "/webhook", via: [:post, :put] do
    send_resp(conn, 200, "received")
  end

  forward "/api", to: ElixirBandit.ApiRouter

  match _ do
    send_resp(conn, 404, "")
  end
end
