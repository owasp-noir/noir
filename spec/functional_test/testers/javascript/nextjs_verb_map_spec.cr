require "../../func_spec.cr"

# A default export wrapping a verb-keyed object serves only those verbs
# (the wrapper answers 405 for the rest). A spread, or an options object
# with no verb key, keeps the all-methods fallback. `e2e/site/` is a
# harness app; `app/api/e2e/` below the router directory is a real URL.
expected_endpoints = [
  Endpoint.new("/api/comments", "GET"),
  Endpoint.new("/api/comments", "POST"),
  Endpoint.new("/api/traces", "GET"),
  Endpoint.new("/api/traces", "DELETE"),
  Endpoint.new("/api/traces", "PATCH"),
  Endpoint.new("/api/spread", "GET"),
  Endpoint.new("/api/spread", "POST"),
  Endpoint.new("/api/spread", "PUT"),
  Endpoint.new("/api/spread", "DELETE"),
  Endpoint.new("/api/spread", "PATCH"),
  Endpoint.new("/api/auth", "GET"),
  Endpoint.new("/api/auth", "POST"),
  Endpoint.new("/api/auth", "PUT"),
  Endpoint.new("/api/auth", "DELETE"),
  Endpoint.new("/api/auth", "PATCH"),
  Endpoint.new("/api/e2e", "GET"),
]

FunctionalTester.new("fixtures/javascript/nextjs_verb_map/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
