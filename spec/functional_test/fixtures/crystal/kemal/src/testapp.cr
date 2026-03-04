require "kemal"

get "/" do
  env.request.headers["x-api-key"].as(String)
  "Hello World!"
end

post "/query" do
  env.request.cookies["my_auth"].as(String)
  env.params.body["query"].as(String)
end

get "/token" do
  env.params.body["client_id"].as(String)
  env.params.body["redirect_url"].as(String)
  env.params.body["grant_type"].as(String)
end

ws "/socket" do |socket|
  socket.send "Hello from Kemal!"
end

api = Kemal::Router.new
api.namespace "/users" do
  get "/" do |env|
    env.params.query["page"]
    "user list"
  end
  get "/:id" do |_|
    "user detail"
  end
end
mount "/api/v1", api

public_folder "custom_public"

Kemal.run
