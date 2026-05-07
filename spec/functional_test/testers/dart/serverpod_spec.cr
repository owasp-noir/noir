require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/example/hello", "POST", [
    Param.new("name", "String", "json"),
  ]),
  Endpoint.new("/example/add", "POST", [
    Param.new("a", "int", "json"),
    Param.new("b", "int", "json"),
  ]),
  Endpoint.new("/order/list", "POST", [
    Param.new("limit", "int", "json"),
    Param.new("cursor", "String?", "json"),
  ]),
  Endpoint.new("/order/create", "POST", [
    Param.new("order", "Order", "json"),
  ]),
  Endpoint.new("/health/ping", "POST"),
]

FunctionalTester.new("fixtures/dart/serverpod/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
