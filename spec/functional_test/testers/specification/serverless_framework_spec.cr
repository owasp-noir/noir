require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/dev/users", "GET"),
  Endpoint.new("/dev/users", "POST"),
  # httpApi: served from the `$default` stage, no `/dev` segment.
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/dev/health", "GET"),
]

FunctionalTester.new("fixtures/specification/serverless_framework/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
