require "../../func_spec.cr"

# A `PathValue("userID")` read in a called helper is not a path param of a
# route whose pattern has no `{userID}` wildcard.
expected_endpoints = [
  Endpoint.new("/users/{identifier}", "GET", [Param.new("identifier", "", "path")]),
  Endpoint.new("/files/{path...}", "GET", [Param.new("path", "", "path")]),
]

tester = FunctionalTester.new("fixtures/go/http_pathvalue_helper/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "http_pathvalue_helper", tags: "functional" do
  it "does not report a helper's PathValue the pattern has no wildcard for" do
    endpoint = tester.endpoints.find! { |ep| ep.url == "/users/{identifier}" }
    endpoint.params.map(&.name).should_not contain("userID")
  end
end
