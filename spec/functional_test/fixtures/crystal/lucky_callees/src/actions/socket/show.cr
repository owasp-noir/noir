class Socket::Show < Lucky::Action
  ws "/lucky/socket" do |socket|
    SocketTracker.connected
    socket.send "ok"
  end
end
