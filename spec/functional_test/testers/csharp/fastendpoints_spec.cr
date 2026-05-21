require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users/{Id}", "GET", [
    Param.new("Id", "", "path"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("Name", "", "json"),
    Param.new("Email", "", "json"),
  ]),
  Endpoint.new("/search", "GET", [
    Param.new("Keyword", "", "query"),
    Param.new("Page", "", "query"),
    Param.new("TraceId", "", "header"),
  ]),
  Endpoint.new("/ping", "GET"),
  Endpoint.new("/legacy/status", "GET"),
  Endpoint.new("/legacy/status", "HEAD"),
  Endpoint.new("/v2/status", "GET"),
  Endpoint.new("/v2/status", "HEAD"),
  Endpoint.new("/users/{Id}", "DELETE", [
    Param.new("Id", "", "path"),
    Param.new("Soft", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/csharp/fastendpoints/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests
