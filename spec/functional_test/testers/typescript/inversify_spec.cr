require "../../func_spec.cr"

# `rootPath: "/api"` in the `InversifyExpressServer` options prefixes every
# controller.
expected_endpoints = [
  Endpoint.new("/api/users", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/api/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("body", "", "body"),
    Param.new("x-api-key", "", "header"),
  ]),
  Endpoint.new("/api/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/typescript/inversify/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
