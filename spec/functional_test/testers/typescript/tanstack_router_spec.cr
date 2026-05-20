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
  # Code-based route trees should compose child paths with their
  # getParentRoute() chain instead of emitting detached fragments.
  Endpoint.new("/shop", "GET", [
    Param.new("sort", "", "query"),
  ]),
  Endpoint.new("/shop/:productId", "GET", [
    Param.new("productId", "", "path"),
  ]),
  Endpoint.new("/shop/:productId/reviews", "GET", [
    Param.new("productId", "", "path"),
  ]),
  # Pathless layout routes (leading underscore) should not add a URL segment.
  Endpoint.new("/login", "GET", [] of Param),
  # Root-route files with a path should still be scanned even when
  # they do not contain createRoute() code-route assignments.
  Endpoint.new("/docs", "GET", [] of Param),
]

FunctionalTester.new("fixtures/typescript/tanstack_router/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
