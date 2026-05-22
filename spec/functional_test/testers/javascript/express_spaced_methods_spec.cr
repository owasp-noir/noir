require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/spaced-get", "GET", [
    Param.new("mode", "", "query"),
  ]),
  Endpoint.new("/spaced-post", "POST", [
    Param.new("title", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/javascript/express_spaced_methods/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
