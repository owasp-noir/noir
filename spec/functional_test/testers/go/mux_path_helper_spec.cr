require "../../func_spec.cr"

# Regression (#3578): a gorilla/mux route whose path goes through a
# one-string wrapper (`s.prefixedPath("/version")`, podinfo's shape) was
# dropped, because the mux chain decoder read only string literals. The
# wrapper's runtime prefix is not readable, so the literal is the route.
# `lookupPath("hidden")` returns nothing readable and stays dropped, and
# `http.Get(apiPath("/remote"))` is a client call, not a route.
expected_endpoints = [
  Endpoint.new("/version", "GET"),
  Endpoint.new("/store", "POST"),
  Endpoint.new("/store/{hash}", "GET"),
  Endpoint.new("/api/health", "GET"),
]

FunctionalTester.new("fixtures/go/mux_path_helper/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
