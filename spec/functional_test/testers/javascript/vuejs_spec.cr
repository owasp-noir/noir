require "../../func_spec.cr"

expected_endpoints = [
  # Basic routes
  Endpoint.new("/", "GET", [] of Param),
  Endpoint.new("/users", "GET", [] of Param),
  # Route with path parameter
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/posts/:postId", "GET", [
    Param.new("postId", "", "path"),
  ]),
  # Route with query parameters
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("filter", "", "query"),
  ]),
  # Route with multiple path parameters
  Endpoint.new("/products/:category/:id", "GET", [
    Param.new("category", "", "path"),
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/vuejs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
