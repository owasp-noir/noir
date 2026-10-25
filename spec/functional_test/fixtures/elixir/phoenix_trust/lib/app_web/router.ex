defmodule AppWeb.Router do
  use AppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug AppWeb.LoadUser
  end

  pipeline :auth do
    plug :fetch_session
    plug AppWeb.LoadUser
  end

  pipeline :account do
    plug AppWeb.RequireAccount
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AppWeb do
    pipe_through [:browser, :auth]

    get "/", PageController, :home
    post "/share/:slug/authenticate", PageController, :authenticate
    get "/edit", PageController, :edit
    get "/me", PageController, :me
    get "/guest", PageController, :guest
  end

  scope "/settings", AppWeb do
    pipe_through [:browser, :account]

    delete "/keys/:id", PageController, :delete_key
  end

  scope "/api/v1", AppWeb.Api do
    pipe_through [:api, AppWeb.ApiAuth]

    get "/items", Items, :index
    patch "/items/:id", Items, :update
  end
end
