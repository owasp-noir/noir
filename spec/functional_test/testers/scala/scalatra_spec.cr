require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id/posts/:postId", "GET", [
    Param.new("id", "", "path"),
    Param.new("postId", "", "path"),
  ]),
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("filter", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [Param.new("body", "User", "json")]),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("body", "User", "json"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/items", "GET", [Param.new("tags", "", "query")]),
  Endpoint.new("/upload", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/profile", "GET", [Param.new("session", "", "cookie")]),
  Endpoint.new("/download/*", "GET", [Param.new("splat", "", "path")]),
]

FunctionalTester.new("fixtures/scala/scalatra/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
