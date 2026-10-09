require "../../func_spec.cr"

# `routePrefix: '/api'` from `createExpressServer` prefixes every controller.
expected_endpoints = [
  Endpoint.new("/api/users", "GET", [
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/api/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("body", "", "body"),
    Param.new("authorization", "", "header"),
  ]),
  Endpoint.new("/api/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
  # Plain `@Controller()` with no prefix.
  Endpoint.new("/api/health", "GET", [] of Param),
]

# `:techs => 1`: the `@Controller` file must not also detect as ts_nestjs.
FunctionalTester.new("fixtures/typescript/routing_controllers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
