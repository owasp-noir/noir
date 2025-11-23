require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/about/", "GET"),
  Endpoint.new("/zz", "GET"),
  Endpoint.new("/zz/", "DELETE"),
  Endpoint.new("/111", "PUT"),
  Endpoint.new("/about/", "POST", [Param.new("data", "", "form"), Param.new("id", "", "form")]),
]

FunctionalTester.new("fixtures/specification/zap/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
