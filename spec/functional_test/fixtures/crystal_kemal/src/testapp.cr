require "kemal"

get "/" do
  env.request.headers["x-api-key"].as(String)
  "Hello World!"
end

post "/query" do
  env.request.cookies["my_auth"].as(String)
  env.params.body["query"].as(String)
end

post "/token" do
  env.params.body["client_id"].as(String)
  env.params.body["redirect_url"].as(String)
  env.params.body["grant_type"].as(String)
end

ws "/socket" do |socket|
  socket.send "Hello from Kemal!"
end

public_folder "custom_public"

Kemal.run
