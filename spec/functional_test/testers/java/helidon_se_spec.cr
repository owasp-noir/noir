require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/ping", "ANY"),
  Endpoint.new("/greet/", "GET", [
    Param.new("lang", "", "query"),
  ]),
  Endpoint.new("/greet/{name}", "GET", [
    Param.new("X-Trace-Id", "", "header"),
    Param.new("name", "", "path"),
  ]),
  Endpoint.new("/greet/greeting", "PUT", [
    Param.new("session", "", "cookie"),
    Param.new("body", "GreetingUpdate", "json"),
  ]),
  Endpoint.new("/greet/admin/status", "GET"),
  Endpoint.new("/greet/admin/cache/{cacheId}", "DELETE", [
    Param.new("cacheId", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/java/helidon_se/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
