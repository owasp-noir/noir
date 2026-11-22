require "../../func_spec.cr"

# Go 1.22 patterns whose method is a stdlib constant (`http.MethodGet+" /users"`).
expected_endpoints = [
  Endpoint.new("/ctl", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/items/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/orders", "GET"),
]

FunctionalTester.new("fixtures/go/http_method_const/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
