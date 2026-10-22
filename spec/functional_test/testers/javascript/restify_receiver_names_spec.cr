require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/a", "GET"),
  Endpoint.new("/b", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/d", "OPTIONS", [Param.new("origin", "", "query")]),
]

FunctionalTester.new("fixtures/javascript/restify_receiver_names/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
