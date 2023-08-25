require "kemal"

get "/" do
  "Hello World!"
end

post "/query" do
   env.params.body["query"].as(String)
end

ws "/socket" do |socket|
  socket.send "Hello from Kemal!"
end

Kemal.run