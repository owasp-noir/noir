require "../../func_spec.cr"

# `mount: { "/rest": [...] }` in the server's `@Configuration` prefixes the
# controllers.
expected_endpoints = [
  Endpoint.new("/rest/calendars", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/rest/calendars/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/rest/calendars", "POST", [
    Param.new("body", "", "body"),
    Param.new("x-api-key", "", "header"),
  ]),
  Endpoint.new("/rest/calendars/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("name", "", "body"),
  ]),
  Endpoint.new("/rest/calendars/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
]

# `:techs => 1`: the `@Controller` file must not also detect as ts_nestjs.
FunctionalTester.new("fixtures/typescript/tsed/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
