require "../../func_spec.cr"

expected_endpoints = [
  # No white_list: the whole listen path is proxied.
  Endpoint.new("/users-api/", "ANY"),
  Endpoint.new("/users-api/admin", "DELETE"),
  Endpoint.new("/users-api/health", "GET"),
  Endpoint.new("/users-api/v1/profile", "PUT"),
  # `cache` lists bare path strings.
  Endpoint.new("/users-api/v1/catalog", "ANY"),
  # Tyk Operator `ApiDefinition`; the white_list hides the bare listen path.
  Endpoint.new("/orders/{id}", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/specification/tyk/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
