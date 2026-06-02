require "amber"

class ApplicationController < Amber::Controller::Base
  def index
    request.headers["x-api-key"]
    "Hello World!"
  end

  def create_user
    params.json["username"]
    params.json["email"]
    "User created"
  end

  def show_post
    params["id"]
    request.cookies["session"]
    "Post details"
  end

  def search
    params.query["q"]
    params.query["limit"]
    "Search results"
  end

  def upload
    params.body["file"]
    context.request.headers["content-type"]
    "File uploaded"
  end
end

Amber::Server.configure do
  routes :web do
    get "/", ApplicationController, :index
    post "/users", ApplicationController, :create_user
    get "/posts/:id", ApplicationController, :show_post
    get "/search", ApplicationController, :search
    post "/upload", ApplicationController, :upload

    # WebSocket route
    ws "/socket", WebSocketController, :handle
  end

  # Scoped block: every route here is prefixed with "/admin", and the
  # `resources` macro fans out to the seven RESTful routes.
  routes :web, "/admin" do
    resources "/articles", ArticleController
  end
end

Amber::Server.start
