require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/greet", "GET", [
    Param.new("lang", "", "query"),
  ]),
  Endpoint.new("/greet/{name}", "GET", [
    Param.new("X-Trace-Id", "", "header"),
    Param.new("name", "", "path"),
  ]),
  Endpoint.new("/greet/greeting", "PUT", [
    Param.new("message", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/java/helidon_mp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
