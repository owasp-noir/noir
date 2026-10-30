require "../../func_spec.cr"

# Both YAML and JSON Envoy config files live in the same fixture directory.
# The expected endpoints below cover:
#   YAML (route_config.virtual_hosts):
#     - prefix match (no :method)     → /v1/users   ANY
#     - path match with :method header → /admin      GET
#     - safe_regex match              → /api/v[0-9]+ ANY
#       (optimizer strips the leading `^` anchor via normalize_url_shapes)
#     - prefix_rewrite                → /            ANY  (extra endpoint)
#     - wildcard domain               → /health      ANY
#   JSON (virtual_hosts at top level):
#     - prefix match                  → /api         ANY
#     - path match with :method header → /status      GET
#   YAML (bootstrap: static_resources.listeners[].filter_chains[].filters[].
#         typed_config.route_config.virtual_hosts):
#     - prefix match                  → /bootstrap   ANY
#     - path_separated_prefix match   → /separated   ANY

expected_endpoints = [
  # ── YAML ──────────────────────────────────────────────────────────────────
  Endpoint.new("/v1/users", "ANY"),
  Endpoint.new("/admin", "GET"),
  # safe_regex: optimizer strips leading `^` from `/^/api/v[0-9]+`
  Endpoint.new("/api/v[0-9]+", "ANY"),
  # prefix_rewrite emits an extra endpoint with the rewritten path
  Endpoint.new("/", "ANY"),
  # wildcard domain ("*") → path only
  Endpoint.new("/health", "ANY"),
  # ── JSON ──────────────────────────────────────────────────────────────────
  Endpoint.new("/api", "ANY"),
  Endpoint.new("/status", "GET"),
  # ── YAML bootstrap ────────────────────────────────────────────────────────
  Endpoint.new("/bootstrap", "ANY"),
  Endpoint.new("/separated", "ANY"),
]

FunctionalTester.new("fixtures/specification/envoy/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
