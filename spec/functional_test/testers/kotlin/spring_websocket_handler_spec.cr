require "../../func_spec.cr"

# Plain WebSocket handlers registered with
# `WebSocketHandlerRegistry.addHandler(handler, paths...)` (#3268).
chat_endpoint = Endpoint.new("/chat", "GET")
chat_endpoint.protocol = "ws"
chat_endpoint.push_callee(Callee.new("WebSocketHandlerRegistry.addHandler", line: 16))
ticker_endpoint = Endpoint.new("/ticker", "GET")
ticker_endpoint.protocol = "ws"
ticker_legacy_endpoint = Endpoint.new("/ticker/legacy", "GET")
ticker_legacy_endpoint.protocol = "ws"

expected_endpoints = [Endpoint.new("/health", "GET"), chat_endpoint, ticker_endpoint, ticker_legacy_endpoint]

# The commented-out `addHandler(oldHandler, "/old")` is not a route.
FunctionalTester.new("fixtures/kotlin/spring_websocket_handler/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
