require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/v1/", "GET"),
  Endpoint.new("/api/v1/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/v1/items", "POST"),
  Endpoint.new("/api/v1/users/:user_id", "GET", [
    Param.new("user_id", "", "path"),
  ]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/chat", "GET"),
]

FunctionalTester.new("fixtures/crystal/grip/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests