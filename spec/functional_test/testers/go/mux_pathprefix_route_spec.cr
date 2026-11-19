require "../../func_spec.cr"

# `PathPrefix(...).Handler/HandlerFunc` routes, a subrouter's `.Methods(...)`
# matcher and an inline `.Subrouter()` receiver. The `http.Dir` file server
# under `/assets/` stays a static mount (no files, so no endpoint).
proxy = %w[GET POST PUT DELETE PATCH HEAD OPTIONS].map { |verb| Endpoint.new("/proxy/", verb) }
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/webhooks/", "POST", [Param.new("X-Signature", "", "header")]),
  Endpoint.new("/readonly/items", "GET"),
  Endpoint.new("/readonly/items", "HEAD"),
  Endpoint.new("/readonly/purge", "POST"),
  Endpoint.new("/inline/ping", "GET"),
] + proxy

FunctionalTester.new("fixtures/go/mux_pathprefix_route/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
