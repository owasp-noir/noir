defmodule AppWeb.RequireAccount do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> Phoenix.Controller.redirect(to: login_path(conn))
      |> halt()
    end
  end

  defp login_path(_conn), do: "/login"
end
