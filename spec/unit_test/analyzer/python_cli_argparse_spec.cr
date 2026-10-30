require "../../spec_helper"
require "../../../src/models/noir"

private def argparse_commands(fixture : String) : Hash(String, Array(String))
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(File.expand_path("../../functional_test/fixtures/#{fixture}", __DIR__))])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints.select(&.method.==("CLI")).to_h do |ep|
    {ep.url, ep.params.map { |p| "#{p.name}:#{p.param_type}" }.sort!}
  end
ensure
  CodeLocator.instance.reset_files
end

# FunctionalTester only checks that expected params exist, so the params that
# used to land on the wrong command are pinned here (issue #3274).
describe "Analyzer::Python::Cli argparse subcommands" do
  commands = argparse_commands("python/cli_argparse_subcommands")

  it "attributes a reused subparser variable to its most recent add_parser" do
    commands["cli://itemctl/list"]?.should eq(["limit:flag"])
    commands["cli://itemctl/get"]?.should eq(["item_id:argument"])
    commands["cli://itemctl/delete"]?.should eq(["force:flag", "item_id:argument"])
  end

  it "copies parents=[common] arguments onto each subcommand, not the root" do
    commands.has_key?("cli://jobctl").should be_false
    commands["cli://jobctl/run"]?.should eq(["job_id:argument", "region:flag"])
    commands["cli://jobctl/stop"]?.should eq(["job_id:argument", "region:flag"])
  end

  it "reads an add_parser( call whose name sits on the next line" do
    commands["cli://userctl/show"]?.should eq(["user_id:argument"])
    commands["cli://userctl/remove"]?.should eq(["user_id:argument", "yes:flag"])
  end

  it "joins calls string- and comment-aware, so a stray ( keeps later subcommands" do
    commands["cli://strayctl/alpha"]?.should eq(["aa:flag"])
    commands["cli://strayctl/gamma"]?.should eq(["cc:flag"])
    commands["cli://clickparenctl/serve"]?.should eq(["port:flag"])
    commands["cli://clickparenctl/stop"]?.should eq(["force:flag"])
  end

  it "attributes argument-group arguments to the parser the group came from" do
    commands["cli://strayctl/beta"]?.should eq(["bb:flag", "json:flag", "quiet:flag"])
  end

  it "keeps the row of a parser that is run, even when it is also a parent" do
    commands["cli://selfparentctl"]?.should eq(["config:flag"])
    commands["cli://selfparentctl/run"]?.should eq(["config:flag", "job:argument"])
  end

  it "leaves a parent's arguments on the root when no recognised parser consumes it" do
    commands["cli://loopctl"]?.should eq(["region:flag"])
  end

  it "starts no join from a docstring line, in argparse or click" do
    commands["cli://docctl/alpha"]?.should eq(["aa:flag"])
    commands["cli://clickparenctl/serve"]?.should eq(["port:flag"])
  end

  it "binds a group to the parser its owner held, and reads a chained group" do
    commands["cli://docctl/beta"]?.should eq(["bb:flag", "late-beta:flag"])
    commands["cli://docctl/gamma"]?.should eq(["inline:flag"])
  end

  it "does not read parse_args() in a string or comment as running a template" do
    commands.has_key?("cli://docctl").should be_false
    commands["cli://docctl/run"]?.should eq(["job:argument", "region:flag"])
  end
end
