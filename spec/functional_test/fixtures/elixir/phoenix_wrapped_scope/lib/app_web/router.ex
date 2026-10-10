defmodule AppWeb.Router do
  use AppWeb, :router

  scope "/api", # v1 api
    AppWeb.Api do
    get "/users", UserController, :index
  end

  scope "/admin",
        AppWeb.Admin,
        as: :admin do
    get "/users", UserController, :index
  end

  scope "/", AppWeb do
    get "/users", UserController, :index
  end
end
