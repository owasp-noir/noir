require "webrick"

server = WEBrick::HTTPServer.new

server.mount_proc "/spec-helper" do |_req, res|
  res.body = "not production"
end
