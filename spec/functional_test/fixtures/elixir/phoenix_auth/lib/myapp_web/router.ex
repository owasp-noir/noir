defmodule MyappWeb.Router do
  use MyappWeb, :router

  scope "/", MyappWeb do
    get "/posts", PostController, :index
    get "/posts/:id", PostController, :show
    get "/public", PublicController, :index
  end
end
