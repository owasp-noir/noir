require "../../func_spec.cr"

# A socket's `channel(...)` declaration that `mix format` spreads over several
# lines (past 98 columns) still maps its channel to the topic. Modules no
# socket maps, and the test/support stub socket, emit nothing.
build = ->(url : String) do
  ep = Endpoint.new(url, "SEND", [] of Param)
  ep.protocol = "ws"
  ep
end

expected_endpoints = [
  build.call("ws://organization_notifications:*/update_preferences"),
  build.call("ws://ping:*/ping"),
]

tester = FunctionalTester.new("fixtures/elixir/phoenix_channel_multiline/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

it "emits nothing for unmapped channels or the test/support stub", tags: "functional" do
  tester.endpoints.map(&.url).select { |url| url.includes?("orphan") || url.includes?("Orphan") || url.includes?("stub") }.should be_empty
end
