require "../../func_spec.cr"

# SignalR hub methods surface as realtime `ws://` endpoints: protocol "ws"
# (so the WebsocketTagger tags them), the synthetic "SEND" method, and
# message params (param_type "json"). Endpoint is a struct, so build via a
# Proc that mutates a local and returns it.
build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "SEND", params)
  ep.protocol = "ws"
  ep
end

signalr_endpoints = [
  # ChatHub mounted at "/chat": each public method is one event; the
  # constructor and the OnConnectedAsync override are excluded, and the
  # trailing CancellationToken is dropped as a framework/DI type.
  build.call("ws://chat/SendMessage", [
    Param.new("user", "", "json"),
    Param.new("message", "", "json"),
  ]),
  build.call("ws://chat/JoinRoom", [
    Param.new("roomName", "", "json"),
  ]),
  build.call("ws://chat/StreamData", [
    Param.new("count", "", "json"),
  ]),
  # AdminHub has a custom base (SecureHubBase) and is recognised only via
  # its MapHub<AdminHub>("/admin") mount — exercises the cross-file join.
  build.call("ws://admin/Kick", [
    Param.new("userId", "", "json"),
  ]),
  # NotificationHub has no callable methods, so only its connection
  # surface is emitted.
  build.call("ws://notify", [] of Param),
]

signalr_tester = FunctionalTester.new("fixtures/csharp/signalr/", {
  :techs     => 1,
  :endpoints => signalr_endpoints.size,
}, signalr_endpoints)
signalr_tester.perform_tests

# Regression: the trailing CancellationToken on StreamData is a framework
# type, not a client-supplied message field, so it must not surface as a
# param on the analyzed endpoint.
it "drops framework/DI params (CancellationToken) from SignalR events" do
  stream = signalr_tester.app.endpoints.find { |e| e.url == "ws://chat/StreamData" }
  stream.should_not be_nil
  if stream
    stream.params.map(&.name).should_not contain("cancellationToken")
  end
end
