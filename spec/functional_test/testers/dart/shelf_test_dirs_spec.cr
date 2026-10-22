require "../../func_spec.cr"

# Only bin/server.dart is a real route. The fake servers under tests/,
# lib/src/testing/, lib/test_utils/, integration_test/ and test_driver/,
# and the scaffold templates under __brick__/ and {{name}}/, are not served
# by the app.
expected_endpoints = [
  Endpoint.new("/real", "GET"),
]

tester = FunctionalTester.new("fixtures/dart/shelf_test_dirs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("dart_shelf"),
})
tester.perform_tests
