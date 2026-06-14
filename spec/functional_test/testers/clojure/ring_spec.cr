require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/ping", "ANY"),
  Endpoint.new("/metrics", "GET"),
  Endpoint.new("/sessions", "DELETE"),
  Endpoint.new("/version", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/contact/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/up", "GET"),
  Endpoint.new("/readiness", "GET"),
]

FunctionalTester.new("fixtures/clojure/ring/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
