require "../../func_spec.cr"

# goctl wraps a `middleware:` group's routes in `rest.WithMiddlewares(...)`.
expected_endpoints = [
  Endpoint.new("/api/v1/users/:id", "GET"),
  Endpoint.new("/api/v1/users/:id", "PUT"),
]

FunctionalTester.new("fixtures/go/gozero_with_middlewares/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
