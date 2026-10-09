require "../../func_spec.cr"

expected_endpoints = [
  # Resolved by name from the outer router, so both prefixes apply.
  Endpoint.new("/api/v1/posts/:postId/comments", "GET", [Param.new("postId", "", "path"), Param.new("cursor", "", "query")]),
  Endpoint.new("/api/posts/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/posts", "POST", [Param.new("title", "", "json")]),
  # Schema constant behind `.strict()`, plus a quoted header key.
  Endpoint.new("/api/posts/:id", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("title", "", "json"),
    Param.new("content", "", "json"),
    Param.new("x-api-key", "", "header"),
  ]),
  Endpoint.new("/api/posts/search", "GET", [Param.new("q", "", "query"), Param.new("take", "", "query")]),
  Endpoint.new("/api/posts/:id", "DELETE", [Param.new("id", "", "path")]),
  # Inline nested router with its own pathPrefix.
  Endpoint.new("/api/admin/stats", "GET"),
]

# Express (the server binding) and ts-rest.
FunctionalTester.new("fixtures/typescript/ts_rest/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
