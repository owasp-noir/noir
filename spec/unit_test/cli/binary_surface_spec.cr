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

  describe "global flags before the verb" do
    # `noir help` documents `--no-color` / `--no-spinner` as working on
    # "every command's output", but the router only ever tested `argv[0]`
    # for a verb — so a global flag typed first pushed the whole invocation
    # down the v0 bare-flag path and every one of these died with
    # `Base path does not exist: <verb>`.
    it "dispatches a verb that follows a leading global flag" do
      result = run_noir(["--no-color", "version"])
      result.stdout.strip.should match(/\A\d+\.\d+\.\d+/)
      result.exit_code.should eq(0)
    end

    it "accepts several leading global flags at once" do
      result = run_noir(["--no-color", "--no-spinner", "list", "formats"])
      result.stdout.should contain("json")
      result.exit_code.should eq(0)
    end

    it "still reaches scan, with the flag applied" do
      result = run_noir(["--no-color", "scan", FIXTURE, "-f", "json", "--no-log"])
      result.exit_code.should eq(0)
      result.stdout.should_not contain("\e[")
      JSON.parse(result.stdout)["endpoints"].as_a.empty?.should be_false
    end

    it "shows the top-level overview for `--no-color -h`, not scan's flag dump" do
      result = run_noir(["--no-color", "-h"])
      result.stdout.should contain("COMMANDS:")
      result.stdout.should_not contain("--passive-scan-severity")
      result.exit_code.should eq(0)
    end

    it "does not let the v0 rewrite hijack a subcommand's own -v" do
      # Same exposure as `noir rules path -v` above, reached through the
      # leading-global-flag path: `subcommand_invocation?` looked at
      # `argv[0]`, saw `--no-color`, and let `-v => version` win.
      result = run_noir(["--no-color", "rules", "path", "-v"])
      result.stdout.should contain("passive_rules")
      result.stdout.strip.should_not match(/\A\d+\.\d+\.\d+\z/)
      result.exit_code.should eq(0)
    end

    it "keeps a globals-only argv on the v0 scan path" do
      result = run_noir(["--no-color"])
      result.stderr.should contain("No path to scan was given")
      result.exit_code.should eq(1)
    end
  end

  describe "config" do
    it "rejects --config-file with no value instead of using the default file" do
      result = run_noir(["config", "path", "--config-file"])
      result.stdout.should be_empty
      result.stderr.should contain("--config-file requires an argument.")
      result.exit_code.should eq(1)
    end

    it "expands a leading ~ in --config-file" do
      result = run_noir(["config", "path", "--config-file=~/noir-spec-nope.yaml"])
      result.stdout.strip.should eq(File.join(Path.home.to_s, "noir-spec-nope.yaml"))
      result.exit_code.should eq(0)
    end

    it "rejects a surplus positional instead of running a different action" do
      result = run_noir(["config", "path", "init"])
      result.stdout.should be_empty
      result.stderr.should contain("Unexpected argument: init")
      result.exit_code.should eq(1)
    end

    it "rejects an unknown flag" do
      result = run_noir(["config", "show", "--bogus-flag"])
      result.stdout.should be_empty
      result.stderr.should contain("Unknown option: --bogus-flag")
      result.exit_code.should eq(1)
    end
  end

  describe "completion" do
    it "rejects a second shell instead of emitting only the first" do
      result = run_noir(["completion", "zsh", "bash"])
      result.stdout.should be_empty
      result.stderr.should contain("Unexpected argument: bash")
      result.exit_code.should eq(1)
    end

    it "still emits a single requested script on stdout" do
      result = run_noir(["completion", "zsh"])
      result.stdout.should contain("#compdef noir")
      result.stderr.should be_empty
      result.exit_code.should eq(0)
    end
  end

  describe "scan" do
    it "rejects a -u/--url with no host" do
      result = run_noir(["scan", FIXTURE, "-u", "http://", "-f", "json", "--no-log"])
      result.stdout.should be_empty
      result.stderr.should contain("has no host")
      result.exit_code.should eq(1)
    end

    it "rejects a -u/--url whose authority holds whitespace" do
      result = run_noir(["scan", FIXTURE, "-u", "not a url", "-f", "json", "--no-log"])
      result.stdout.should be_empty
      result.stderr.should contain("whitespace or control characters")
      result.exit_code.should eq(1)
    end

    it "rejects an --exclude-path glob that would silently match nothing" do
      {"*.{rb", "{", "", "  "}.each do |pattern|
        result = run_noir(["scan", FIXTURE, "--exclude-path", pattern, "-f", "json", "--no-log"])
        result.stdout.should be_empty
        result.stderr.should contain("--exclude-path")
        result.exit_code.should eq(1)
      end
    end

    it "still fails a CLI-typed --status-codes without a URL" do
      result = run_noir(["scan", FIXTURE, "--status-codes", "-f", "json", "--no-log"])
      result.stdout.should be_empty
      result.stderr.should contain("--status-codes needs a target URL")
      result.exit_code.should eq(1)
    end

    it "warns and carries on when the URL-dependent value came from a config file" do
      # `status_codes:` is a documented config key, so enforcing the URL
      # dependency after the merge made a plain `noir scan ./app` die,
      # blaming a flag the user never typed.
      config = File.tempfile("noir-cli-spec", ".yaml") do |file|
        file.puts "status_codes: true"
      end

      begin
        result = run_noir(["scan", FIXTURE, "--config-file", config.path, "-f", "json", "--no-log"])
        result.stderr.should contain("config key `status_codes`")
        result.exit_code.should eq(0)
        # The warning belongs on stderr — stdout must stay byte-parseable.
        JSON.parse(result.stdout)["endpoints"].as_a.empty?.should be_false
      ensure
        config.delete
      end
    end

    it "treats everything after `--` as a path, flag-shaped or not" do
      # Crystal's OptionParser drops the `--` and leaves the tail in place,
      # which erased the boundary: the positional loop skipped every
      # leftover starting with `-`, so a flag typed after `--` vanished and
      # its value was promoted to a base path.
      result = run_noir(["scan", "--", FIXTURE, "-f", "json"])
      result.stdout.should be_empty
      result.stderr.should contain("Base path does not exist: -f")
      result.exit_code.should eq(1)
    end

    it "scans a directory whose name starts with a dash when given after `--`" do
      dir = File.join(Dir.tempdir, "-noir-dash-#{Random.rand(100_000)}")
      Dir.mkdir_p(dir)
      begin
        result = run_noir(["scan", "-f", "json", "--no-log", "--", dir])
        result.exit_code.should eq(0)
        JSON.parse(result.stdout)["endpoints"].as_a.empty?.should be_true
      ensure
        Dir.delete(dir) if Dir.exists?(dir)
      end
    end

    it "names an empty base path instead of reporting a blank one as missing" do
      result = run_noir(["scan", ""])
      result.stderr.should contain("Base path is empty")
      result.exit_code.should eq(1)
    end

    it "reports a --config-file that is a directory instead of crashing" do
      # `File.exists?` is true for a directory and the `File.read` that
      # followed it sat outside ConfigInitializer's YAML rescue, so this
      # printed a raw Crystal backtrace before CliValidation's one-liner.
      result = run_noir(["scan", FIXTURE, "--config-file", Dir.tempdir, "-f", "json", "--no-log"])
      result.stdout.should be_empty
      result.stderr.should_not contain("Unhandled exception")
      result.stderr.should contain("--config-file is not a file")
      result.exit_code.should eq(1)
    end

    it "leaves a well-formed scan untouched" do
      result = run_noir(["scan", FIXTURE, "-u", "http://localhost:3000", "-f", "json", "--no-log"])
      result.stderr.should be_empty
      result.exit_code.should eq(0)
      urls = JSON.parse(result.stdout)["endpoints"].as_a.map(&.["url"].as_s)
      urls.empty?.should be_false
      urls.all?(&.starts_with?("http://localhost:3000/")).should be_true
    end
  end

  describe "broken pipe" do
    # `noir list techs` writes far more than a pipe buffer holds, so a
    # reader that stops early (`| head`) closes the pipe mid-write. Scan's
    # own stdout writes have been guarded for a while, but the thin
    # subcommands write straight to STDOUT — this painted a full Crystal
    # backtrace over the terminal and exited non-zero.
    it "exits quietly when the reader closes the pipe" do
      log = File.tempname("noir-epipe-", ".log")
      begin
        # The brace group sends both noir's stderr and its exit status to
        # `log`, because `$?` after a pipeline in `sh` belongs to `head`.
        Process.run("/bin/sh", args: [
          "-c", "{ \"$0\" list techs; echo \"rc=$?\" >&2; } 2>\"$1\" | head -1 >/dev/null",
          BINARY, log,
        ])
        captured = File.read(log)
        captured.should_not contain("Unhandled exception")
        captured.should contain("rc=0")
      ensure
        File.delete?(log)
      end
    end
  end
end
