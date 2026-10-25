defmodule AppWeb.ApiAuth do
  import Plug.Conn

  alias AppWeb.Api.Helpers, as: H

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, key} <- App.Keys.find(token) do
      assign(conn, :api_key, key)
    else
      _ -> H.unauthorized(conn, "Missing API key")
    end
  end
end
