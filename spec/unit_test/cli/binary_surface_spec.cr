require "../../spec_helper"
require "json"

# End-to-end specs for the CLI front door, driven through the *built
# binary*.
#
# Everything else in this directory tests a pure parser helper, and
# `spec/functional_test`'s `FunctionalTester` drives `detect`/`analyze`
# directly without ever going through the CLI — which is exactly the gap
# the router/subcommand bugs fixed here lived in. Argv handling, exit
# codes, and the stdout/stderr split can only be pinned by running the
# real program, so these examples assert all three separately.
private REPO_ROOT = File.expand_path(File.join(__DIR__, "..", "..", ".."))
private BINARY    = File.join(REPO_ROOT, "bin", "noir")
private FIXTURE   = File.join(REPO_ROOT, "spec", "functional_test", "fixtures", "ruby", "sinatra")

private record CliRun, stdout : String, stderr : String, exit_code : Int32

private def run_noir(args : Array(String)) : CliRun
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run(BINARY, args: args, output: stdout, error: stderr)
  CliRun.new(stdout: stdout.to_s, stderr: stderr.to_s, exit_code: status.exit_code)
end

# `bin/noir` is produced by a separate CI job from the one that runs the
# specs, so it is routinely absent here — and a stale binary would fail
# these examples for a reason that has nothing to do with the code under
# test. Both cases skip instead; `shards build` makes them run.
private def binary_ready? : Bool
  return false unless File.exists?(BINARY)
  built_at = File.info(BINARY).modification_time
  Dir.glob(File.join(REPO_ROOT, "src", "**", "*.cr")).none? do |source|
    File.info(source).modification_time > built_at
  end
end

describe "noir CLI surface (built binary)" do
  unless binary_ready?
    pending "needs an up-to-date bin/noir — run `shards build` to exercise these"
    next
  end

  describe "terminal-flag rewriting" do
    it "leaves a subcommand's own -v alone" do
      # `noir rules update -v` used to print the version and exit 0 —
      # `-v` was rewritten to the `version` subcommand before the router
      # ever saw the verb, so the rules were never updated while the
      # documented `noir rules update && noir scan . -P` precondition
      # reported success. `rules path` is the network-free stand-in for
      # the same argv shape.
      result = run_noir(["rules", "path", "-v"])
      result.stdout.should contain("passive_rules")
      result.stdout.strip.should_not match(/\A\d+\.\d+\.\d+\z/)
      result.exit_code.should eq(0)
    end

    it "still routes the v0 (verb-less) global flags to `version`" do
      %w[-v -V --version].each do |flag|
        result = run_noir([flag])
        result.stdout.strip.should match(/\A\d+\.\d+\.\d+/)
        result.stderr.should be_empty
        result.exit_code.should eq(0)
      end
    end

    it "keeps `noir version -v` working" do
      result = run_noir(["version", "-v"])
      result.stdout.strip.should match(/\A\d+\.\d+\.\d+/)
      result.exit_code.should eq(0)
    end

    it "keeps the v0 terminal flags working after other v0 flags" do
      result = run_noir(["-b", FIXTURE, "--build-info"])
      result.stdout.should contain("Crystal:")
      result.exit_code.should eq(0)
    end
  end
end
