require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/users", "GET"),
  Endpoint.new("/v1/users", "POST", [
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/admin/dashboard", "GET"),
  Endpoint.new("/v1/nested/item", "DELETE"),
]

FunctionalTester.new("fixtures/go/gin_crossfile/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
