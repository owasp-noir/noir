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
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/admin/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("force", "", "query"),
  ]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/ping", "ANY"),
]

FunctionalTester.new("fixtures/clojure/compojure/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
