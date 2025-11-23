require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/get_param.jsp", "GET", [
    Param.new("username", "", "query"),
    Param.new("password", "", "query"),
  ]),
  Endpoint.new("/el.jsp", "GET", [Param.new("username", "", "query")]),
]

FunctionalTester.new("fixtures/java/jsp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
