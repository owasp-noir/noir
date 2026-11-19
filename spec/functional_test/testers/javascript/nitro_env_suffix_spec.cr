require "../../func_spec.cr"

# `debug.get.dev.ts` / `metrics.prod.ts`: the environment suffix is no part
# of the URL, and the method suffix before it still applies.
expected_endpoints = [
  Endpoint.new("/debug", "GET"),
  Endpoint.new("/ok", "GET"),
] + %w[GET POST PUT DELETE PATCH HEAD OPTIONS].map { |method| Endpoint.new("/metrics", method) }

FunctionalTester.new("fixtures/javascript/nitro_env_suffix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
