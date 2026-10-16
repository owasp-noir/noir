require "../../func_spec.cr"

# In Dart Frog the folder names under `routes/` are URL segments, so
# `routes/tests/` and `routes/testing/` (a quiz or QA backend) serve real
# `/tests` and `/testing` routes. A `tests/routes/` tree above the project's
# routes and Dart Frog's `test/routes/` mirror are mocks and stay suppressed.
expected_endpoints = [
  Endpoint.new("/tests", "GET"),
  Endpoint.new("/tests/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/testing/health", "GET"),
]

tester = FunctionalTester.new("fixtures/dart/dart_frog_test_segments/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reports nothing from the tests/ and test/ mirror trees", tags: "functional" do
  tester.endpoints.map(&.url).should_not contain("/mock")
end
