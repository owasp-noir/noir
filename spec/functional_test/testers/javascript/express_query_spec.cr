require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/search", "QUERY", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/items", "QUERY", [
    Param.new("filter", "", "query"),
  ]),
  Endpoint.new("/filter", "QUERY", [
    Param.new("category", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/javascript/express_query/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
