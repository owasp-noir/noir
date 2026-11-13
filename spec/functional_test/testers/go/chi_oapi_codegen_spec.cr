require "../../func_spec.cr"

# oapi-codegen's chi server registers every operation as
# `r.Get(options.BaseURL+"/status", ...)`. The base is runtime config, so
# the route is its literal tail; before #3576 the whole path was dropped
# and a generated server reported nothing. `routes.go` covers a local copy
# of the base, a route outside a Group, a package constant (resolved in
# full) and two paths that stay dropped: a runtime value between literals
# (`"/users/"+id+"/avatar"`) and a path that is all runtime value.
expected_endpoints = [
  Endpoint.new("/status", "GET"),
  Endpoint.new("/items", "GET"),
  Endpoint.new("/items", "POST"),
  Endpoint.new("/items/{itemId}", "GET", [Param.new("itemId", "", "path")]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/items/{itemId}", "DELETE", [Param.new("itemId", "", "path")]),
  Endpoint.new("/v1/version", "GET"),
]

FunctionalTester.new("fixtures/go/chi_oapi_codegen/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
