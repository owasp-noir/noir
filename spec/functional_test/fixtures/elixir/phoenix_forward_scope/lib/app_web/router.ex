defmodule AppWeb.Router do
  use AppWeb, :router

  scope "/api/v1/sites", AppWeb do
    pipe_through :api

    get "/", SiteController, :index
    post "/", SiteController, :create
    get "/:id", SiteController, :show
  end

  forward "/sent-emails", Bamboo.SentEmailViewerPlug
end
