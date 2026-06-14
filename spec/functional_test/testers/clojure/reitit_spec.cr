require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/ping", "GET"),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/api/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/dashboard", "GET"),
  Endpoint.new("/api/orders", "GET", [
    Param.new("limit", "", "query"),
    Param.new("offset", "", "query"),
  ]),
  Endpoint.new("/api/items", "GET", [
    Param.new("tag", "", "query"),
    Param.new("cursor", "", "query"),
  ]),
  Endpoint.new("/api/guarded/info", "GET"),
  Endpoint.new("/api/admin/reports/:id", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("status", "", "json"),
    Param.new("x-request-id", "", "header"),
  ]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/version", "GET"),
]

FunctionalTester.new("fixtures/clojure/reitit/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
