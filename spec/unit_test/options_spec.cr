require "../spec_helper"
require "../../src/tagger/tagger"
require "../../src/techs/techs"
require "../../src/options.cr"

# Runs `run_options_parser` against a temporary `--config-file` plus the given
# CLI arguments, so a spec can pin the config-vs-CLI precedence of one flag.
# ARGV and the temp file are restored/removed either way.
private def with_config_argv(config_body : String, args : Array(String), &)
  config_path = File.tempname("noir-precedence-", ".yaml")
  File.write(config_path, config_body)
  original_argv = ARGV.dup

  ARGV.clear
  ARGV.concat(["-b", "./app", "--config-file", config_path] + args)
  begin
    yield run_options_parser
  ensure
    ARGV.clear
    ARGV.concat(original_argv)
    File.delete?(config_path)
  end
end

describe "default_options" do
  it "init" do
    noir_options = create_test_options
    noir_options["format"].should eq("plain")
  end

  it "has base as an empty array" do
    noir_options = create_test_options
    noir_options["base"].as_a.should be_empty
  end

  it "has default native tool-calling allowlist" do
    noir_options = create_test_options
    noir_options["ai_native_tools_allowlist"].to_s.should eq("openai,xai,github")
  end

  it "has ai_context disabled by default" do
    noir_options = create_test_options
    noir_options["ai_context"].should be_false
  end

  it "has loading spinners enabled by default" do
    noir_options = create_test_options
    noir_options["no_spinner"].should be_false
  end

  it "has strict mode disabled by default" do
    noir_options = create_test_options
    noir_options["strict"].should be_false
  end

  # Concurrency is auto-scaled to the host's CPU count, clamped to the
  # [4, 32] window. The exact value depends on the box the suite runs
  # on, so the spec asserts the window rather than a literal.
  it "auto-scales concurrency to the host CPU count within a safe window" do
    noir_options = create_test_options
    value = noir_options["concurrency"].to_s.to_i
    value.should be >= 4
    value.should be <= 32
    expected = System.cpu_count.clamp(4, 32)
    value.should eq(expected)
  end
end

describe "run_options_parser" do
  # POSIX `--`: everything after it is a positional, never a flag. Crystal's
  # OptionParser drops the marker and leaves the tail in place, which erased
  # the boundary — the positional loop then skipped every leftover starting
  # with `-`, so `noir scan -- -old-api` scanned nothing at all and
  # `noir scan -- ./app -f json` promoted `json` to a base path.
  it "treats every token after -- as a base path, flag-shaped included" do
    original_argv = ARGV.dup

    ARGV.clear
    ARGV.concat(["--", "./app", "-f", "json"])

    begin
      noir_options = run_options_parser()
      # `normalize_base` drops the leading `./`, as it does for any positional.
      noir_options["base"].as_a.map(&.to_s).should eq(["app", "-f", "json"])
      # `-f` after the marker is a path, so the format stays at its default.
      noir_options["format"].to_s.should eq("plain")
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "still parses the flags typed before --" do
    original_argv = ARGV.dup

    ARGV.clear
    ARGV.concat(["-f", "json", "--no-log", "--", "-dash-dir"])

    begin
      noir_options = run_options_parser()
      noir_options["format"].to_s.should eq("json")
      noir_options["nolog"].should be_true
      noir_options["base"].as_a.map(&.to_s).should eq(["-dash-dir"])
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "supports --no-spinner" do
    original_argv = ARGV.dup

    ARGV.clear
    ARGV.concat(["--no-spinner"])

    begin
      noir_options = run_options_parser()
      noir_options["no_spinner"].should be_true
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "supports --strict" do
    original_argv = ARGV.dup

    ARGV.clear
    ARGV.concat(["--strict"])

    begin
      noir_options = run_options_parser()
      noir_options["strict"].should be_true
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "supports multiple -b flags" do
    # Save original ARGV
    original_argv = ARGV.dup

    # Test with multiple -b flags
    ARGV.clear
    ARGV.concat(["-b", "./app1", "-b", "./app2", "-b", "./app3"])

    begin
      noir_options = run_options_parser()
      noir_options["base"].as_a.size.should eq(3)
      # Base paths are normalized at parse time (the leading "./" is
      # dropped) so the same tree always reports the same code_path.
      noir_options["base"].as_a[0].to_s.should eq("app1")
      noir_options["base"].as_a[1].to_s.should eq("app2")
      noir_options["base"].as_a[2].to_s.should eq("app3")
    ensure
      # Restore original ARGV
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "supports single -b flag" do
    # Save original ARGV
    original_argv = ARGV.dup

    # Test with single -b flag
    ARGV.clear
    ARGV.concat(["-b", "./single_app"])

    begin
      noir_options = run_options_parser()
      noir_options["base"].as_a.size.should eq(1)
      noir_options["base"].as_a[0].to_s.should eq("single_app")
    ensure
      # Restore original ARGV
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "supports --ai-agent flag" do
    original_argv = ARGV.dup

    ARGV.clear
    ARGV.concat(["-b", "./single_app", "--ai-agent"])

    begin
      noir_options = run_options_parser()
      noir_options["ai_agent"].should be_true
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "supports --ai-context flag" do
    original_argv = ARGV.dup

    ARGV.clear
    ARGV.concat(["-b", "./single_app", "--ai-context"])

    begin
      noir_options = run_options_parser()
      noir_options["ai_context"].should be_true
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "supports --ai-native-tools-allowlist flag" do
    original_argv = ARGV.dup

    ARGV.clear
    ARGV.concat(["-b", "./single_app", "--ai-native-tools-allowlist", "openai,github"])

    begin
      noir_options = run_options_parser()
      noir_options["ai_native_tools_allowlist"].to_s.should eq("openai,github")
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "supports --ai-agent-max-steps flag" do
    original_argv = ARGV.dup

    ARGV.clear
    ARGV.concat(["-b", "./single_app", "--ai-agent-max-steps", "10"])

    begin
      noir_options = run_options_parser()
      noir_options["ai_agent_max_steps"].as_i.should eq(10)
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  # ---------- v1 flag-consolidation surface (Phase 6) ----------

  it "supports positional path arguments (v1 scan idiom)" do
    original_argv = ARGV.dup
    ARGV.clear
    ARGV.concat(["./app", "./api"])

    begin
      noir_options = run_options_parser()
      base = noir_options["base"].as_a.map(&.to_s)
      base.should eq(["app", "api"])
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "mixes positional paths with repeated -b" do
    original_argv = ARGV.dup
    ARGV.clear
    ARGV.concat(["-b", "./app1", "./app2", "-b", "./app3"])

    begin
      noir_options = run_options_parser()
      noir_options["base"].as_a.map(&.to_s).should eq(["app1", "app3", "app2"])
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "--include path,techs sets the matching include_* booleans" do
    original_argv = ARGV.dup
    ARGV.clear
    ARGV.concat(["-b", "./app", "--include", "path,techs"])

    begin
      noir_options = run_options_parser()
      noir_options["include_path"].should be_true
      noir_options["include_techs"].should be_true
      noir_options["include_callee"].should be_false
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "--include callee enables include_callee only" do
    original_argv = ARGV.dup
    ARGV.clear
    ARGV.concat(["-b", "./app", "--include", "callee"])

    begin
      noir_options = run_options_parser()
      noir_options["include_callee"].should be_true
      noir_options["include_path"].should be_false
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "--pvalue TYPE=VAL routes into the matching set_pvalue_* slot" do
    original_argv = ARGV.dup
    ARGV.clear
    ARGV.concat(["-b", "./app", "--pvalue", "query=FOO", "--pvalue", "header=BAR"])

    begin
      noir_options = run_options_parser()
      noir_options["set_pvalue_query"].as_a.map(&.to_s).should eq(["FOO"])
      noir_options["set_pvalue_header"].as_a.map(&.to_s).should eq(["BAR"])
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "--pvalue without a TYPE prefix routes into the global set_pvalue array" do
    original_argv = ARGV.dup
    ARGV.clear
    ARGV.concat(["-b", "./app", "--pvalue", "BLAH"])

    begin
      noir_options = run_options_parser()
      noir_options["set_pvalue"].as_a.map(&.to_s).should eq(["BLAH"])
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "bare --ai-context enables AI context with no feature filter" do
    original_argv = ARGV.dup
    ARGV.clear
    ARGV.concat(["-b", "./app", "--ai-context"])

    begin
      noir_options = run_options_parser()
      noir_options["ai_context"].should be_true
      noir_options["ai_context_features"].to_s.should eq("")
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "--ai-context guards,sinks stores the feature filter" do
    original_argv = ARGV.dup
    ARGV.clear
    ARGV.concat(["-b", "./app", "--ai-context", "guards,sinks"])

    begin
      noir_options = run_options_parser()
      noir_options["ai_context"].should be_true
      noir_options["ai_context_features"].to_s.should eq("guards,sinks")
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "--ai-context followed by a path leaves the path as positional" do
    original_argv = ARGV.dup
    ARGV.clear
    ARGV.concat(["--ai-context", "./app"])

    begin
      noir_options = run_options_parser()
      noir_options["ai_context"].should be_true
      noir_options["ai_context_features"].to_s.should eq("")
      noir_options["base"].as_a.map(&.to_s).should eq(["app"])
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  # The config file is read before OptionParser runs, so `--ai-context=all`
  # and the bare flag used to `return` before writing `ai_context_features` —
  # leaving a config-file narrowing in place. Asking for every bucket on the
  # command line then produced *fewer* buckets than asking for one.
  ["all", ""].each do |spec|
    flag = spec.empty? ? "--ai-context" : "--ai-context=all"

    it "#{flag} resets a config-file ai_context_features to every bucket" do
      original_argv = ARGV.dup
      config_path = File.tempname("noir-ai-context", ".yaml")
      File.write(config_path, "ai_context_features: \"guards\"\n")
      ARGV.clear
      ARGV.concat(["-b", "./app", "--config-file", config_path, flag])

      begin
        noir_options = run_options_parser()
        noir_options["ai_context"].should be_true
        noir_options["ai_context_features"].to_s.should eq("")
      ensure
        File.delete?(config_path)
        ARGV.clear
        ARGV.concat(original_argv)
      end
    end
  end

  it "--ai-context=signals overrides a config-file ai_context_features" do
    original_argv = ARGV.dup
    config_path = File.tempname("noir-ai-context", ".yaml")
    File.write(config_path, "ai_context_features: \"guards\"\n")
    ARGV.clear
    ARGV.concat(["-b", "./app", "--config-file", config_path, "--ai-context=signals"])

    begin
      noir_options = run_options_parser()
      noir_options["ai_context_features"].to_s.should eq("signals")
    ensure
      File.delete?(config_path)
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "--ai-context=callee accepts the explicit-equals form" do
    original_argv = ARGV.dup
    ARGV.clear
    ARGV.concat(["-b", "./app", "--ai-context=callee"])

    begin
      noir_options = run_options_parser()
      noir_options["ai_context"].should be_true
      noir_options["ai_context_features"].to_s.should eq("callee")
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  it "normalize_ai_context_flag routes a multi-token typo to --ai-context=... instead of a stray path" do
    # A comma-joined multi-word token essentially never collides with a real
    # directory name, so any multi-token comma list -- typo'd feature names
    # included -- is folded into `--ai-context=...` and left for
    # apply_ai_context's own vocabulary check to reject with a precise
    # "unknown feature" error, instead of silently being scanned as a bogus
    # base path ("Base path does not exist: bogus,guards").
    Noir::OptionsParsing.normalize_ai_context_flag(["--ai-context", "bogus,guards"]).should eq(["--ai-context=bogus,guards"])
    Noir::OptionsParsing.normalize_ai_context_flag(["--ai-context", "guards,sink"]).should eq(["--ai-context=guards,sink"])
  end

  it "normalize_ai_context_flag still treats a single unrecognized word as a positional path" do
    # A bare single word is genuinely ambiguous with a real one-word
    # directory name (`noir scan --ai-context myapp`), so it's left alone
    # rather than folded in as a feature-list value.
    Noir::OptionsParsing.normalize_ai_context_flag(["--ai-context", "myapp"]).should eq(["--ai-context=", "myapp"])
  end

  it "legacy --set-pvalue-query alias still appends to set_pvalue_query" do
    original_argv = ARGV.dup
    ARGV.clear
    ARGV.concat(["-b", "./app", "--set-pvalue-query", "OLD"])

    begin
      noir_options = run_options_parser()
      noir_options["set_pvalue_query"].as_a.map(&.to_s).should eq(["OLD"])
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end

  # `append_to_csv_option`'s own comment states the rule — "First CLI
  # occurrence of this flag replaces any config-file value outright (CLI wins
  # over config, not `config,cli`)" — but `reset_seen:` was passed at exactly
  # one call site. Every other CSV flag concatenated onto the config value.
  # For `--only-techs` that *inverted* the flag: the CLI widened the
  # restriction instead of replacing it, and there was no way to override a
  # config-file `only_techs` from the command line at all.
  #
  # The four cases below are the whole contract: the reset is per-flag and
  # fires once, on the transition from config to CLI. A second occurrence of
  # the same flag on one command line must still accumulate.
  describe "CSV flags override the config file rather than appending to it" do
    csv_cases = [
      {flag: "--exclude-codes", key: "exclude_codes", config: "404", first: "500", second: "418"},
      {flag: "--exclude-path", key: "exclude_path", config: "*.md", first: "*.js", second: "*.ts"},
      {flag: "--use-taggers", key: "use_taggers", config: "cors", first: "oauth", second: "hunt"},
      {flag: "-t", key: "techs", config: "ruby_rails", first: "python_flask", second: "php_pure"},
      {flag: "--only-techs", key: "only_techs", config: "ruby_rails", first: "python_flask", second: "php_pure"},
      {flag: "--exclude-techs", key: "exclude_techs", config: "ruby_rails", first: "python_flask", second: "php_pure"},
    ]

    csv_cases.each do |c|
      it "#{c[:flag]}: config-only value is kept when the flag is absent" do
        with_config_argv("#{c[:key]}: \"#{c[:config]}\"\n", [] of String) do |options|
          options[c[:key]].to_s.should eq(c[:config])
        end
      end

      it "#{c[:flag]}: one CLI occurrence replaces the config value" do
        with_config_argv("#{c[:key]}: \"#{c[:config]}\"\n", [c[:flag], c[:first]]) do |options|
          options[c[:key]].to_s.should eq(c[:first])
        end
      end

      it "#{c[:flag]}: two CLI occurrences accumulate with each other, not with the config" do
        args = [c[:flag], c[:first], c[:flag], c[:second]]
        with_config_argv("#{c[:key]}: \"#{c[:config]}\"\n", args) do |options|
          options[c[:key]].to_s.should eq("#{c[:first]},#{c[:second]}")
        end
      end

      it "#{c[:flag]}: repeated CLI flags still accumulate with no config file" do
        original_argv = ARGV.dup
        ARGV.clear
        ARGV.concat(["-b", "./app", c[:flag], c[:first], c[:flag], c[:second]])
        begin
          run_options_parser[c[:key]].to_s.should eq("#{c[:first]},#{c[:second]}")
        ensure
          ARGV.clear
          ARGV.concat(original_argv)
        end
      end
    end

    # The reset is keyed per flag, so one flag's first occurrence must not
    # clear a different flag's config value.
    it "resets only the flag that was actually passed" do
      body = "only_techs: \"ruby_rails\"\nexclude_path: \"*.md\"\n"
      with_config_argv(body, ["--only-techs", "python_flask"]) do |options|
        options["only_techs"].to_s.should eq("python_flask")
        options["exclude_path"].to_s.should eq("*.md")
      end
    end
  end

  # In v0 these were real `parser.on "--set-pvalue VALUE"` entries, so
  # Crystal's OptionParser accepted both spellings. The v1 hand-rolled
  # extractor only matched the bare token, so the `=` form fell through to
  # `invalid_option` and hard-failed — while
  # `Noir::CLI::Legacy.translate_flag_aliases` *does* handle `=` for the
  # probe aliases, leaving the two legacy layers disagreeing.
  describe "legacy --set-pvalue= (equals form)" do
    it "accepts the = form for every LEGACY_PVALUE_TARGETS entry" do
      Noir::OptionsParsing::LEGACY_PVALUE_TARGETS.each do |flag, key|
        opts = create_test_options
        remaining = Noir::OptionsParsing.extract_legacy_aliases(["#{flag}=EQ_VALUE"], opts)
        remaining.should be_empty
        opts[key].as_a.map(&.to_s).should eq(["EQ_VALUE"])
      end
    end

    it "splits on the first = only, so a VALUE containing = survives" do
      opts = create_test_options
      Noir::OptionsParsing.extract_legacy_aliases(["--set-pvalue-query=key=val"], opts)
      opts["set_pvalue_query"].as_a.map(&.to_s).should eq(["key=val"])
    end

    it "mixes with the bare form and accumulates" do
      opts = create_test_options
      Noir::OptionsParsing.extract_legacy_aliases(
        ["--set-pvalue", "BARE", "--set-pvalue=EQ"],
        opts,
      )
      opts["set_pvalue"].as_a.map(&.to_s).should eq(["BARE", "EQ"])
    end

    it "leaves an unrelated = token for OptionParser" do
      opts = create_test_options
      remaining = Noir::OptionsParsing.extract_legacy_aliases(["--format=json"], opts)
      remaining.should eq(["--format=json"])
    end

    it "reaches noir_options through the full parser" do
      original_argv = ARGV.dup
      ARGV.clear
      ARGV.concat(["-b", "./app", "--set-pvalue=abc"])
      begin
        run_options_parser["set_pvalue"].as_a.map(&.to_s).should eq(["abc"])
      ensure
        ARGV.clear
        ARGV.concat(original_argv)
      end
    end
  end

  it "legacy --include-path alias still flips include_path" do
    original_argv = ARGV.dup
    ARGV.clear
    ARGV.concat(["-b", "./app", "--include-path"])

    begin
      noir_options = run_options_parser()
      noir_options["include_path"].should be_true
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end
  end
end

# extract_legacy_aliases is the pre-OptionParser rewrite that hides v0
# spellings (--include-*, --set-pvalue*) from `noir scan -h` while
# keeping every v0 script byte-identical. Walk every mapping so a
# future refactor doesn't quietly drop one of the seven pvalue slots
# or three include flags.
describe "extract_legacy_aliases" do
  it "maps every legacy --set-pvalue-* flag to its v1 storage key" do
    legacy_to_key = {
      "--set-pvalue"        => "set_pvalue",
      "--set-pvalue-header" => "set_pvalue_header",
      "--set-pvalue-cookie" => "set_pvalue_cookie",
      "--set-pvalue-query"  => "set_pvalue_query",
      "--set-pvalue-form"   => "set_pvalue_form",
      "--set-pvalue-json"   => "set_pvalue_json",
      "--set-pvalue-path"   => "set_pvalue_path",
    }

    legacy_to_key.each do |flag, key|
      opts = create_test_options
      args = [flag, "LEGACY_VALUE"]
      remaining = Noir::OptionsParsing.extract_legacy_aliases(args, opts)
      remaining.should be_empty
      opts[key].as_a.map(&.to_s).should eq(["LEGACY_VALUE"])
    end
  end

  it "maps every legacy --include-* flag to its include_* boolean" do
    legacy_to_key = {
      "--include-path"   => "include_path",
      "--include-techs"  => "include_techs",
      "--include-callee" => "include_callee",
    }

    legacy_to_key.each do |flag, key|
      opts = create_test_options
      remaining = Noir::OptionsParsing.extract_legacy_aliases([flag], opts)
      remaining.should be_empty
      opts[key].should be_true
    end
  end

  it "leaves unrelated tokens in place for OptionParser" do
    opts = create_test_options
    remaining = Noir::OptionsParsing.extract_legacy_aliases(["-b", "./app", "--passive", "--include", "path"], opts)
    remaining.should eq(["-b", "./app", "--passive", "--include", "path"])
  end

  it "supports repeating the same legacy flag (each occurrence appends)" do
    opts = create_test_options
    remaining = Noir::OptionsParsing.extract_legacy_aliases(
      ["--set-pvalue-query", "A", "--set-pvalue-query", "B"],
      opts,
    )
    remaining.should be_empty
    opts["set_pvalue_query"].as_a.map(&.to_s).should eq(["A", "B"])
  end

  it "mixes legacy and v1-native tokens cleanly" do
    opts = create_test_options
    remaining = Noir::OptionsParsing.extract_legacy_aliases(
      ["--include-callee", "-b", "./app", "--set-pvalue-header", "X=1"],
      opts,
    )
    remaining.should eq(["-b", "./app"])
    opts["include_callee"].should be_true
    opts["set_pvalue_header"].as_a.map(&.to_s).should eq(["X=1"])
  end
end
