require "../../func_spec.cr"

# Action Cable channel actions surface as realtime `ws://` endpoints:
# protocol "ws" (so the WebsocketTagger tags them), the synthetic "SEND"
# method, addressed as ws://<cable-mount>/<Channel>/<action>. Endpoint is a
# struct, so build via a Proc that mutates a local and returns it.
build = ->(url : String) do
  ep = Endpoint.new(url, "SEND", [] of Param)
  ep.protocol = "ws"
  ep
end

actioncable_endpoints = [
  # ChatChannel public methods become actions under the "/cable" mount;
  # subscribed/unsubscribed (lifecycle) and the private helper are excluded.
  build.call("ws://cable/ChatChannel/speak"),
  build.call("ws://cable/ChatChannel/typing"),
  # NotificationChannel has no actions, so only its connection surface is
  # emitted.
  build.call("ws://cable/NotificationChannel"),
]

actioncable_tester = FunctionalTester.new("fixtures/ruby/actioncable/", {
  :techs     => 1,
  :endpoints => actioncable_endpoints.size,
}, actioncable_endpoints)
actioncable_tester.perform_tests

# Regression: lifecycle callbacks and private helpers must not surface as
# actions.
it "excludes Action Cable lifecycle callbacks and private helpers" do
  urls = actioncable_tester.app.endpoints.map(&.url)
  urls.should_not contain("ws://cable/ChatChannel/subscribed")
  urls.should_not contain("ws://cable/ChatChannel/unsubscribed")
  urls.should_not contain("ws://cable/ChatChannel/sanitize")
end
