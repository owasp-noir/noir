require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/multi", "GET"),
  Endpoint.new("/multi", "POST"),
  Endpoint.new("/filter", "GET", [
    Param.new("type", "", "query"),
    Param.new("page", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/go/mux_route_constraints/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
