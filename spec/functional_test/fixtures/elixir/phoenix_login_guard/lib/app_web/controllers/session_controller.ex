defmodule AppWeb.SessionController do
  def create(conn, params) do
    case Auth.find_user_and_check_password(params) do
      {:ok, user} ->
        {:ok, jwt, _claims} = AppWeb.Guardian.encode_and_sign(user, %{}, token_type: :token)
        conn |> put_status(:created) |> json(%{token: jwt})

      {:error, message} ->
        conn |> put_status(401) |> json(%{error: message})
    end
  end

  def show(conn, _params) do
    case conn.assigns[:current_user] do
      nil -> conn |> put_status(401) |> json(%{error: "unauthorized"})
      user -> json(conn, %{id: user.id})
    end
  end

  def refresh(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn |> put_status(401) |> json(%{error: "unauthorized"})

      user ->
        {:ok, jwt, _claims} = AppWeb.Guardian.encode_and_sign(user, %{}, token_type: :token)
        json(conn, %{token: jwt})
    end
  end

  def private(conn, _params) do
    json(conn, %{ok: true})
  end
end
