require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/bracket-literal", "GET", [
    Param.new("mode", "", "query"),
    Param.new("X-Request-Id", "", "header"),
  ]),
  Endpoint.new("/public-api/status", "GET", [
    Param.new("traceId", "", "cookie"),
  ]),
  Endpoint.new("/api/v1/things/:thingId", "POST", [
    Param.new("thingId", "", "path"),
    Param.new("display_name", "", "json"),
    Param.new("enabled", "", "json"),
  ]),
  Endpoint.new("/admin-api/things/:thingId", "POST", [
    Param.new("thingId", "", "path"),
    Param.new("display_name", "", "json"),
    Param.new("enabled", "", "json"),
  ]),
  Endpoint.new("/public-api/imported", "GET", [
    Param.new("source", "", "query"),
  ]),
  Endpoint.new("/api/v1/imported", "GET", [
    Param.new("source", "", "query"),
  ]),
  Endpoint.new("/admin-api/imported", "GET", [
    Param.new("source", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/javascript/express_mount_edge_patterns/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
