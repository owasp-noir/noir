require "../../func_spec.cr"

# Coverage for the minified guard added to Fastify's auxiliary
# `extract_route_configs` pass (issue #1903 review). The sibling
# src/lib/vendor-bundle.js is a minified single line (not under any
# test-stub path, so `test_stub_only?` is false) that packs a
# `fastify.route({ method:'GET', url:'/leak' })` config. Without the
# `|| minified_content?(content)` clause on the aux-pass gate, `/leak`
# would leak. Only the two real routes from app.js may survive.

expected_endpoints = [
  Endpoint.new("/api/ping", "GET"),
  Endpoint.new("/api/health", "GET"),
]

FunctionalTester.new("fixtures/javascript/fastify_minified_noise/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
