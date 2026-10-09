require "../../spec_helper"
require "../../../src/models/noir"

private def cli_params(fixture : String) : Array(String)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(File.expand_path("../../functional_test/fixtures/#{fixture}", __DIR__))])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints.select(&.method.==("CLI")).flat_map(&.params.map { |p| "#{p.name}:#{p.param_type}" }).sort!
ensure
  CodeLocator.instance.reset_files
end

# The CLI analyzers matched raw lines, so a commented-out option, a block
# comment / POD / `=begin` doc block and an env *write* all surfaced as input.
describe "CLI analyzers and non-code" do
  it "ruby: reads neither comments, =begin blocks nor ENV writes" do
    cli_params("ruby/cli_comments").should eq(["DEFAULTED:env", "READ_ME:env", "real:flag"])
  end

  it "perl: reads neither comments, POD, __END__ nor %ENV writes" do
    cli_params("perl/cli_comments").should eq(["READ_ME:env", "real:flag"])
  end

  it "lua: reads neither -- nor --[[ ]] comments" do
    cli_params("lua/cli_comments").should eq(["READ_ME:env", "real:flag"])
  end

  it "php: reads neither //, # nor /* */ comments, nor $_ENV writes" do
    cli_params("php/cli_comments").should eq(["AFTER_STRING:env", "READ_ME:env", "real:flag", "v:flag"])
  end
end
