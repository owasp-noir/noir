require "../../func_spec.cr"

# A gin router builder declared as a method, called as `h.Register(v1)`.
expected_endpoints = [
  Endpoint.new("/api/users/login", "POST"),
  Endpoint.new("/api/tags", "GET"),
]

FunctionalTester.new("fixtures/go/gin_group_method_builder/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
