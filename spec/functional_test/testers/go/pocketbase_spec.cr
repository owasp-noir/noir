require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/foos/", "GET"),
  Endpoint.new("/foos/", "POST"),
  Endpoint.new("/foos/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/foos/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/foos/{id}", "DELETE", [Param.new("id", "", "path")]),
  # A sibling file reuses the `sub` group var with a different prefix and a
  # `.Bind(...).Unbind(...)` middleware chain — the chain must be peeled so
  # `/bars` resolves locally instead of inheriting `/foos` (cross-file
  # contamination from the shared variable name).
  Endpoint.new("/bars/", "GET"),
  Endpoint.new("/bars/", "POST"),
  Endpoint.new("/bars/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/_/extensions.js", "GET"),
]

FunctionalTester.new("fixtures/go/pocketbase/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

# A stock app imports only `pocketbase` + `core` (never `tools/router`) and
# registers on the `se.Router` field inside the OnServe hook.
stock_endpoints = [
  Endpoint.new("/hello/{name}", "GET", [Param.new("name", "", "path")]),
  Endpoint.new("/api/custom/items", "POST"),
]

FunctionalTester.new("fixtures/go/pocketbase_stock/", {
  :techs     => 1,
  :endpoints => stock_endpoints.size,
}, stock_endpoints).perform_tests
