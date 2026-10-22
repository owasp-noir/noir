require "../../func_spec.cr"

# `-ifdef(TEST). -include_lib("eunit/include/eunit.hrl"). -endif.` on one line
# is valid Erlang and opens and closes the region within the line; the mask
# must not stay open for the rest of the module. Regions that really are
# TEST-only (multi-line, one-line, and the `-else.` of `-ifndef(TEST).`)
# stay suppressed.
expected_endpoints = [
  Endpoint.new("/after-inline", "ANY"),
  Endpoint.new("/ifndef-branch", "ANY"),
  Endpoint.new("/after-all", "ANY"),
]

tester = FunctionalTester.new("fixtures/erlang/ifdef_inline/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

it "reports nothing from TEST-only regions, one-line or multi-line", tags: "functional" do
  tester.endpoints.map(&.url).select(&.includes?("test-only")).should be_empty
end

it "keeps the line numbers of routes that follow masked regions", tags: "functional" do
  after = tester.endpoints.find! { |endpoint| endpoint.url == "/after-all" }
  after.details.code_paths.first.line.should eq 38
end
