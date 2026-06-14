require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{userId}", "GET", [Param.new("userId", "", "path")]),
  Endpoint.new("/users", "POST", [Param.new("body", "CreateUser", "json")]),
  Endpoint.new("/api/v1/status", "GET"),
  Endpoint.new("/api/v1/items", "GET", [
    Param.new("category", "", "query"),
    Param.new("sort", "", "query"),
  ]),
  Endpoint.new("/api/v1/items/{itemId}", "GET", [Param.new("itemId", "", "path")]),
  Endpoint.new("/api/v1/items/{itemId}", "PUT", [
    Param.new("itemId", "", "path"),
    Param.new("body", "UpdateItem", "json"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/api/v1/items/{itemId}", "DELETE", [
    Param.new("itemId", "", "path"),
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/search", "POST", [Param.new("q", "", "query")]),
  # Declarative Endpoint(...) DSL: trailing `.out[Int]` must not add a phantom
  # path param; query comes from the `.query(...)` codec chain.
  Endpoint.new("/v2/users/{userId}", "GET", [Param.new("userId", "", "path")]),
  Endpoint.new("/v2/users/{userId}/posts", "GET", [
    Param.new("userId", "", "path"),
    Param.new("name", "", "query"),
  ]),
  # Response headers (`Headers(Header.ContentType(...))`) are not request params.
  Endpoint.new("/v2/download", "GET"),
]

FunctionalTester.new("fixtures/scala/zio_http/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
