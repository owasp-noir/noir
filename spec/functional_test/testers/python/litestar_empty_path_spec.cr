require "../../func_spec.cr"

# Regression test: Litestar defaults an omitted path to "" (joined with any
# controller prefix). Previously `@get()` / `@get(sync_to_thread=False)` and
# controller methods without a path were dropped entirely (0 endpoints).
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/", "POST"),
  Endpoint.new("/items", "GET"),
  Endpoint.new("/items", "POST", [Param.new("data", "", "json")]),
]

FunctionalTester.new("fixtures/python/litestar_empty_path/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
