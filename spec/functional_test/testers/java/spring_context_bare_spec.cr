require "../../func_spec.cr"

# A controller with no class-level `@RequestMapping` under a configured
# `server.servlet.context-path`. The route extractor resolves an unmapped
# class to an empty prefix, so the context path is the only segment on the
# left of the join — and a bare `@GetMapping` puts an empty string on the
# right.
#
# That pair used to reach the top-level `join_paths` (`File.join`), which
# appends a separator for an empty trailing segment: `File.join("/portal",
# "")` is `"/portal/"`. Spring serves the mapping at `/portal`. Every other
# Java analyzer in the directory composed paths with `Helper.join_paths`;
# only the two Spring analyzers fell through to the global.
expected_endpoints = [
  Endpoint.new("/servlet/tenant-info", "GET"),
  Endpoint.new("/portal/external", "GET"),
  Endpoint.new("/portal/choice", "GET"),
  Endpoint.new("/portal", "GET"),
  Endpoint.new("/portal/users", "POST"),
]

tester = FunctionalTester.new("fixtures/java/spring_context_bare/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "spring_context_bare route resolution", tags: "functional" do
  it "records the evidence for each reported route" do
    tester.endpoints.find! { |ep| ep.url == "/servlet/tenant-info" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/portal/choice" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/portal/external" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/portal" }.resolution.should be_nil
    tester.endpoints.find! { |ep| ep.url == "/portal/users" }.resolution.should be_nil
  end
end
