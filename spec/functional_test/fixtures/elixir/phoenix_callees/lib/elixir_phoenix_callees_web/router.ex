defmodule ElixirPhoenixCalleesWeb.Router do
  use ElixirPhoenixCalleesWeb, :router

  scope "/", ElixirPhoenixCalleesWeb do
    get "/users", UserController, :index
    post "/users", UserController, :create
    resources "/posts", PostController, only: [:index, :show]
  end
end
