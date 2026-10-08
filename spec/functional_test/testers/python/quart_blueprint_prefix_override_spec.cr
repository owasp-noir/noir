require "../../func_spec.cr"

# A url_prefix passed to register_blueprint() replaces the blueprint's own
# url_prefix; the own prefix is used only when url_prefix is omitted.
expected_endpoints = [
  Endpoint.new("/mounted/o", "GET"),
  Endpoint.new("/api/child/c", "GET"),
  Endpoint.new("/outer/mounted-inner/i", "GET"),
  Endpoint.new("/e", "GET"),
  Endpoint.new("/kept/k", "GET"),
]

FunctionalTester.new("fixtures/python/quart_blueprint_prefix_override/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
