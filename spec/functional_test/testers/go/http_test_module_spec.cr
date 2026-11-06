require "../../func_spec.cr"

# A nested module named for a test tree (`module example.com/shop/tests`) is
# built by the test run only: its fake upstream servers are not the app's
# routes. A module named `testing` is not judged by its name. Scanning the
# test module itself keeps its routes.
FunctionalTester.new("fixtures/go/http_test_module/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/orders/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/health", "GET"),
]).perform_tests

FunctionalTester.new("fixtures/go/http_test_module/tests/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/v1/charges", "POST"),
]).perform_tests
