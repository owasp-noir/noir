require "../../func_spec.cr"

# Inline `register(fn, { prefix })` calls nest: routes inside the inner
# plugin carry every enclosing prefix, outermost first, under the file's own
# cross-file register prefix.
expected_endpoints = [
  Endpoint.new("/api/a", "GET"),
  Endpoint.new("/api/v2/b", "GET"),
  Endpoint.new("/internal/ping", "GET"),
  Endpoint.new("/internal/v2/echo", "POST"),
  Endpoint.new("/internal/v2/config", "PUT"),
]

FunctionalTester.new("fixtures/javascript/fastify_nested_register/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
