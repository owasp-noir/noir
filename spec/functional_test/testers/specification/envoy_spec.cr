require "../../func_spec.cr"

# Both YAML and JSON Envoy config files live in the same fixture directory.
# The expected endpoints below cover:
#   YAML (route_config.virtual_hosts):
#     - prefix match                  → /v1/users   GET
#     - path match with :method header → /admin      GET
#     - safe_regex match              → /api/v[0-9]+ GET
#       (optimizer strips the leading `^` anchor via normalize_url_shapes)
#     - prefix_rewrite                → /            GET  (extra endpoint)
#     - wildcard domain               → /health      GET
#   JSON (virtual_hosts at top level):
#     - prefix match                  → /api         GET
#     - path match with :method header → /health      GET

expected_endpoints = [
  # ── YAML ──────────────────────────────────────────────────────────────────
  Endpoint.new("/v1/users", "GET"),
  Endpoint.new("/admin", "GET"),
  # safe_regex: optimizer strips leading `^` from `/^/api/v[0-9]+`
  Endpoint.new("/api/v[0-9]+", "GET"),
  # prefix_rewrite emits an extra endpoint with the rewritten path
  Endpoint.new("/", "GET"),
  # wildcard domain ("*") → path only
  Endpoint.new("/health", "GET"),
  # ── JSON ──────────────────────────────────────────────────────────────────
  Endpoint.new("/api", "GET"),
  Endpoint.new("/status", "GET"),
]

FunctionalTester.new("fixtures/specification/envoy/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
