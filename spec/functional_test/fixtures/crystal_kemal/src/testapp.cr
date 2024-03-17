require "kemal"

get "/" do
  env.request.headers["x-api-key"].as(String)
  "Hello World!"
end

post "/query" do
  env.request.cookies["my_auth"].as(String)
  env.params.body["query"].as(String)
end

ws "/socket" do |socket|
  socket.send "Hello from Kemal!"
end

public_folder "custom_public"

Kemal.run
