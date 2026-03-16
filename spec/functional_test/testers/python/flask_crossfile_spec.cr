require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/v1/login", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),
  Endpoint.new("/api/v1/logout", "GET"),
  Endpoint.new("/api/v2/items", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/api/v2/items", "POST", [
    Param.new("name", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/python/flask_crossfile/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
