require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/get_param.jsp", "GET", [
    Param.new("username", "", "query"),
    Param.new("password", "", "query"),
  ]),
  Endpoint.new("/el.jsp", "GET", [Param.new("username", "", "query")]),
  Endpoint.new("/attribute.jsp", "GET", [Param.new("userId", "", "query")]),
  Endpoint.new("/header.jsp", "GET", [Param.new("X-API-Key", "", "header")]),
  Endpoint.new("/cookie.jsp", "GET", [Param.new("", "", "cookie")]),
]

FunctionalTester.new("fixtures/java/jsp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
