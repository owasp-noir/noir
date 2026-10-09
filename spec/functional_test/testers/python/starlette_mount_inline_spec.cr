require "../../func_spec.cr"

# `sub = Starlette(routes=[...])` with an inline routes list, mounted via
# `Mount("/v2", app=sub)`, serves its routes under the mount path.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/v2/items", "GET", [Param.new("q", "", "query")]),
]

FunctionalTester.new("fixtures/python/starlette_mount_inline/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
