require "../spec_helper"
require "../../src/cli_validation"

describe Noir::CliValidation do
  it "rejects missing base paths" do
    options = create_test_options

    expect_raises(Noir::CliValidation::Error, /No path to scan was given/) do
      Noir::CliValidation.validate_base_paths!(options)
    end
  end

  it "rejects nonexistent base paths" do
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new("/tmp/noir-does-not-exist")])

    expect_raises(Noir::CliValidation::Error, /Base path does not exist/) do
      Noir::CliValidation.validate_base_paths!(options)
    end
  end

  it "names an empty base path rather than reporting a blank one as missing" do
    # `noir scan "$TARGET"` with `TARGET` unset. The entry is present, so
    # the "No path to scan was given" branch above doesn't fire, and the
    # existence check printed `Base path does not exist: ` — a message with
    # nothing after the colon.
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new("")])

    expect_raises(Noir::CliValidation::Error, /Base path is empty/) do
      Noir::CliValidation.validate_base_paths!(options)
    end
  end

  it "rejects invalid output formats" do
    options = create_test_options
    options["format"] = YAML::Any.new("madeup")

    expect_raises(Noir::CliValidation::Error, /Invalid output format 'madeup'/) do
      Noir::CliValidation.validate_output_format!(options)
    end
  end

  it "rejects non-positive concurrency" do
    options = create_test_options
    options["concurrency"] = YAML::Any.new(0)

    expect_raises(Noir::CliValidation::Error, /Invalid concurrency '0'/) do
      Noir::CliValidation.validate_concurrency!(options)
    end
  end

  it "normalizes valid concurrency to an integer" do
    options = create_test_options
    options["concurrency"] = YAML::Any.new("2")

    Noir::CliValidation.validate_concurrency!(options)

    options["concurrency"].as_i.should eq(2)
  end

  it "rejects output paths in missing directories" do
    options = create_test_options
    options["output"] = YAML::Any.new("/tmp/noir-missing-dir/out.txt")

    expect_raises(Noir::CliValidation::Error, /Output directory does not exist/) do
      Noir::CliValidation.validate_output_path!(options)
    end
  end

  it "rejects unknown tagger names" do
    options = create_test_options
    options["use_taggers"] = YAML::Any.new("hunt,madeup")

    expect_raises(Noir::CliValidation::Error, /Unknown tagger/) do
      Noir::CliValidation.validate_tagger_names!(options)
    end
  end

  describe "validate_config_file!" do
    it "passes when no config-file is set" do
      options = create_test_options
      options["config_file"] = YAML::Any.new("")
      Noir::CliValidation.validate_config_file!(options)
    end

    it "rejects missing config-file" do
      options = create_test_options
      options["config_file"] = YAML::Any.new("/tmp/no-such-config-#{Random.rand(1_000_000)}.yaml")
      expect_raises(Noir::CliValidation::Error, /does not exist/) do
        Noir::CliValidation.validate_config_file!(options)
      end
    end

    it "rejects directories passed as --config-file" do
      options = create_test_options
      options["config_file"] = YAML::Any.new("/tmp")
      expect_raises(Noir::CliValidation::Error, /is not a file/) do
        Noir::CliValidation.validate_config_file!(options)
      end
    end

    it "rejects malformed YAML" do
      path = File.tempname("noir-bad-yaml")
      File.write(path, "not valid yaml: :\n  - \"broken\n")
      begin
        options = create_test_options
        options["config_file"] = YAML::Any.new(path)
        expect_raises(Noir::CliValidation::Error, /invalid YAML/) do
          Noir::CliValidation.validate_config_file!(options)
        end
      ensure
        File.delete(path) if File.exists?(path)
      end
    end

    it "rejects YAML whose top-level value is not a mapping" do
      path = File.tempname("noir-list-yaml")
      File.write(path, "- one\n- two\n")
      begin
        options = create_test_options
        options["config_file"] = YAML::Any.new(path)
        expect_raises(Noir::CliValidation::Error, /must be a YAML mapping/) do
          Noir::CliValidation.validate_config_file!(options)
        end
      ensure
        File.delete(path) if File.exists?(path)
      end
    end

    it "accepts an empty file (treated as no overrides)" do
      path = File.tempname("noir-empty-yaml")
      File.write(path, "")
      begin
        options = create_test_options
        options["config_file"] = YAML::Any.new(path)
        Noir::CliValidation.validate_config_file!(options)
      ensure
        File.delete(path) if File.exists?(path)
      end
    end

    it "accepts a valid YAML mapping" do
      path = File.tempname("noir-good-yaml")
      File.write(path, "concurrency: 10\nformat: yaml\n")
      begin
        options = create_test_options
        options["config_file"] = YAML::Any.new(path)
        Noir::CliValidation.validate_config_file!(options)
      ensure
        File.delete(path) if File.exists?(path)
      end
    end
  end

  describe "validate_ai_provider_pair!" do
    it "passes when neither --ai-provider nor --ai-model is set" do
      options = create_test_options
      Noir::CliValidation.validate_ai_provider_pair!(options)
    end

    it "passes when both --ai-provider and --ai-model are set" do
      options = create_test_options
      options["ai_provider"] = YAML::Any.new("openai")
      options["ai_model"] = YAML::Any.new("gpt-4")
      Noir::CliValidation.validate_ai_provider_pair!(options)
    end

    it "passes when --ai-provider is ACP-prefixed and no model is given" do
      # `acp:claude` / `acp:codex` carry their own default model;
      # forcing `--ai-model` here would block a valid invocation.
      options = create_test_options
      options["ai_provider"] = YAML::Any.new("acp:claude")
      Noir::CliValidation.validate_ai_provider_pair!(options)
    end

    it "is case-insensitive on the ACP prefix" do
      options = create_test_options
      options["ai_provider"] = YAML::Any.new("ACP:Codex")
      Noir::CliValidation.validate_ai_provider_pair!(options)
    end

    it "rejects --ai-provider without --ai-model (non-ACP)" do
      options = create_test_options
      options["ai_provider"] = YAML::Any.new("openai")
      expect_raises(Noir::CliValidation::Error, /companion --ai-model/) do
        Noir::CliValidation.validate_ai_provider_pair!(options)
      end
    end

    it "rejects --ai-model without --ai-provider" do
      options = create_test_options
      options["ai_model"] = YAML::Any.new("gpt-4")
      expect_raises(Noir::CliValidation::Error, /companion --ai-provider/) do
        Noir::CliValidation.validate_ai_provider_pair!(options)
      end
    end
  end

  describe "validate_passive_scan_paths!" do
    it "passes when no --passive-scan-path is set" do
      options = create_test_options
      Noir::CliValidation.validate_passive_scan_paths!(options)
    end

    it "rejects a missing directory" do
      options = create_test_options
      options["passive_scan_path"] = YAML::Any.new([
        YAML::Any.new("/tmp/noir-no-such-dir-#{Random.rand(1_000_000)}"),
      ])
      expect_raises(Noir::CliValidation::Error, /does not exist/) do
        Noir::CliValidation.validate_passive_scan_paths!(options)
      end
    end

    it "rejects a path that points at a file, not a directory" do
      # Create a temp file to point at — pre-fix, this would silently
      # load 0 rules because Dir.glob("FILE/**/*.{yml,yaml}") returns
      # nothing.
      path = File.tempname("noir-passive-file")
      File.write(path, "")
      begin
        options = create_test_options
        options["passive_scan_path"] = YAML::Any.new([YAML::Any.new(path)])
        expect_raises(Noir::CliValidation::Error, /is not a directory/) do
          Noir::CliValidation.validate_passive_scan_paths!(options)
        end
      ensure
        File.delete(path) if File.exists?(path)
      end
    end

    it "accepts an existing directory" do
      options = create_test_options
      options["passive_scan_path"] = YAML::Any.new([YAML::Any.new("/tmp")])
      Noir::CliValidation.validate_passive_scan_paths!(options)
    end

    it "flags the first invalid entry when multiple paths are passed" do
      options = create_test_options
      options["passive_scan_path"] = YAML::Any.new([
        YAML::Any.new("/tmp"),
        YAML::Any.new("/tmp/noir-no-such-dir-#{Random.rand(1_000_000)}"),
      ])
      expect_raises(Noir::CliValidation::Error, /does not exist/) do
        Noir::CliValidation.validate_passive_scan_paths!(options)
      end
    end
  end

  describe "validate_tech_names!" do
    it "rejects unknown --only-techs values" do
      options = create_test_options
      options["only_techs"] = YAML::Any.new("bogusFramework")
      expect_raises(Noir::CliValidation::Error, /unknown tech/) do
        Noir::CliValidation.validate_tech_names!(options)
      end
    end

    it "rejects unknown --exclude-techs values" do
      options = create_test_options
      options["exclude_techs"] = YAML::Any.new("notathing")
      expect_raises(Noir::CliValidation::Error, /unknown tech/) do
        Noir::CliValidation.validate_tech_names!(options)
      end
    end

    it "rejects unknown -t/--techs values" do
      options = create_test_options
      options["techs"] = YAML::Any.new("madeup")
      expect_raises(Noir::CliValidation::Error, /unknown tech/) do
        Noir::CliValidation.validate_tech_names!(options)
      end
    end

    it "flags every unknown name in a comma-separated list, not just the first" do
      options = create_test_options
      options["only_techs"] = YAML::Any.new("flask,fakeOne,fakeTwo")
      # First valid name (flask) passes; the unknown ones must be
      # reported. Error message lists them in the order they appear.
      expect_raises(Noir::CliValidation::Error, /"fakeOne".*"fakeTwo"/) do
        Noir::CliValidation.validate_tech_names!(options)
      end
    end

    it "accepts canonical tech keys" do
      options = create_test_options
      options["only_techs"] = YAML::Any.new("python_flask")
      Noir::CliValidation.validate_tech_names!(options)
    end

    it "accepts alias names" do
      options = create_test_options
      options["only_techs"] = YAML::Any.new("flask")
      Noir::CliValidation.validate_tech_names!(options)
    end

    it "accepts comma-separated mix of canonical + alias" do
      options = create_test_options
      options["only_techs"] = YAML::Any.new("flask,python_flask,express")
      Noir::CliValidation.validate_tech_names!(options)
    end

    it "passes when no tech flags are set" do
      options = create_test_options
      options["only_techs"] = YAML::Any.new("")
      options["exclude_techs"] = YAML::Any.new("")
      options["techs"] = YAML::Any.new("")
      Noir::CliValidation.validate_tech_names!(options)
    end

    # A value that is nothing but separators or whitespace names no tech,
    # and every name in it is "valid" only because the list is empty after
    # stripping. `--only-techs ,` then cleared the detector list and the
    # scan reported zero endpoints with exit 0 — under --no-log, silently.
    it "rejects a value that names no technology at all" do
      {",", " ", ",,", " , "}.each do |value|
        options = create_test_options
        options["only_techs"] = YAML::Any.new(value)
        expect_raises(Noir::CliValidation::Error, /names no technology/) do
          Noir::CliValidation.validate_tech_names!(options)
        end
      end
    end

    it "still accepts a trailing comma next to a real name" do
      options = create_test_options
      options["only_techs"] = YAML::Any.new("flask,")
      Noir::CliValidation.validate_tech_names!(options)
    end
  end

  # `--passive-scan-severity` is validated by its flag handler in options.cr,
  # but the identical `passive_scan_severity:` config key reached
  # `PassiveScanSeverity` untouched — and `meets_threshold?` returns true when
  # the threshold is unknown. So a config-file typo didn't loosen the filter
  # by a level, it removed it: the user's intended filter became no filter,
  # silently. Both sources now pass through this one gate.
  describe "passive_scan_severity" do
    it "rejects an unknown severity" do
      options = create_test_options
      options["passive_scan_severity"] = YAML::Any.new("bogus")

      expect_raises(Noir::CliValidation::Error, /Invalid passive scan severity "bogus"/) do
        Noir::CliValidation.validate_passive_scan_severity!(options)
      end
    end

    it "rejects an empty severity" do
      # `passive_scan_severity:` with no value parses to nil -> "", which is
      # just as unknown to PassiveScanSeverity as a typo is.
      options = create_test_options
      options["passive_scan_severity"] = YAML::Any.new("")

      expect_raises(Noir::CliValidation::Error, /Invalid passive scan severity/) do
        Noir::CliValidation.validate_passive_scan_severity!(options)
      end
    end

    it "accepts every documented level" do
      %w[critical high medium low].each do |level|
        options = create_test_options
        options["passive_scan_severity"] = YAML::Any.new(level)
        Noir::CliValidation.validate_passive_scan_severity!(options)
        options["passive_scan_severity"].to_s.should eq(level)
      end
    end

    it "normalizes case, matching what the CLI flag stores" do
      options = create_test_options
      options["passive_scan_severity"] = YAML::Any.new("HIGH")
      Noir::CliValidation.validate_passive_scan_severity!(options)
      options["passive_scan_severity"].to_s.should eq("high")
    end
  end

  # `--ai-max-token` / `--ai-agent-max-steps` are bounded by
  # `positive_int_or_die!` on the CLI side; their config twins had no bound at
  # all. ConfigInitializer coerces the value to an Int, this checks the range.
  describe "ai integer options" do
    it "rejects a zero agent step budget" do
      options = create_test_options
      options["ai_agent_max_steps"] = YAML::Any.new(0)

      expect_raises(Noir::CliValidation::Error, /Invalid --ai-agent-max-steps '0'/) do
        Noir::CliValidation.validate_ai_integer_options!(options)
      end
    end

    it "rejects a negative token budget" do
      options = create_test_options
      options["ai_max_token"] = YAML::Any.new(-1)

      expect_raises(Noir::CliValidation::Error, /Invalid --ai-max-token '-1'/) do
        Noir::CliValidation.validate_ai_integer_options!(options)
      end
    end

    it "accepts ai_max_token 0, the shipped default meaning \"no limit\"" do
      # `--ai-max-token 0` is rejected on the CLI, but 0 is what
      # default_options and the generated template both carry, so the config
      # path must keep accepting it.
      options = create_test_options
      Noir::CliValidation.validate_ai_integer_options!(options)
      options["ai_max_token"].as_i.should eq(0)
    end

    it "rejects a non-numeric value that survived coercion" do
      options = create_test_options
      options["ai_max_token"] = YAML::Any.new("abc")

      expect_raises(Noir::CliValidation::Error, /Invalid --ai-max-token "abc"/) do
        Noir::CliValidation.validate_ai_integer_options!(options)
      end
    end
  end
end
