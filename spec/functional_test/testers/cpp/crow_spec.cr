require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/update", "POST", [
    Param.new("name", "", "query"),
    Param.new("X-Token", "", "header"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/user/{param1}/{param2}", "GET", [
    Param.new("param1", "", "path"),
    Param.new("param2", "", "path"),
  ]),
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/cpp/crow/", {
  :techs     => 1,
  :endpoints => 4,
}, expected_endpoints).perform_tests
