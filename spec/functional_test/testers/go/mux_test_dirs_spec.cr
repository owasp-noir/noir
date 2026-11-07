require "../../func_spec.cr"

# Helpers under test/, tests/, e2e/ and integration/ are test-only even
# when the file is not *_test.go (toxiproxy test/e2e/endpoint.go). The
# nested go.mod there is not named test/tests/e2e, so the directory
# segment has to win. testutil/ is a different segment and stays.
# Scanning the test/ directory itself keeps the routes that live directly
# in it.
expected_endpoints = [
  Endpoint.new("/proxies", "GET"),
  Endpoint.new("/kept", "GET"),
]

tester = FunctionalTester.new("fixtures/go/mux_test_dirs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "Go analyzers skip conventional test directories", tags: "functional" do
  it "drops routes under test/, tests/, e2e/ and integration/ but keeps testutil/" do
    urls = tester.endpoints.map(&.url)
    %w[/test1 /test2 /from-test /from-tests /from-e2e /from-integration].each do |url|
      urls.should_not contain(url)
    end
    urls.should contain("/kept")
    urls.should contain("/proxies")
  end
end

FunctionalTester.new("fixtures/go/mux_test_dirs/test/", {
  :techs     => 1,
  :endpoints => 1,
}, [Endpoint.new("/from-test", "GET")]).perform_tests
