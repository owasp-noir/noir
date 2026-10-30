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

  it "go: does not report go-flags struct tags in a library package that parses a caller string" do
    dir = File.tempname("go_flags_lib")
    Dir.mkdir_p(File.join(dir, "pkg", "cmdline"))
    File.write(File.join(dir, "go.mod"), "module example.com/lib\n\ngo 1.21\n\nrequire github.com/jessevdk/go-flags v1.5.0\n")
    File.write(File.join(dir, "pkg", "cmdline", "parse.go"), <<-GO)
      package cmdline

      import (
        "strings"
        "github.com/jessevdk/go-flags"
      )

      type Options struct {
        Data    string `short:"d" long:"data"`
        Request string `short:"X" long:"request"`
      }

      func Parse(line string) (*Options, error) {
        var opts Options
        _, err := flags.NewParser(&opts, flags.Default).ParseArgs(strings.Fields(line))
        return &opts, err
      }
      GO

    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(dir)])
    runner = NoirRunner.new(options)
    runner.detect
    runner.analyze
    runner.endpoints.select(&.method.==("CLI")).should be_empty

    # The same struct in a module that builds a binary is that binary's argv.
    Dir.mkdir_p(File.join(dir, "cmd", "lib"))
    File.write(File.join(dir, "cmd", "lib", "main.go"), "package main\n\nfunc main() {}\n")
    CodeLocator.instance.reset_files
    runner = NoirRunner.new(options)
    runner.detect
    runner.analyze
    runner.endpoints.select(&.method.==("CLI")).flat_map(&.params.map(&.name)).sort!.should eq(["data", "request"])
  ensure
    CodeLocator.instance.reset_files
    FileUtils.rm_rf(dir) if dir && Dir.exists?(dir)
  end
end
