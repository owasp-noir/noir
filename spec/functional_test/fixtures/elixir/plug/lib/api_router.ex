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

  # Query parameters example
  get "/search/api" do
    query = conn.query_params["query"]
    page = conn.params["page"]
    send_resp(conn, 200, "API search results")
  end

  # Body parameters example
  post "/api/create" do
    title = conn.body_params["title"]
    description = conn.params["description"]
    send_resp(conn, 201, "API resource created")
  end

  # Header parameters example
  get "/api/secured" do
    token = get_req_header(conn, "x-api-token")
    auth = get_req_header(conn, "authorization")
    send_resp(conn, 200, "Secured API endpoint")
  end

  # Cookie parameters example
  get "/api/session" do
    token = conn.cookies["api_token"]
    user = conn.cookies["api_user"]
    send_resp(conn, 200, "API session info")
  end

  match _ do
    send_resp(conn, 404, "API endpoint not found")
  end
end