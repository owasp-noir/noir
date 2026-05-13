require "grip"

class IndexController
  include Grip::Controllers::HTTP

  def get(context : Context) : Context
    payload = HomeService.build
    context.json({"home" => payload}).halt
  end

  def show(context : Context) : Context
    id = context.fetch_path_params["id"]
    user = UserLookup.find(id)
    context.json({"user" => UserPresenter.render(user)}).halt
  end

  def create(context : Context) : Context
    payload = PayloadBuilder.from(context.fetch_json_params["content"])
    ItemService.create(payload)
    context.put_status(201).json({"ok" => true}).halt
  end
end

class ChatController
  include Grip::Controllers::WebSocket

  def on_message(context : Context, message : String) : Nil
    SocketTracker.connected
    context.send(message)
  end
end

module Api
  class StatusController
    include Grip::Controllers::HTTP

    def get(context : Context) : Context
      status = ApiStatus.check
      context.json({"status" => status}).halt
    end
  end
end

class Application
  include Grip::Application

  def initialize
    scope "/api" do
      get "/", IndexController
      get "/:id", IndexController, as: :show
      post "/items", IndexController, as: :create
      get "/status", Api::StatusController
    end

    get "/health", IndexController
    ws "/chat", ChatController
  end
end

app = Application.new
app.run
