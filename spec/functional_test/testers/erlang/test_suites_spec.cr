require "../../func_spec.cr"

# rebar3 projects keep Common Test suites (`test/*_SUITE.erl`) and EUnit
# modules (`*_tests.erl`) that build throwaway dispatch tables, and wrap
# in-module EUnit tests in `-ifdef(TEST).`. None of those routes is served by
# a deployed node; only the production clauses around them are.
expected_endpoints = [
  # Cowboy: the real table, the `-else.` branch (compiled without TEST) and
  # the code after the `-ifdef(TEST).` block.
  Endpoint.new("/real", "ANY"),
  Endpoint.new("/else-branch", "ANY"),
  Endpoint.new("/after-ifdef", "ANY"),
  # Elli: the real clauses around the `-ifdef(TEST).` clause.
  Endpoint.new("/ping", "GET"),
  Endpoint.new("/after-ifdef", "GET"),
]

tester = FunctionalTester.new("fixtures/erlang/test_suites/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

it "reports nothing from test suites, EUnit modules or -ifdef(TEST) regions", tags: "functional" do
  tester.endpoints.map(&.url).select { |url| url.includes?("only") || url.includes?("nested") || url == "/" }.should be_empty
end

it "keeps the line numbers of routes that follow a masked -ifdef(TEST) region", tags: "functional" do
  after = tester.endpoints.find! { |endpoint| endpoint.method == "ANY" && endpoint.url == "/after-ifdef" }
  after.details.code_paths.first.line.should eq 38
end
