require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/posts/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/search", "GET"),
  Endpoint.new("/upload", "POST"),
  Endpoint.new("/socket", "GET"), # WebSocket endpoint
  Endpoint.new("/test.html", "GET"),
  Endpoint.new("/style.css", "GET"),
]

FunctionalTester.new("fixtures/crystal/amber/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
