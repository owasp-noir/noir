require "../../spec_helper"
require "file_utils"
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
# A second, deliberately different codebase, so `--diff-path` has something
# to report as added/removed rather than an empty diff.
private DIFF_FIXTURE = File.join(REPO_ROOT, "spec", "functional_test", "fixtures", "ruby", "rails")

private record CliRun, stdout : String, stderr : String, exit_code : Int32

# A HAR whose `startedDateTime` and cookie `expires` are not ISO-8601.
# Browsers and capture proxies do emit such files, and the `har` shard reports
# each one through Crystal's *global* `Log` — whose default backend writes to
# STDOUT. So `noir scan ./captures -f json` printed a WARN line *and a full
# Crystal backtrace* ahead of the JSON document, and `| jq .` died with
# `Invalid numeric literal at line 1, column 14`.
#
# Neither the warning nor the shard is Noir's to change, which is the point:
# the fix is the process-entry redirect in `Router.dispatch`
# (`Noir::CLI.route_library_logs_to_stderr!`), so third-party logging cannot
# reach the report stream no matter who does it. Driven through the built
# binary because that redirect is a real-stream property — the spec runner's
# own `Log` is set to `:none`, so nothing in-process can observe it.
private BAD_TIMESTAMP_HAR = <<-HAR
  {
    "log": {
      "version": "1.2",
      "creator": { "name": "spec", "version": "1" },
      "entries": [
        {
          "startedDateTime": "not-a-timestamp",
          "request": {
            "bodySize": 0, "method": "GET",
            "url": "https://www.example.com/api/users",
            "httpVersion": "HTTP/1.1",
            "headers": [{ "name": "Host", "value": "www.example.com" }],
            "cookies": [{ "name": "sid", "value": "abc",
                          "expires": "Wed, 21 Oct 2015 07:28:00 GMT" }],
            "queryString": [{ "name": "page", "value": "1" }],
            "headersSize": -1
          },
          "response": {
            "status": 200, "statusText": "OK", "httpVersion": "HTTP/1.1",
            "headers": [], "cookies": [],
            "content": { "size": 0, "mimeType": "application/json" },
            "redirectURL": "", "headersSize": -1, "bodySize": 0
          },
          "cache": {}, "timings": { "send": 0, "wait": 0, "receive": 0 },
          "time": 0
        }
      ]
    }
  }
  HAR

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
      # `z[b` and `a[b` are the same malformation. The validator used to
      # probe them with `File.match?(pattern, "noir")`, and Crystal's
      # matcher stops at the first literal that does not match its subject:
      # `a[b` reached the unterminated `[` and raised, `z[b` did not and
      # sailed through to exclude nothing at all. Which one a user got
      # depended on the first character of their pattern.
      {"*.{rb", "{", "", "  ", "a[b", "z[b", "[", "src/[a-z"}.each do |pattern|
        result = run_noir(["scan", FIXTURE, "--exclude-path", pattern, "-f", "json", "--no-log"])
        result.stdout.should be_empty
        result.stderr.should contain("--exclude-path")
        result.exit_code.should eq(1)
      end
    end

    # A brace group with a comma in it (`*.{rb,py}`) is not expressible
    # here — the flag splits its value on `,` before a pattern is parsed —
    # so the single-branch form is what these assert.
    it "still accepts the character classes and brace groups that are valid" do
      {"[]]", "[^a-z]*.rb", "src/[a-z]*.go", "*.{rb}", "**/vendor/**"}.each do |pattern|
        result = run_noir(["scan", FIXTURE, "--exclude-path", pattern, "-f", "json", "--no-log"])
        result.stderr.should_not contain("invalid glob pattern")
        result.exit_code.should eq(0)
      end
    end

    # A tech flag given nothing is stored as `""` — indistinguishable, in
    # the options hash, from the flag never being typed. `--only-techs ""`
    # therefore asked to restrict the scan and silently widened it back to
    # every technology, which is what a CI job passing `--only-techs
    # "$TECHS"` gets when `$TECHS` is unset. `--only-techs ,` went the other
    # way: no detector ran, zero endpoints, exit 0, no word about why.
    it "rejects a tech flag that names no technology" do
      {
        {"--only-techs", ""}, {"--only-techs", "  "}, {"--only-techs", ","},
        {"--exclude-techs", ""}, {"--exclude-techs", ",,"},
        {"-t", ""}, {"--techs", " "},
      }.each do |(flag, value)|
        result = run_noir(["scan", FIXTURE, flag, value, "-f", "json", "--no-log"])
        result.stdout.should be_empty
        result.stderr.should contain(flag == "-t" ? "--techs" : flag)
        result.exit_code.should eq(1)
      end

      result = run_noir(["scan", FIXTURE, "--only-techs=", "-f", "json", "--no-log"])
      result.stdout.should be_empty
      result.stderr.should contain("--only-techs")
      result.exit_code.should eq(1)
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

  describe "stdout purity" do
    it "keeps a third-party warning out of the report stream" do
      dir = File.join(Dir.tempdir, "noir-stdout-purity-#{Random.rand(100_000)}")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "capture.har"), BAD_TIMESTAMP_HAR)
        result = run_noir(["scan", dir, "-f", "json", "--no-log"])

        result.exit_code.should eq(0)
        # The whole point: stdout parses, and it is the report.
        JSON.parse(result.stdout)["endpoints"].as_a
          .map(&.["url"].as_s)
          .should contain("https://www.example.com/api/users")
        # ...and the diagnostic is not lost, it moved to the other stream.
        result.stderr.should contain("Unable to parse timestamp")
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  describe "diff mode with a format it cannot render" do
    # Diff mode only implements plain/json/yaml/toml. Any other `-f` falls
    # back to the decorated text diff, and the notice saying so used to go
    # through the progress logger — which `--no-log` silences wholesale.
    # That is exactly backwards: `--no-log -f sarif -o report.sarif` in CI
    # is the run that most needs to hear it, and it was the one run that
    # could not. The warning now takes the same always-visible STDERR path
    # as the other "your flag was ignored" notices.
    it "warns on stderr even under --no-log" do
      result = run_noir(["scan", FIXTURE, "--diff-path", DIFF_FIXTURE,
                         "--no-color", "--no-log", "-f", "sarif"])
      result.stderr.should contain("diff mode does not support -f sarif")
      result.stdout.should_not contain("\"$schema\"")
    end

    it "stays quiet for a format diff mode does implement" do
      result = run_noir(["scan", FIXTURE, "--diff-path", DIFF_FIXTURE,
                         "--no-color", "--no-log", "-f", "json"])
      result.stderr.should_not contain("does not support")
      JSON.parse(result.stdout)["added"].as_a.should_not be_nil
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
