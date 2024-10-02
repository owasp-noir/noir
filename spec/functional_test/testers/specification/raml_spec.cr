require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/users/{userId}", "GET", [
    Param.new("userId", "", "path"),
    Param.new("userId", "", "query"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/raml/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).test_all
