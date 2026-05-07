require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/users", "GET"),
  Endpoint.new("/v1/users/:userId", "GET", [
    Param.new("userId", "Integer", "path"),
  ]),
  Endpoint.new("/v1/users", "POST", [
    Param.new("body", "User", "body"),
  ]),
  Endpoint.new("/v1/users/:userId", "PUT", [
    Param.new("userId", "Integer", "path"),
    Param.new("body", "User", "body"),
  ]),
  Endpoint.new("/v1/users/:userId", "DELETE", [
    Param.new("userId", "Integer", "path"),
  ]),
  Endpoint.new("/v1/search", "GET", [
    Param.new("q", "Text", "query"),
  ]),
  Endpoint.new("/v1/files/*path", "GET", [
    Param.new("path", "Text", "path"),
  ]),
  Endpoint.new("/v1/secure", "GET", [
    Param.new("X-Token", "Text", "header"),
  ]),
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/haskell/servant/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
