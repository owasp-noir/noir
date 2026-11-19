require "../../func_spec.cr"

# httprouter's stdlib-handler adapters `router.HandlerFunc(method, path, h)`
# and `router.Handler(method, path, h)` register routes like `Handle`.
expected_endpoints = [
  Endpoint.new("/v1/healthcheck", "GET"),
  Endpoint.new("/v1/movies", "GET", [Param.new("title", "", "query")]),
  Endpoint.new("/v1/movies/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/v1/movies/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/debug/vars", "GET"),
  Endpoint.new("/v1/native/:id", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/go/httprouter_handlerfunc/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
