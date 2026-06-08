defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/", MyAppWeb do
    get "/service-b/shared", PageController, :show
  end
end
