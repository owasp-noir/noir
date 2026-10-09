defmodule InlineScopeWeb.Router do
  use InlineScopeWeb, :router

  defmacro ops_routes(options \\ []) do
    scoped = Keyword.get(options, :scope, "/ops")

    quote do
      scope unquote(scoped), InlineScopeWeb, do: get("/health", OpsController, :health)
      get "/macro-after", OpsController, :after
    end
  end

  # The one-line `do:` form has no `end`; its scope covers this line only.
  scope "/admin", InlineScopeWeb, do: get("/inline", AdminController, :index)

  scope "/api", InlineScopeWeb do
    get "/users", UserController, :index
  end

  get "/after", PageController, :index

  ops_routes()
end
