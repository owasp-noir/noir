require "kemal"

get "/" do |env|
  payload = HomeService.build
  env.redirect "/dashboard"
end

post "/users" do |env|
  payload = env.params.json["user"]
  UserService.create(payload)
end

get "/inline" do
  InlineService.call; "ok"
end

ws "/socket" do |socket|
  SocketTracker.connected
  socket.send "ok"
end

api = Kemal::Router.new
api.namespace "/api" do
  get "/users/:id" do |env|
    id = env.params.url["id"]
    user = UserLookup.find(id)
    UserPresenter.render(user)
  end
end
mount "/v1", api

Kemal.run
