defmodule AppWeb.LoadUser do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_token) do
      nil -> conn
      token -> assign(conn, :current_user, App.Accounts.get_user_by_token(token))
    end
  end
end
