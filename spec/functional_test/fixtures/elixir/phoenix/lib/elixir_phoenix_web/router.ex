defmodule ElixirPhoenixWeb.Router do
  use ElixirPhoenixWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {ElixirPhoenixWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  defmacro admin_routes(options \\ []) do
    scoped = Keyword.get(options, :scope, "/macro-admin")
    controller = Keyword.get(options, :controller, AdminController)

    quote do
      scope unquote(scoped), ElixirPhoenixWeb do
        get "/dashboard", unquote(controller), :dashboard
        options "/dashboard", unquote(controller), :preflight
      end
    end
  end

  defmacro unused_routes(options \\ []) do
    scoped = Keyword.get(options, :scope, "/unused-admin")

    quote do
      scope unquote(scoped), ElixirPhoenixWeb do
        get "/ghost", AdminController, :dashboard
      end
    end
  end

  scope "/", ElixirPhoenixWeb do
    pipe_through :browser

    get "/page", PageController, :home
    post "/page", PageController, :home
    put "/page", PageController, :home
    patch "/page", PageController, :home
    delete "/page", PageController, :home
    socket "/socket", MyAppWeb.Socket, websocket: true, longpoll: false
    
    # Routes with path parameters
    get "/users/:id", UserController, :show
    put "/users/:id", UserController, :update
    delete "/users/:id", UserController, :delete
    get "/users/:user_id/posts/:id", PostController, :show
    
    # Routes with wildcard parameters
    get "/files/*path", FileController, :serve
    
    # LiveView routes
    live "/live/users", UserLive
    live "/live/users/:id", UserLive
    live "/live/users/:id/edit", UserEditLive
    
    # Resources macro
    resources "/posts", PostController
    resources "/comments", CommentController, only: [:index, :show]
  end

  scope "/api", ElixirPhoenixWeb do
    pipe_through :api

    get "/accounts/:id", Api.UserController, :show
    post("/page", PageController, :home)

    # Plug-style routes: the 2nd arg is a Plug module and the 3rd is plug
    # opts (`[]` / keyword list), NOT an `:action` atom. Common for API
    # docs, dashboards and SPA catch-alls; must still be detected. # spellchecker:disable-line
    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
    get "/swaggerui", OpenApiSpex.Plug.SwaggerUI, config: %{path: "/api/openapi"}

    match :post, "/hooks", PageController, :home
    match :put, "/hooks", PageController, :home
  end

  # Nested resources: the child collection mounts under the parent's
  # `/:singular_id` member segment, and `only:` placed behind `as:`
  # must still constrain the generated actions.
  scope "/admin", ElixirPhoenixWeb do
    resources "/podcasts", PodcastController, only: [:index, :show] do
      resources "/episodes", EpisodeController, as: :episode, only: [:index]
    end
  end

  # Parenthesised `resources(...)` call form, plus a `singleton: true`
  # resource whose member routes carry no `/:id` segment.
  scope "/account", ElixirPhoenixWeb do
    resources("/session", SessionController, singleton: true, only: [:create, :delete])
    resources "/keys", KeyController, param: "key_id", only: [:show, :delete]
  end

  admin_routes(scope: "/macro-admin-v2")

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:elixir_phoenix, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ElixirPhoenixWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
