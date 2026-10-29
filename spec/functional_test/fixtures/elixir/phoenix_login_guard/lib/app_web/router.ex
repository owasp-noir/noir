defmodule AppWeb.Router do
  use AppWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(Guardian.Plug.VerifyHeader, realm: "Token")
    plug(Guardian.Plug.LoadResource, allow_blank: true)
  end

  pipeline :authenticated do
    plug(Guardian.Plug.EnsureAuthenticated)
  end

  scope "/api", AppWeb do
    pipe_through(:api)

    post("/users/login", SessionController, :create)
    get("/secret", SessionController, :show)
    post("/refresh", SessionController, :refresh)
  end

  scope "/api", AppWeb do
    pipe_through(:authenticated)

    get("/private", SessionController, :private)
  end
end
