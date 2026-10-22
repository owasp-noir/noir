require "../../func_spec.cr"

# Mock servers a unit test starts on localhost live under tests/ and test/;
# the application never serves them. Only the src/ routes are endpoints.
expected_endpoints = [
  Endpoint.new("/real/crow", "GET"),
  Endpoint.new("/real/httplib", "GET"),
  Endpoint.new("/real/drogon", "GET"),
  Endpoint.new("/real/oatpp", "GET"),
]

tester = FunctionalTester.new("fixtures/cpp/test_dirs/", {
  :techs     => 4,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "C++ route analyzers skip test directories", tags: "functional" do
  it "drops the fake servers under tests/ and test/" do
    urls = tester.app.endpoints.map(&.url)
    urls.select(&.starts_with?("/fake/")).should be_empty
  end
end

# The gate reads the scan-base-relative path, so pointing -b at a tests/
# directory itself still reports what is inside it.
base_is_tests_endpoints = [
  Endpoint.new("/fake/crow", "GET"),
  Endpoint.new("/fake/httplib", "GET"),
  Endpoint.new("/fake/drogon", "GET"),
]

FunctionalTester.new("fixtures/cpp/test_dirs/tests/", {
  :techs     => 3,
  :endpoints => base_is_tests_endpoints.size,
}, base_is_tests_endpoints).perform_tests
