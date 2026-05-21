require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET", [
    Param.new("limit", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/javascript/express_bracket_only/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
