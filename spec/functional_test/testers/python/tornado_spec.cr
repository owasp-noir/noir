require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET", [Param.new("name", "", "query")]),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [Param.new("username", "", "form"), Param.new("email", "", "form")]),
  Endpoint.new("/auth", "POST", [Param.new("X-API-Key", "", "header"), Param.new("auth_token", "", "cookie")]),
  Endpoint.new("/ws/([^/]+)", "GET", [Param.new("room_id", "", "path"), Param.new("token", "", "query")]),
  Endpoint.new("/products/([0-9]+)", "GET", [Param.new("product_id", "", "path"), Param.new("expand", "", "query")]),
  Endpoint.new("/named/{item_id}", "GET", [Param.new("item_id", "", "path"), Param.new("X-Trace-ID", "", "header")]),
  Endpoint.new("/api", "GET", [Param.new("X-API-Key", "", "header")]),
  Endpoint.new("/api", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/search", "GET", [Param.new("tags", "", "query"), Param.new("q", "", "query")]),
  Endpoint.new("/items(?:/(\\d+))?", "GET", [Param.new("tags", "", "query"), Param.new("q", "", "query")]),
  Endpoint.new("/admin", "GET", [Param.new("admin_token", "", "cookie")]),
  Endpoint.new("/admin", "DELETE"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/health", "POST"),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/ping", "GET"),
  Endpoint.new("/ping", "POST"),
  Endpoint.new("/api/v2", "GET", [Param.new("X-API-Key", "", "header")]),
  Endpoint.new("/api/v2", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/triple-bracket", "GET"),
  Endpoint.new("/triple-bracket", "POST"),
  Endpoint.new("/search/v2", "GET", [Param.new("tags", "", "query"), Param.new("q", "", "query")]),
  Endpoint.new("/nested-def", "POST", [Param.new("username", "", "form")]),
  Endpoint.new("/inner-class", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/inner-class", "DELETE"),
  Endpoint.new("/multiline-tuple", "GET"),
  Endpoint.new("/multiline-tuple", "POST"),
  Endpoint.new("/multiline-triple", "GET"),
  Endpoint.new("/multiline-triple", "POST"),
  Endpoint.new("/deep", "GET", [Param.new("token", "", "query")]),
  Endpoint.new("/metrics", "GET"),
  Endpoint.new("/metrics", "POST"),
  Endpoint.new("/version", "GET"),
  Endpoint.new("/named-url", "GET"),
  Endpoint.new("/spec-url", "GET"),
  Endpoint.new("/spec-url", "POST"),
  # Module-level `default_handlers = [...]` registered from another
  # module (no local Application) — picked up by the handler-list pass.
  # The ("format %s", lowercase_arg) tuple in the same list is NOT a
  # route and must be rejected by the handler-class gate.
  Endpoint.new("/standalone", "GET"),
  Endpoint.new("/standalone", "POST"),
]

tester = FunctionalTester.new("fixtures/python/tornado/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "marks Tornado WebSocketHandler endpoints with ws protocol" do
  websocket_route = tester.app.endpoints.find { |endpoint| endpoint.url == "/ws/([^/]+)" }
  websocket_route.should_not be_nil
  websocket_route.try(&.protocol).should eq("ws")
end
