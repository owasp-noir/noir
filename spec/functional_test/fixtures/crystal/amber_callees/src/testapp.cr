require "amber"

class ApplicationController < Amber::Controller::Base
  def index
    payload = HomeService.build; json payload
  end

  def create_user
    username = params.json["username"]
    user = UserService.create(username)
    AuditTrail.record(user)
  end

  def show_post
    id = params["id"]
    post = PostLookup.find(id)
    render_post(post)
  end

  def upload
    file = params.body["file"]
    UploadService.store(file)
    context.request.headers["content-type"]
  end
end

class WebSocketController < Amber::Controller::Base
  def handle
    SocketTracker.connected
    socket.send "ok"
  end
end

Amber::Server.configure do
  routes :web do
    get "/", ApplicationController, :index
    post "/users", ApplicationController, :create_user
    get "/posts/:id", ApplicationController, :show_post
    post "/upload", ApplicationController, :upload
    ws "/socket", WebSocketController, :handle
    get "/health"
  end
end

Amber::Server.start
