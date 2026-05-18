require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/todo", "GET"),
  Endpoint.new("/todo/:name", "DELETE", [
    Param.new("name", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/restify_client_noise/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
