require "../spec_helper"
require "../../src/tagger/tagger"
require "../../src/techs/techs"
require "../../src/options.cr"

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

  it "supports multiple -b flags" do
    # Save original ARGV
    original_argv = ARGV.dup

    # Test with multiple -b flags
    ARGV.clear
    ARGV.concat(["-b", "./app1", "-b", "./app2", "-b", "./app3"])

    begin
      noir_options = run_options_parser()
      noir_options["base"].as_a.size.should eq(3)
      noir_options["base"].as_a[0].to_s.should eq("./app1")
      noir_options["base"].as_a[1].to_s.should eq("./app2")
      noir_options["base"].as_a[2].to_s.should eq("./app3")
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
      noir_options["base"].as_a[0].to_s.should eq("./single_app")
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
      base.should eq(["./app", "./api"])
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
      noir_options["base"].as_a.map(&.to_s).should eq(["./app1", "./app3", "./app2"])
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
      noir_options["base"].as_a.map(&.to_s).should eq(["./app"])
    ensure
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
      remaining = extract_legacy_aliases(args, opts)
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
      remaining = extract_legacy_aliases([flag], opts)
      remaining.should be_empty
      opts[key].should be_true
    end
  end

  it "leaves unrelated tokens in place for OptionParser" do
    opts = create_test_options
    remaining = extract_legacy_aliases(["-b", "./app", "--passive", "--include", "path"], opts)
    remaining.should eq(["-b", "./app", "--passive", "--include", "path"])
  end

  it "supports repeating the same legacy flag (each occurrence appends)" do
    opts = create_test_options
    remaining = extract_legacy_aliases(
      ["--set-pvalue-query", "A", "--set-pvalue-query", "B"],
      opts,
    )
    remaining.should be_empty
    opts["set_pvalue_query"].as_a.map(&.to_s).should eq(["A", "B"])
  end

  it "mixes legacy and v1-native tokens cleanly" do
    opts = create_test_options
    remaining = extract_legacy_aliases(
      ["--include-callee", "-b", "./app", "--set-pvalue-header", "X=1"],
      opts,
    )
    remaining.should eq(["-b", "./app"])
    opts["include_callee"].should be_true
    opts["set_pvalue_header"].as_a.map(&.to_s).should eq(["X=1"])
  end
end
