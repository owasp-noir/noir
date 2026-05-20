require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users/{userId}/sessions", "POST", [
    Param.new("userId", "", "path"),
    Param.new("X-Session-Token", "", "header"),
    Param.new("region", "", "query"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/users/{userId}", "GET", [
    Param.new("userId", "", "path"),
    Param.new("verbose", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/specification/smithy/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
