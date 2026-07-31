require "../../func_spec.cr"

# A wrangler route pattern is host-qualified (`example.com/api/*`). The host is
# routing context, not part of the request path, so it becomes a
# `wrangler-host` tag and the endpoint carries the path alone.
expected_endpoints = [
  Endpoint.new("/*", "ANY"),
  Endpoint.new("/api/*", "ANY"),
  # mixed-routes/wrangler.toml: `routes` mixes a bare string with an inline
  # table, which the bundled TOML shard rejects — recovered by the fallback.
  Endpoint.new("/assets/*", "ANY"),
  Endpoint.new("/edge/*", "ANY"),
]

FunctionalTester.new("fixtures/specification/cloudflare_wrangler/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
