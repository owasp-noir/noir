defmodule ElixirPlug.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  # Basic route definitions
  get "/hello" do
    send_resp(conn, 200, "Hello World!")
  end

  # Route with query parameters
  get "/search" do
    query = conn.query_params["q"]
    limit = conn.params["limit"]
    send_resp(conn, 200, "Search results for: #{query}")
  end

  post "/users" do
    send_resp(conn, 201, "User created")
  end

  # Route with body parameters
  post "/login" do
    username = conn.body_params["username"]
    password = conn.params["password"]
    send_resp(conn, 200, "Login attempt for: #{username}")
  end

  # Route with headers
  get "/protected" do
    auth = get_req_header(conn, "authorization")
    api_key = get_req_header(conn, "x-api-key")
    send_resp(conn, 200, "Protected resource")
  end

  # Route with cookies
  get "/profile" do
    session_id = conn.cookies["session_id"]
    conn = fetch_cookies(conn)
    user_pref = conn.cookies["user_preference"]
    send_resp(conn, 200, "User profile")
  end

  put "/users/:id" do
    id = conn.path_params["id"]
    send_resp(conn, 200, "User #{id} updated")
  end

  patch "/users/:id/profile" do
    send_resp(conn, 200, "Profile updated")
  end

  delete "/users/:id" do
    send_resp(conn, 204, "")
  end

  head "/health" do
    send_resp(conn, 200, "")
  end

  options "/api/*path" do
    send_resp(conn, 200, "")
  end

  # Forward to another router
  forward "/api", to: ElixirPlug.ApiRouter

  # Match with via option
  match "/webhook", via: [:post, :put] do
    send_resp(conn, 200, "Webhook received")
  end

  # Simple match (defaults to GET)
  match "/simple" do
    send_resp(conn, 200, "Simple match")
  end

  # Catch-all route
  match _ do
    send_resp(conn, 404, "Not found")
  end
end