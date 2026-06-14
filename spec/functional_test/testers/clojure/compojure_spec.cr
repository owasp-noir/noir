require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/feed", "GET", [
    Param.new("cursor", "", "query"),
  ]),
  Endpoint.new("/tags", "GET", [
    Param.new("tag", "", "query"),
  ]),
  Endpoint.new("/notes", "POST", [
    Param.new("title", "", "query"),
    Param.new("body", "", "query"),
  ]),
  Endpoint.new("/comments", "POST", [
    Param.new("author", "", "query"),
    Param.new("message", "", "query"),
  ]),
  Endpoint.new("/profile/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/orders/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/coerce/:n", "GET", [
    Param.new("n", "", "path"),
  ]),
  Endpoint.new("/items/:item-id", "GET", [
    Param.new("item-id", "", "path"),
  ]),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/admin/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("force", "", "query"),
  ]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/ping", "ANY"),
  Endpoint.new("/widgets", "GET"),
  Endpoint.new("/widgets", "POST"),
  Endpoint.new("/widgets/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/health-check", "GET"),
  Endpoint.new("/metered", "GET"),
  Endpoint.new("/calc", "GET", [
    Param.new("x", "", "query"),
    Param.new("y", "", "query"),
  ]),
  Endpoint.new("/echo", "POST", [
    Param.new("message", "", "json"),
    Param.new("authorization", "", "header"),
  ]),
  Endpoint.new("/pair", "GET", [
    Param.new("a", "", "query"),
    Param.new("b", "", "query"),
  ]),
  Endpoint.new("/upload/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("file", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/clojure/compojure/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
