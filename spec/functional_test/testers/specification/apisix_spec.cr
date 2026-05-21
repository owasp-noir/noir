require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/users", "GET"),
  Endpoint.new("/v1/users", "POST"),
  Endpoint.new("/admin", "GET", [Param.new("Host", "admin.example.com", "header")]),
  Endpoint.new("/admin/*", "GET", [Param.new("Host", "admin.example.com", "header")]),
  Endpoint.new("/api/*", "ANY"),
  Endpoint.new("/internal", "DELETE", [
    Param.new("Host", "api.example.com", "header"),
    Param.new("Host", "internal.example.com", "header"),
  ]),
  Endpoint.new("/json/users", "GET"),
  Endpoint.new("/json/admin", "ANY"),
  Endpoint.new("/json/admin/*", "ANY"),
]

FunctionalTester.new("fixtures/specification/apisix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
