require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/g", "GET"),
  Endpoint.new("/r1", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/r4", "GET"),
  Endpoint.new("/q1", "QUERY", [Param.new("term", "", "query")]),
  Endpoint.new("/r5", "DELETE"),
  Endpoint.new("/ws", "GET"),
]

FunctionalTester.new("fixtures/javascript/fastify_plugin_receiver/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
