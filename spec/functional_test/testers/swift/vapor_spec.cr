require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/v2/ping", "GET"),
  Endpoint.new("/users", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/users/:userID", "GET", [Param.new("userID", "", "path")]),
  Endpoint.new("/users/:userID/posts/:postID", "PUT", [Param.new("postID", "", "path"), Param.new("userID", "", "path")]),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query"), Param.new("sort", "", "query")]),
  Endpoint.new("/api/login", "POST", [Param.new("Authorization", "", "header"), Param.new("body", "", "json")]),
  Endpoint.new("/profile", "GET", [Param.new("session", "", "cookie")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/articles/:articleID", "PATCH", [Param.new("articleID", "", "path"), Param.new("body", "", "json")]),
  Endpoint.new("/status", "GET"),
  # Chained `.grouped(...)` and verbs called on a group expression.
  Endpoint.new("/api/v3/items", "GET"),
  Endpoint.new("/secure/vault", "GET"),
  Endpoint.new("/inline/direct", "GET"),
  Endpoint.new("/a/b/c", "POST"),
  # RoutesBuilder extension: bare `grouped(...)` + `self.<verb>` (AdminRoutes).
  Endpoint.new("/admin/dashboard", "GET"),
  Endpoint.new("/purge", "POST"),
]

FunctionalTester.new("fixtures/swift/vapor/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
