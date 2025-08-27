require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users/<int:id>", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/auth/login", "GET"),
  Endpoint.new("/products", "GET"),
  Endpoint.new("/products/<slug:slug>", "GET", [
    Param.new("slug", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/crystal/marten/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
