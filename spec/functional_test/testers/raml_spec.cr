require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/users/{userId}", "GET", [
    Param.new("userId", "", "query"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/raml/", {
  :techs     => 1,
  :endpoints => 2,
}, extected_endpoints).test_all
