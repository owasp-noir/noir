require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("filter", "", "query"),
  ]),
  Endpoint.new("/users/:userId/posts/:postId", "GET", [
    Param.new("userId", "", "path"),
    Param.new("postId", "", "path"),
  ]),
  Endpoint.new("/items", "GET", [
    Param.new("category", "", "query"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/files/$path<.+>", "GET", [Param.new("path", "", "path")]),
  Endpoint.new("/upload", "POST"),
  Endpoint.new("/api/protected", "GET"),
  Endpoint.new("/api/data", "POST"),
  Endpoint.new("/assets/*file", "GET", [
    Param.new("path", "", "query"),
    Param.new("file", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/scala/play/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
