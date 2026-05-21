require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/items", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/items", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/healthz", "GET"),
  Endpoint.new("/items/<int:item_id>", "DELETE"),
  Endpoint.new("/api/v1/users", "POST", [Param.new("username", "", "json")]),
  Endpoint.new("/ws", "GET"),
]

FunctionalTester.new("fixtures/python/quart/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
