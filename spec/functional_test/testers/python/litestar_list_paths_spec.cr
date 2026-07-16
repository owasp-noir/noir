require "../../func_spec.cr"

# Regression test: Litestar accepts a list of path strings
# (`@get(["/a", "/b"])`, `@get(path=["/a", "/b"])`) and registers one
# route per entry. Previously the list form was not recognized and the
# handler was dropped.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/index", "GET"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/healthz", "GET"),
  Endpoint.new("/status", "GET"),
]

FunctionalTester.new("fixtures/python/litestar_list_paths/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
