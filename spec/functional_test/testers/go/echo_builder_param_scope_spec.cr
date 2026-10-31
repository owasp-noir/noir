require "../../func_spec.cr"

# vikunja: `registerAPIRoutes(a)` and `registerAPIRoutesV2(e, a2)` both name
# their group parameter `a`, the same name as `RegisterRoutes`' `/api/v1`
# group. The v2 helper is handed `e.Group(apiv2.GroupPrefix)` (another
# package's constant), and hands its own parameter on to `m.Register(a)`.
# Each parameter is scoped to its helper: the v2 routes, MCP included, are
# served under `/api/v2`.
expected_endpoints = [
  Endpoint.new("/api/v2/docs", "GET"),
  Endpoint.new("/api/v2/ws", "GET"),
  Endpoint.new("/api/v2/mcp", "POST"),
  Endpoint.new("/api/v1/info", "GET"),
  Endpoint.new("/api/v1/user", "GET"),
]

FunctionalTester.new("fixtures/go/echo_builder_param_scope/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
