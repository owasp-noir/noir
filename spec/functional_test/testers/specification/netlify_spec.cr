require "../../func_spec.cr"

# A `_redirects` source may be a bare path or a fully-qualified URL for a
# domain-level rule. The scheme and host of the latter are routing context, not
# part of the request path — the host lands in a `netlify-host` tag and the
# endpoint carries `/legacy`, not `https://old.example.com/legacy`.
expected_endpoints = [
  Endpoint.new("/home", "ANY"),
  Endpoint.new("/blog/*", "ANY"),
  Endpoint.new("/legacy", "ANY"),
  Endpoint.new("/api/*", "ANY"),
  Endpoint.new("/toml-api/*", "ANY"),
  # `[[context.production.redirects]]`
  Endpoint.new("/prod-only", "ANY"),
  Endpoint.new("/edge/*", "ANY"),
]

FunctionalTester.new("fixtures/specification/netlify/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
