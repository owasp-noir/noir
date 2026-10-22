defmodule ElixirPlug.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/secured" do
    token =
      get_req_header(
        conn,
        "x-api-token"
      )

    q = conn.query_params[
      "q"
    ]

    # get_req_header(
    #   conn,
    #   "x-ghost"
    # )
    send_resp(conn, 200, "ok")
  end
end
