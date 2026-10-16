require "../../func_spec.cr"

# Closure-form UrlMappings: the body is brace-matched, so the
# `action = [POST: ...]` verb map after a nested `controller = { ... }`
# closure is read instead of falling back to a fabricated GET.
expected_endpoints = [
  Endpoint.new("/api/fulfillments", "POST"),
  Endpoint.new("/api/widgets", "GET"),
  Endpoint.new("/api/widgets", "POST"),
  Endpoint.new("/api/gadgets", "DELETE"),
  Endpoint.new("/api/legacy", "PUT"),
  Endpoint.new("/api/status", "GET"),
]

FunctionalTester.new("fixtures/groovy/grails_closure_verbs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
