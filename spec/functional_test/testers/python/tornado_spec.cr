require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET", [Param.new("name", "", "query")]),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [Param.new("username", "", "form"), Param.new("email", "", "form")]),
  Endpoint.new("/auth", "POST", [Param.new("X-API-Key", "", "header"), Param.new("auth_token", "", "cookie")]),
]

FunctionalTester.new("fixtures/python/tornado/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
