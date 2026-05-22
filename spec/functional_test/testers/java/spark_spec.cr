require "../../func_spec.cr"

ws_endpoint = Endpoint.new("/api/events/:roomId", "GET", [
  Param.new("roomId", "", "path"),
])
ws_endpoint.protocol = "ws"

expected_endpoints = [
  Endpoint.new("/**", "GET"),
  Endpoint.new("/hello", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/v1/health", "GET"),
  Endpoint.new("/api/v1/submit", "POST", [
    Param.new("body", "", "json"),
    Param.new("X-Token", "", "header"),
  ]),
  Endpoint.new("/api/v1/items/:itemId", "GET", [
    Param.new("itemId", "", "path"),
    Param.new("category", "", "query"),
  ]),
  Endpoint.new("/sessions/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/profile", "PUT", [
    Param.new("body", "", "json"),
    Param.new("X-Trace", "", "header"),
  ]),
  Endpoint.new("/legacy-home", "GET"),
  Endpoint.new("/legacy-submit", "POST"),
  Endpoint.new("/legacy-any", "ANY"),
  Endpoint.new("/api/reports/:reportId", "GET", [
    Param.new("reportId", "", "path"),
    Param.new("X-Report-Trace", "", "header"),
  ]),
  ws_endpoint,
]

FunctionalTester.new("fixtures/java/spark/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
