require "../../func_spec.cr"

# A `test` subcommand directory (yargs/oclif/Angular-style
# `src/commands/test/index.ts`) is shipped CLI surface; only the `fixtures/`
# subtree of a tests/ directory is a decoy.
endpoint = Endpoint.new("cli://testsubdemo", "CLI", [
  Param.new("verbose", "", "flag"),
  Param.new("prod", "", "flag"),
  Param.new("watch", "", "flag"),
])
endpoint.protocol = "cli"

FunctionalTester.new("fixtures/javascript/cli_test_subcommand_dir/", {
  :techs     => 1,
  :endpoints => 1,
}, [endpoint]).perform_tests

describe "js_cli test/ subcommand directory", tags: "functional" do
  it "keeps the test subcommand's flag but not the tests/fixtures decoy" do
    tester = FunctionalTester.new("fixtures/javascript/cli_test_subcommand_dir/", {:techs => 1}, [] of Endpoint)
    ep = tester.endpoints.find { |e| e.url == "cli://testsubdemo" }
    ep.should_not be_nil
    if ep
      ep.params.count { |p| p.name == "watch" }.should eq(1)
      ep.params.count { |p| p.name == "only-in-fixtures" }.should eq(0)
    end
  end
end
