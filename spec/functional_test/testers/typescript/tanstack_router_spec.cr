require "../../func_spec.cr"

expected_endpoints = [
  # Index route
  Endpoint.new("/", "GET", [] of Param),
  # Posts route with search params
  Endpoint.new("/posts", "GET", [
    Param.new("page", "", "query"),
    Param.new("filter", "", "query"),
  ]),
  # Post detail route with path param
  Endpoint.new("/posts/:postId", "GET", [
    Param.new("postId", "", "path"),
  ]),
  # User profile route with path param
  Endpoint.new("/users/:userId/profile", "GET", [
    Param.new("userId", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/typescript/tanstack_router/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
