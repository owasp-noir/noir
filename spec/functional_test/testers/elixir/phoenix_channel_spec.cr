require "../../func_spec.cr"

# Phoenix Channel handle_in events surface as realtime `ws://` endpoints:
# protocol "ws" (so the WebsocketTagger tags them), the synthetic "SEND"
# method, addressed as ws://<topic>/<event>. Endpoint is a struct, so build
# via a Proc that mutates a local and returns it.
build = ->(url : String) do
  ep = Endpoint.new(url, "SEND", [] of Param)
  ep.protocol = "ws"
  ep
end

phoenix_channel_endpoints = [
  # RoomChannel is mapped to topic "room:*" in UserSocket; its handle_in
  # clauses become events. The catch-all handle_in(_event, ...) has no
  # literal name and is not emitted.
  build.call("ws://room:*/new_msg"),
  build.call("ws://room:*/typing"),
  # NoticeChannel (mapped to "notice:lobby", declared via `use MyAppWeb,
  # :channel`) has no handle_in clauses, so only its connection surface is
  # emitted.
  build.call("ws://notice:lobby"),
]

phoenix_channel_tester = FunctionalTester.new("fixtures/elixir/phoenix_channel/", {
  :techs     => 1,
  :endpoints => phoenix_channel_endpoints.size,
}, phoenix_channel_endpoints)
phoenix_channel_tester.perform_tests

# Regression: the catch-all handle_in clause carries no literal event name
# and must not surface as an endpoint.
it "does not emit an endpoint for a catch-all handle_in clause" do
  urls = phoenix_channel_tester.app.endpoints.map(&.url)
  urls.count(&.starts_with?("ws://room:*/")).should eq 2
end
