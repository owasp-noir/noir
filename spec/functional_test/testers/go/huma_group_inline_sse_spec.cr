require "../../func_spec.cr"

# Huma: `huma.NewGroup` prefixes (nested too), `sse.Register` operations,
# and inline `*struct {...}` input types (query, header and JSON body fields).
expected_endpoints = [
  Endpoint.new("/count/{count}", "PUT", [Param.new("count", "", "path"), Param.new("q", "", "query"), Param.new("X-Count", "", "header"), Param.new("name", "", "json")]),
  Endpoint.new("/v1/items", "GET", [Param.new("limit", "", "query")]),
  Endpoint.new("/v1/admin/items/{id}", "DELETE", [Param.new("id", "", "path")]),
  # `huma.NewGroup(api, "/v2", "/api/v2")` serves under both prefixes.
  Endpoint.new("/v2/ping", "GET"),
  Endpoint.new("/api/v2/ping", "GET"),
  Endpoint.new("/sse", "GET"),
]

# humago serves on a net/http mux, so go_http is detected alongside go_huma.
FunctionalTester.new("fixtures/go/huma_group_inline_sse/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
