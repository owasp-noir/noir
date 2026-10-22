require "../../func_spec.cr"

# `sub = Starlette(routes=[...])` with an inline routes list, mounted via
# `Mount("/v2", app=sub)` or positionally (`Mount("/pos", pos)`), serves its
# routes under the mount path. An app or StaticFiles mount does not prefix
# routes that merely share its line.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/v2/items", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/pos/inner", "GET"),
  Endpoint.new("/static/*", "GET"),
  Endpoint.new("/after", "GET"),
]

FunctionalTester.new("fixtures/python/starlette_mount_inline/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
