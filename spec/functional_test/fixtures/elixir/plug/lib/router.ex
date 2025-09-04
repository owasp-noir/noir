defmodule ElixirPlug.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  # Basic route definitions
  get "/hello" do
    send_resp(conn, 200, "Hello World!")
  end

  post "/users" do
    send_resp(conn, 201, "User created")
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