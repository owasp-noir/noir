defmodule ElixirPhoenixWeb.UserController do
  use ElixirPhoenixWeb, :controller

  def show(conn, %{"id" => id}) do
    # Path parameter 'id' is automatically extracted
    user = get_user(id)
    
    # Headers
    auth_token = get_req_header(conn, "authorization")
    api_key = get_req_header(conn, "x-api-key")
    
    render(conn, :show, user: user)
  end

  def update(conn, %{"id" => id}) do
    # Body/form parameters
    name = conn.body_params["name"]
    email = conn.params["email"]
    age = conn.params["age"]
    
    # Cookies
    session_id = conn.cookies["session_id"]
    user_pref = conn.cookies["user_preference"]
    
    render(conn, :update)
  end

  def delete(conn, %{"id" => id}) do
    # Just path parameter
    delete_user(id)
    send_resp(conn, 204, "")
  end

  defp get_user(id), do: %{id: id}
  defp delete_user(id), do: :ok
end
