require "../../func_spec.cr"

# A connection callback that hands its socket to a handler function
# (`chatHandler(socket)`, defined in another module) registers that
# function's events too. The connection module imports nothing from
# `socket.io` (its `io` comes from ./app). A `ws` server that hands its
# socket to the same function adds nothing.
build = ->(url : String) do
  ep = Endpoint.new(url, "SEND", [] of Param)
  ep.protocol = "ws"
  ep
end

delegated_endpoints = [
  build.call("ws://ping me"),
  build.call("ws://send"),
  build.call("ws://chat_join"),
  build.call("ws://history"),
  build.call("ws://kick"),
  build.call("ws://open"),
]

delegated_tester = FunctionalTester.new("fixtures/javascript/socketio_delegated/", {
  :techs     => 1,
  :endpoints => delegated_endpoints.size,
}, delegated_endpoints)
delegated_tester.perform_tests

it "skips an unresolved event-name prefix and the ws server's events", tags: "functional" do
  urls = delegated_tester.app.endpoints.map(&.url)
  urls.should_not contain("ws://raw message")
  urls.any?(&.ends_with?("leave")).should be_false
end

it "reports a delegated event at its own line", tags: "functional" do
  send = delegated_tester.app.endpoints.find! { |ep| ep.url == "ws://send" }
  send.details.code_paths.first.path.should end_with("handlers/chat.js")
  send.details.code_paths.first.line.should eq(9)
end
