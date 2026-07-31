require "../../func_spec.cr"

# The fixture also carries `respond "Hello, world!"`, `redir
# https://www.example.com{uri} permanent`, `handle {` and `route {`. None of
# those has a matcher token, so none may produce an endpoint — they used to
# surface as `/"Hello,`, `https://www.example.com{uri}` and `/{`.
expected_endpoints = [
  Endpoint.new("/v1/*", "ANY"),
  Endpoint.new("/admin/*", "ANY"),
  Endpoint.new("/api/*", "GET"),
  Endpoint.new("/api/*", "POST"),
  Endpoint.new("/old", "ANY"),
]

FunctionalTester.new("fixtures/specification/caddy/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
