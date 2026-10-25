defmodule AppWeb.PageController do
  use AppWeb, :controller

  @owner_actions [:edit]

  plug AppWeb.RequireGuest when action in [:guest]

  plug(
    AppWeb.RequireAccount
    when action in @owner_actions
  )

  def home(conn, _params) do
    render(conn, "home.html", user: conn.assigns.current_user)
  end

  def authenticate(conn, %{"slug" => slug, "password" => password}) do
    if App.Links.valid?(slug, password) do
      redirect(conn, to: return_path(conn))
    else
      render(conn, "password.html")
    end
  end

  def edit(conn, _params) do
    render(conn, "edit.html")
  end

  def me(conn, _params) do
    with %{} = user <- conn.assigns[:current_user] do
      json(conn, user)
    else
      _ -> conn |> put_status(:unauthorized) |> json(%{error: "log in first"})
    end
  end

  def guest(conn, _params) do
    render(conn, "guest.html")
  end

  def delete_key(conn, %{"id" => id}) do
    App.Keys.delete(conn.assigns.current_user, id)
    redirect(conn, to: "/settings")
  end

  defp return_path(conn) do
    conn.query_params["return_to"] || "/"
  end
end
