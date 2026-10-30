require "../../func_spec.cr"
require "../../../../src/cli/inspect"

# A ServeMux pattern ending in `/` serves its subtree and is tagged so, which
# `noir trace` reads; `/exact/{$}` is reported as `/exact/` but serves only
# that path, so it carries no tag.
expected_endpoints = [
  Endpoint.new("/exact/", "GET"),
  Endpoint.new("/reader/api/0/", "GET"),
  Endpoint.new("/api/v1/users", "GET"),
]

tester = FunctionalTester.new("fixtures/go/http_subtree/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "net/http subtree patterns", tags: "functional" do
  it "tags a subtree pattern, not an exact {$} one, and trace serves only the subtree" do
    endpoints = tester.app.endpoints
    tagged = endpoints.select { |ep| ep.tags.any? { |t| t.name == "go-http-path-type" && t.description == "subtree" } }
    tagged.map(&.url).should eq(["/reader/api/0/"])
    Noir::CLI::Inspect.trace(endpoints, "GET", "/reader/api/0/stream/contents").map { |m| {m.endpoint.url, m.matched_by} }.should eq([{"/reader/api/0/", "prefix"}])
    Noir::CLI::Inspect.trace(endpoints, "GET", "/exact/x").should be_empty
    Noir::CLI::Inspect.trace(endpoints, "GET", "/exact/").map(&.matched_by).should eq(["exact"])
  end
end
