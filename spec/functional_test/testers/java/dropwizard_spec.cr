require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/hello/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Trace", "", "header"),
  ]),
  Endpoint.new("/hello", "POST", [
    Param.new("subject", "", "form"),
    Param.new("body", "", "form"),
  ]),
  Endpoint.new("/hello/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("message", "", "json"),
    Param.new("locale", "", "json"),
  ]),
  Endpoint.new("/hello/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/java/dropwizard/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
