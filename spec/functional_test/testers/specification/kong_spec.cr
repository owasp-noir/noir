require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/users", "GET"),
  Endpoint.new("/v1/users", "POST"),
  # `~` selects Kong 3.x regex mode; it is a marker, not a path segment, so the
  # URL is `/admin/.*` and the mode is carried by the `kong-path-type` tag.
  Endpoint.new("/admin/.*", "ANY"),
  Endpoint.new("/v1/orders", "GET"),
  Endpoint.new("/v1/orders", "POST"),
]

FunctionalTester.new("fixtures/specification/kong/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
