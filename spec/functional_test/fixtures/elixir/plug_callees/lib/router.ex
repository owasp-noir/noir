defmodule ElixirPlugCallees.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/users" do
    page = conn.query_params["page"]
    users = UserService.list(page)
    AuditLog.write("users")
    send_resp(conn, 200, JsonPresenter.render(users))
  end

  post "/users" do
    payload = UserPayload.from_conn(conn)
    created = payload |> UserService.create()
    send_resp conn, 201, render_user(created)
  end

  get "/health" do
    if Health.ready?() do
      send_resp(conn, 200, "ok")
    else
      send_resp(conn, 503, "down")
    end
  end

  match "/webhook", via: [:post, :put] do
    WebhookHandler.dispatch(conn)
    send_resp(conn, 200, "ok")
  end
end
