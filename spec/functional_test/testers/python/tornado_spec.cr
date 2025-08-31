require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET", [Param.new("name", "", "query")]),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [Param.new("username", "", "form"), Param.new("email", "", "form")]),
  Endpoint.new("/auth", "POST", [Param.new("X-API-Key", "", "header"), Param.new("auth_token", "", "cookie")]),
]

FunctionalTester.new("fixtures/python/tornado/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests