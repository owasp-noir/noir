defmodule ElixirPhoenixCalleesWeb.PostController do
  use ElixirPhoenixCalleesWeb, :controller

  def index(conn, _params) do
    category = conn.query_params["category"]
    posts = PostQuery.list(category)
    render(conn, :index, posts: PostPresenter.render(posts))
  end

  def show(conn, %{"id" => id}) do
    post = PostQuery.find(id)
    AuditLog.read_post(id)
    render(conn, :show, post: PostPresenter.render(post))
  end
end
