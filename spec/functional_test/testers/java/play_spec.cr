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
  Endpoint.new("/clients", "GET", [
    Param.new("page", "1", "query"),
    Param.new("label", "new,hot", "query"),
  ]),
  Endpoint.new("/api/list-all", "GET", [
    Param.new("version", "null", "query"),
  ]),
  Endpoint.new("/fixed-home", "GET"),
  Endpoint.new("/files/$path<.+>", "GET", [Param.new("path", "", "path")]),
  Endpoint.new("/upload", "POST"),
  Endpoint.new("/api/protected", "GET", [
    Param.new("Authorization", "", "header"),
    Param.new("session_id", "", "cookie"),
  ]),
  Endpoint.new("/api/data", "POST", [
    Param.new("Content-Type", "", "header"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/api/modern", "POST", [
    Param.new("X-Trace", "", "header"),
    Param.new("session_id", "", "cookie"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/async", "GET", [
    Param.new("X-Async", "", "header"),
  ]),
  Endpoint.new("/legacy-async", "GET", [
    Param.new("X-Legacy-Async", "", "header"),
  ]),
  Endpoint.new("/assets/*file", "GET", [
    Param.new("file", "", "path"),
  ]),
  Endpoint.new("/multipart", "POST", [
    Param.new("body", "", "form"),
  ]),
  Endpoint.new("/bytes", "POST", [
    Param.new("body", "", "body"),
  ]),
  Endpoint.new("/whitespace", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/api/static", "POST", [
    Param.new("X-Static", "", "header"),
    Param.new("body", "", "body"),
  ]),
  Endpoint.new("/api/reports/:reportId", "GET", [
    Param.new("reportId", "", "path"),
  ]),
  Endpoint.new("/api/reports", "POST", [
    Param.new("body", "", "json"),
  ]),
  # Controller in a non-`controllers` package (`app/v1/PostsApi.java`):
  # header + body enrichment must still resolve via the `play.mvc`
  # marker gate, not the package-path convention.
  Endpoint.new("/v1/posts", "POST", [
    Param.new("X-Posts-Trace", "", "header"),
    Param.new("body", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/java/play/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
