require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/g", "GET"),
  Endpoint.new("/on1", "GET"),
  Endpoint.new("/on2", "GET", [Param.new("id", "", "query")]),
  Endpoint.new("/on2", "POST", [Param.new("id", "", "query")]),
]

FunctionalTester.new("fixtures/javascript/hono_on_receiver/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
