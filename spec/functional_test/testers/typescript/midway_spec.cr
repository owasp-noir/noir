require "../../func_spec.cr"

# `koa.globalPrefix: '/v1'` from src/config/config.default.ts prefixes every
# route, and `@Get('/')` collapses into its controller prefix (no trailing
# slash), as Midway's `joinURLPath` does.
expected_endpoints = [
  # v2 `@midwayjs/decorator` controller at the root.
  Endpoint.new("/v1", "GET", [] of Param),
  # `@Controller(prefix, options)` / `@Get(path, options)`: only the first
  # argument is the path.
  Endpoint.new("/v1/api/users", "GET", [
    Param.new("page", "", "query"),
    Param.new("size", "", "query"),
  ]),
  Endpoint.new("/v1/api/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/v1/api/users", "POST", [
    Param.new("body", "", "body"),
    Param.new("x-request-id", "", "header"),
  ]),
  Endpoint.new("/v1/api/users/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("name", "", "body"),
  ]),
  # Midway spells DELETE as `@Del`.
  Endpoint.new("/v1/api/users/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  # `@All` expands to every verb.
  Endpoint.new("/v1/api/users/ping", "GET", [] of Param),
  Endpoint.new("/v1/api/users/ping", "POST", [] of Param),
  Endpoint.new("/v1/api/users/ping", "PUT", [] of Param),
  Endpoint.new("/v1/api/users/ping", "DELETE", [] of Param),
  Endpoint.new("/v1/api/users/ping", "PATCH", [] of Param),
  Endpoint.new("/v1/api/users/ping", "HEAD", [] of Param),
  Endpoint.new("/v1/api/users/ping", "OPTIONS", [] of Param),
]

# `:techs => 1`: the `@Controller` files must not also detect as ts_nestjs.
FunctionalTester.new("fixtures/typescript/midway/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
