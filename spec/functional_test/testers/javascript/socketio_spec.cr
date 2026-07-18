require "../../func_spec.cr"

# Socket.IO inbound event handlers surface as realtime `ws://` endpoints:
# protocol "ws" (so the WebsocketTagger tags them), the synthetic "SEND"
# method, addressed as ws://<namespace>/<event> (default namespace →
# ws://<event>). Endpoint is a struct, so build via a Proc that mutates a
# local and returns it.
build = ->(url : String) do
  ep = Endpoint.new(url, "SEND", [] of Param)
  ep.protocol = "ws"
  ep
end

socketio_endpoints = [
  # Default-namespace connection handler events.
  build.call("ws://chat message"),
  build.call("ws://join room"),
  # A named namespace ("/admin") scopes its own event.
  build.call("ws://admin/ban user"),
]

socketio_tester = FunctionalTester.new("fixtures/javascript/socketio/", {
  :techs     => 1,
  :endpoints => socketio_endpoints.size,
}, socketio_endpoints)
socketio_tester.perform_tests

# Regression: reserved lifecycle events ("disconnect"), outbound `io.emit`
# calls, and `.on` handlers on non-socket receivers (`httpServer.on("error")`,
# `process.on("SIGTERM")`) are not inbound attack surface and must not be
# emitted.
it "excludes reserved events, outbound emits and non-socket .on handlers" do
  urls = socketio_tester.app.endpoints.map(&.url)
  urls.should_not contain("ws://disconnect")
  urls.should_not contain("ws://banned")
  urls.should_not contain("ws://error")
  urls.should_not contain("ws://SIGTERM")
end
