defmodule MyappWeb.PostController do
  use MyappWeb, :controller

  plug :require_authenticated_user

  def index(conn, _params) do
    posts = Blog.list_posts()
    json(conn, posts)
  end

  def show(conn, %{"id" => id}) do
    post = Blog.get_post!(id)
    json(conn, post)
  end
end
