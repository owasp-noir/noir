require "../../func_spec.cr"

# A unit-test harness under test/ is not part of the served surface; the
# library-named VENDORED_DIR gate never fires here (no mongoose/ parent).
expected_endpoints = [
  Endpoint.new("/real/mongoose", "GET"),
]

tester = FunctionalTester.new("fixtures/c/test_dirs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

# Scanning the test directory itself keeps its routes (scan-base-relative gate).
FunctionalTester.new("fixtures/c/test_dirs/test/", {
  :techs     => 1,
  :endpoints => 1,
}, [Endpoint.new("/fake/mongoose", "GET")]).perform_tests
