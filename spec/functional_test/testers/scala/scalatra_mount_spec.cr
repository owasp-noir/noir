require "../../func_spec.cr"

# ApiController is mounted at "/api/users" in ScalatraBootstrap, so each route is
# served under that prefix. The `get(...)`/`post(...)` calls in the test spec are
# HTTP client requests, not route definitions, and must be excluded.
expected_endpoints = [
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users", "POST", [Param.new("name", "", "query")]),
]

FunctionalTester.new("fixtures/scala/scalatra_mount/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
