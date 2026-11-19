defmodule MyApp.Router do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/plain" do
    send_resp(conn, 200, "ok")
  end

  get("/health") do
    send_resp(conn, 200, "ok")
  end

  post("/items") do
    send_resp(conn, 201, conn.body_params["name"])
  end

  get("/ping", do: send_resp(conn, 200, "pong"))

  delete("/items/:id", do: send_resp(conn, 204, ""))

  match("/hook", via: [:post, :put]) do
    send_resp(conn, 200, "ok")
  end

  forward("/admin", to: MyApp.AdminRouter)
end
