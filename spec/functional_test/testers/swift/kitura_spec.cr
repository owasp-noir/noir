require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/users", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/users/:userID", "GET", [Param.new("userID", "", "path")]),
  Endpoint.new("/users/:userID/posts/:postID", "PUT", [Param.new("postID", "", "path"), Param.new("userID", "", "path")]),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query"), Param.new("sort", "", "query")]),
  Endpoint.new("/api/login", "POST", [Param.new("Authorization", "", "header")]),
  Endpoint.new("/profile", "GET", [Param.new("session", "", "cookie")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/articles/:articleID", "PATCH", [Param.new("articleID", "", "path"), Param.new("body", "", "json")]),
  Endpoint.new("/status", "GET"),
]

FunctionalTester.new("fixtures/swift/kitura/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
