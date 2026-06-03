require "../../func_spec.cr"

# Gotham scoped routing: `route.scope("/api", |route| { ... })` prepends
# a segment, nested scopes compose (`/api/v2/...`), and
# `route.with_pipeline_chain(chain, |route| { ... })` adds middleware
# without changing the path. Handler-body enrichment (the Authorization
# header) still resolves through the composed route.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/v2/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/profile", "GET", [Param.new("Authorization", "", "header")]),
]

FunctionalTester.new("fixtures/rust/gotham_scope/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
