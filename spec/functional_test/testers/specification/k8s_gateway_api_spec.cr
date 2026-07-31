require "../../func_spec.cr"

search = Endpoint.new("/v1/search", "GET")
# `headers` / `queryParams` matchers are conditions the route will not fire
# without, so they are request params.
search.params = [
  Param.new("X-Api-Version", "2", "header"),
  Param.new("q", "term", "query"),
]

expected_endpoints = [
  Endpoint.new("/v1/users", "GET"),
  Endpoint.new("/v1/users", "POST"),
  Endpoint.new("/v2/.*", "ANY"),
  Endpoint.new("/v1/legacy", "ANY"),
  # Second document declares `kind: "HTTPRoute"` (quoted).
  search,
]

FunctionalTester.new("fixtures/specification/k8s_gateway_api/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
