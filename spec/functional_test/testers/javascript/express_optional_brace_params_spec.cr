require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/user/:id{/:op}", "GET", [
    Param.new("id", "", "path"),
    Param.new("op", "", "path"),
  ]),
  Endpoint.new("/user/:id{/:op}", "POST", [
    Param.new("id", "", "path"),
    Param.new("op", "", "path"),
  ]),
  Endpoint.new("/user/:id{/:op}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("op", "", "path"),
  ]),
  Endpoint.new("/user/:id{/:op}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("op", "", "path"),
  ]),
  Endpoint.new("/user/:id{/:op}", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("op", "", "path"),
  ]),
  Endpoint.new("/user/:id{/:op}", "HEAD", [
    Param.new("id", "", "path"),
    Param.new("op", "", "path"),
  ]),
  Endpoint.new("/user/:id{/:op}", "OPTIONS", [
    Param.new("id", "", "path"),
    Param.new("op", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/express_optional_brace_params/", {
  :techs => 1,
}, expected_endpoints).perform_tests
