defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/", MyAppWeb do
    get "/service-a/shared", PageController, :show
  end
end
