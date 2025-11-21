defmodule ElixirPhoenixWeb.PostController do
  use ElixirPhoenixWeb, :controller

  def index(conn, _params) do
    # Query parameters for filtering
    category = conn.query_params["category"]
    sort_by = conn.params["sort"]
    
    render(conn, :index)
  end

  def show(conn, %{"user_id" => user_id, "id" => id}) do
    # Multiple path parameters
    post = get_post(user_id, id)
    render(conn, :show, post: post)
  end

  def create(conn, _params) do
    # Body parameters
    title = conn.body_params["title"]
    content = conn.body_params["content"]
    tags = conn.params["tags"]
    
    render(conn, :create)
  end

  def update(conn, %{"id" => id}) do
    # Mixed parameters
    title = conn.body_params["title"]
    content = conn.params["content"]
    
    render(conn, :update)
  end

  def delete(conn, %{"id" => id}) do
    send_resp(conn, 204, "")
  end

  def new(conn, _params) do
    render(conn, :new)
  end

  def edit(conn, %{"id" => id}) do
    post = get_post(id)
    render(conn, :edit, post: post)
  end

  defp get_post(id), do: %{id: id}
  defp get_post(user_id, id), do: %{user_id: user_id, id: id}
end
