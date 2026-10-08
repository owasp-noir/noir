defmodule BlogWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api" do
    pipe_through :api

    forward "/graphiql", Absinthe.Plug.GraphiQL, schema: BlogWeb.Schema

    forward "/graphql", Absinthe.Plug, schema: BlogWeb.Schema
  end
end
