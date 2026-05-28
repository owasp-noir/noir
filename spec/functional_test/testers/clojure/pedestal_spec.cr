require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/files/*path", "GET", [
    Param.new("path", "", "path"),
  ]),
  Endpoint.new("/api/orders", "GET"),
  Endpoint.new("/api/orders/:order-id", "PATCH", [
    Param.new("order-id", "", "path"),
  ]),
  Endpoint.new("/api/admin/reports", "POST"),
  Endpoint.new("/api/admin/reports/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/map", "GET"),
  Endpoint.new("/map/status", "GET"),
  Endpoint.new("/map/jobs/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/orders", "POST"),
  Endpoint.new("/custom-query", "QUERY"),
  Endpoint.new("/expanded", "GET"),
  Endpoint.new("/verbose-parent/child", "GET"),
  Endpoint.new("/verbose-parent/health", "GET"),
  Endpoint.new("/search", "GET"),
]

FunctionalTester.new("fixtures/clojure/pedestal/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
