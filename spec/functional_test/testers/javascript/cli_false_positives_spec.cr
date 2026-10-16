require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# --- `cac` evidence marker is word-bounded ----------------------------------
# A caching module ("cache"/"cacheName" contain the letters c-a-c) next to a
# real commander program: its `options: {` parameter type and
# `process.env.CACHE_TTL` read must not land on the endpoint as a flag/env.
cache_fp_endpoints = [
  build.call("cli://cachefpdemo", [
    Param.new("verbose", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_cache_fp/", {
  :techs     => 1,
  :endpoints => cache_fp_endpoints.size,
}, cache_fp_endpoints).perform_tests

# --- test trees and type tests are not shipped CLIs --------------------------
# test/, tests/fixtures/ and a `.test-d.ts` type test each program commander;
# only the real top-level cli.js is the CLI surface.
test_dirs_endpoints = [
  build.call("cli://testdirsdemo", [
    Param.new("verbose", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_test_dirs/", {
  :techs     => 1,
  :endpoints => test_dirs_endpoints.size,
}, test_dirs_endpoints).perform_tests

# FunctionalTester only checks that expected params are present, so the
# absence of the decoys' params is asserted here.
describe "js_cli false-positive guards", tags: "functional" do
  it "does not harvest the caching module's options bag or env read" do
    tester = FunctionalTester.new("fixtures/javascript/cli_cache_fp/", {:techs => 1}, [] of Endpoint)
    endpoint = tester.endpoints.find { |ep| ep.url == "cli://cachefpdemo" }
    endpoint.should_not be_nil
    if endpoint
      endpoint.params.count { |p| {"cacheName", "wait", "CACHE_TTL"}.includes?(p.name) }.should eq(0)
    end
  end

  it "does not attach the .test-d.ts type test's flag to the real CLI" do
    tester = FunctionalTester.new("fixtures/javascript/cli_test_dirs/", {:techs => 1}, [] of Endpoint)
    endpoint = tester.endpoints.find { |ep| ep.url == "cli://testdirsdemo" }
    endpoint.should_not be_nil
    if endpoint
      endpoint.params.count { |p| p.name == "type-test-only" }.should eq(0)
    end
  end
end
