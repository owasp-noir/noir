require "../../func_spec.cr"

# An unnamed catch-all (`[...].ts`) is h3's `_` param, not a literal segment.
expected_endpoints = [
  Endpoint.new("/api/proxy/:_", "ANY", [
    Param.new("_", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/nuxtjs_catchall/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
