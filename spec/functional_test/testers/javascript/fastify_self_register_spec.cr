require "../../func_spec.cr"

# A plugin that registers itself used to grow its own prefix list while
# iterating it, so the scan never finished (multi-GB RSS). The
# self-registration is also not a top-level prefix (`/child/node`).
expected_endpoints = [
  Endpoint.new("/api/node", "GET"),
]

FunctionalTester.new("fixtures/javascript/fastify_self_register/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
