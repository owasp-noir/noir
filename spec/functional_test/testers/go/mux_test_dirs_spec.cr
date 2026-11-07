require "../../func_spec.cr"

# Helpers under test/, tests/ and e2e/ are test-only even when the file
# is not *_test.go (toxiproxy test/e2e/endpoint.go). The nested go.mod
# there is not named test/tests/e2e, so the directory segment has to win.
# testutil/ is a different segment and stays. integration/ is a production
# package name, so its routes stay too. Scanning the test/ directory
# itself keeps the routes that live directly in it.
expected_endpoints = [
  Endpoint.new("/proxies", "GET"),
  Endpoint.new("/kept", "GET"),
  Endpoint.new("/from-integration", "GET"),
]

tester = FunctionalTester.new("fixtures/go/mux_test_dirs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "Go analyzers skip conventional test directories", tags: "functional" do
  it "drops routes under test/, tests/ and e2e/ but keeps testutil/ and integration/" do
    urls = tester.endpoints.map(&.url)
    %w[/test1 /test2 /from-test /from-tests /from-e2e].each do |url|
      urls.should_not contain(url)
    end
    urls.should contain("/kept")
    urls.should contain("/proxies")
    urls.should contain("/from-integration")
  end
end

FunctionalTester.new("fixtures/go/mux_test_dirs/test/", {
  :techs     => 1,
  :endpoints => 1,
}, [Endpoint.new("/from-test", "GET")]).perform_tests
