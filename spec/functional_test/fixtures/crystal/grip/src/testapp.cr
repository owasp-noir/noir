require "grip"

class IndexController
  include Grip::Controllers::HTTP

  def get(context : Context) : Context
    context
      .put_status(200)
      .json({"id" => 1})
      .halt
  end

  def index(context : Context) : Context
    id = context.fetch_path_params["id"]
    name = context.fetch_query_params["name"]
    auth_header = context.fetch_headers["Authorization"]
    session_cookie = context.fetch_cookies["session_id"]

    context
      .json(content: {"id" => id, "name" => name, "authorization" => auth_header, "session_id" => session_cookie}, content_type: "application/json")
      .halt
  end

  def create(context : Context) : Context
    title = context.fetch_form_params["title"]
    body = context.fetch_json_params["content"]

    context
      .put_status(201)
      .json({"message" => "Created", "title" => title, "content" => body})
      .halt
  end
end

class UserController
  include Grip::Controllers::HTTP

  def show(context : Context) : Context
    user_id = context.fetch_path_params["user_id"]
    context.json({"user_id" => user_id}).halt
  end
end

class ChatController
  include Grip::Controllers::WebSocket

  def on_message(context : Context, message : String) : Nil
    context.send(message)
  end
end

class Application
  include Grip::Application

  def initialize
    property handlers : Array(HTTP::Handler) = [
      Grip::Handlers::Log.new,
      Grip::Handlers::HTTP.new,
      Grip::Handlers::WebSocket.new,
    ] of HTTP::Handler

    property environment : String = ENV["ENVIRONMENT"]? || "PRODUCTION"

    scope "/api" do
      scope "/v1" do
        get "/", IndexController
        get "/:id", IndexController, as: :index
        post "/items", IndexController, as: :create

        scope "/users" do
          get "/:user_id", UserController, as: :show
        end
      end
    end

    get "/health", IndexController
    ws "/chat", ChatController
  end
end

app = Application.new
app.run
