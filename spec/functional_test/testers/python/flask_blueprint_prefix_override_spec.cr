require "../../func_spec.cr"

# A url_prefix passed to register_blueprint() replaces the blueprint's own
# url_prefix; the own prefix is used only when url_prefix is omitted.
# A blueprint registered twice is served under both registrations.
expected_endpoints = [
  Endpoint.new("/mounted/o", "GET"),
  Endpoint.new("/api/child/c", "GET"),
  Endpoint.new("/outer/mounted-inner/i", "GET"),
  Endpoint.new("/e", "GET"),
  Endpoint.new("/kept/k", "GET"),
  Endpoint.new("/v1/t", "GET"),
  Endpoint.new("/v2/t", "GET"),
]

FunctionalTester.new("fixtures/python/flask_blueprint_prefix_override/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
