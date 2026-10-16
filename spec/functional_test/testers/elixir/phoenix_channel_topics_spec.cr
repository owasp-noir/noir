require "../../func_spec.cr"

# Phoenix Channel topic attribution. Socket declarations in `mix format`'s
# paren form still map a channel to its topic; modules that share a short
# name (`Client.Channel` / `Gateway.Channel`) each keep their own topic; a
# declaration through a partial alias resolves; helper modules no socket maps
# (`Client.Channel.Shared`) and the stub channel under `test/support` emit
# nothing, instead of a topic invented from the module name.
build = ->(url : String) do
  ep = Endpoint.new(url, "SEND", [] of Param)
  ep.protocol = "ws"
  ep
end

expected_endpoints = [
  build.call("ws://conversation:*/ping"),
  build.call("ws://client/create_flow"),
  build.call("ws://gateway/flow_authorized"),
  build.call("ws://alias:*/hello"),
]

tester = FunctionalTester.new("fixtures/elixir/phoenix_channel_topics/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

it "never invents a topic from a channel module's name", tags: "functional" do
  tester.endpoints.map(&.url).select { |url| url.includes?("Channel") || url.includes?("Shared") || url.includes?("stub") }.should be_empty
end
