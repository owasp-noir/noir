defmodule MyApp.AdminRouter do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get("/users") do
    send_resp(conn, 200, "ok")
  end
end
