require "../../func_spec.cr"

# Spring routes `@MessageMapping` only on `@Controller` beans: directly, or
# through a project stereotype meta-annotated with it, or up the type
# hierarchy. A `@Component` with a stray `@MessageMapping` is no destination;
# one whose annotation is declared outside the scan (`@StompController`) may
# be a controller and stays. A mapping an interface declares is read too.
expected_endpoints = [
  Endpoint.new("/ws", "GET").tap(&.protocol=("ws")),
  Endpoint.new("/app/chat", "SEND", [Param.new("text", "", "json")]).tap(&.protocol=("ws")),
  Endpoint.new("/app/external", "SEND", [Param.new("text", "", "json")]).tap(&.protocol=("ws")),
  Endpoint.new("/app/lobby", "SEND", [Param.new("text", "", "json")]).tap(&.protocol=("ws")),
  Endpoint.new("/app/ping", "SEND", [Param.new("text", "", "json")]).tap(&.protocol=("ws")),
  Endpoint.new("/app/score", "SEND", [Param.new("text", "", "json")]).tap(&.protocol=("ws")),
]

tester = FunctionalTester.new("fixtures/kotlin/spring_message_mapping_stereotype/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Kotlin Spring @MessageMapping outside a controller", tags: "functional" do
  it "is not a destination" do
    tester.endpoints.map(&.url).should_not contain("/app/relay")
  end
end
