require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/service/api/hello", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/service/api/hello/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Trace", "", "header"),
  ]),
  Endpoint.new("/service/api/hello", "POST", [
    Param.new("subject", "", "form"),
    Param.new("body", "", "form"),
  ]),
  Endpoint.new("/service/api/hello/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("message", "", "json"),
    Param.new("locale", "", "json"),
  ]),
  Endpoint.new("/service/api/hello/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/service/assets/*", "GET"),
  Endpoint.new("/service/admin/*", "GET"),
]

FunctionalTester.new("fixtures/java/dropwizard/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
