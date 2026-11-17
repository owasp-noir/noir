require "../../func_spec.cr"

# Spring routes `@MessageMapping` only on `@Controller` beans: directly, or
# through a project stereotype meta-annotated with it (two levels here), or up
# the type hierarchy. A `@Component` with a stray `@MessageMapping` is no
# destination.
expected_endpoints = [
  Endpoint.new("/ws", "GET").tap(&.protocol=("ws")),
  Endpoint.new("/app/chat", "SEND").tap(&.protocol=("ws")),
  Endpoint.new("/app/lobby", "SEND").tap(&.protocol=("ws")),
  Endpoint.new("/app/score", "SEND").tap(&.protocol=("ws")),
  Endpoint.new("/app/presence", "SUBSCRIBE").tap(&.protocol=("ws")),
]

tester = FunctionalTester.new("fixtures/java/spring_message_mapping_stereotype/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Spring @MessageMapping outside a controller", tags: "functional" do
  it "is not a destination" do
    tester.endpoints.map(&.url).should_not contain("/app/relay")
  end
end
