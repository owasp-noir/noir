require "../../func_spec.cr"

# `go help packages`: a directory named testdata is ignored by the toolchain,
# so a route registered under it is parser input, never served.
expected_endpoints = [
  Endpoint.new("/real", "GET"),
  Endpoint.new("/real/mytestdata", "GET"),
]

tester = FunctionalTester.new("fixtures/go/testdata_dirs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "Go analyzers skip testdata directories", tags: "functional" do
  it "drops routes under testdata/ at any depth but keeps a mytestdata/ package" do
    urls = tester.app.endpoints.map(&.url)
    urls.select(&.starts_with?("/fake/")).should be_empty
    urls.should contain("/real/mytestdata")
  end
end

# The gate reads the scan-base-relative path, so pointing -b at a testdata/
# app itself still reports its routes.
FunctionalTester.new("fixtures/go/testdata_dirs/testdata/app/", {
  :techs     => 1,
  :endpoints => 1,
}, [Endpoint.new("/fake/testdata", "GET")]).perform_tests
