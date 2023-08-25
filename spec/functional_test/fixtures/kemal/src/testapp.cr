require "kemal"

get "/" do
  "Hello World!"
end

ws "/socket" do |socket|
  socket.send "Hello from Kemal!"
end

Kemal.run