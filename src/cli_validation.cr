require "colorize"
require "yaml"
require "./tagger/tagger"
require "./techs/techs"

module Noir::CliValidation
  class Error < Exception
  end

  VALID_OUTPUT_FORMATS = %w[
    plain
    yaml
    json
    jsonl
    toml
    markdown-table
    sarif
    html
    curl
    httpie
    powershell
    adb
    simctl
    oas2
    oas3
    postman
    only-url
    only-param
    only-header
    only-cookie
    only-tag
    mermaid
  ]

  def self.validate!(options : Hash(String, YAML::Any))
    validate_base_paths!(options)
    validate_output_format!(options)
    validate_concurrency!(options)
    validate_output_path!(options)
    validate_tagger_names!(options)
    validate_config_file!(options)
    validate_tech_names!(options)
    validate_passive_scan_paths!(options)
    validate_ai_provider_pair!(options)
    warn_about_unused_delivery_flags(options)
  end

  # `--ai-provider` and `--ai-model` need each other to take effect.
  # Either flag set on its own silently skips the AI analyzer:
  #   * `--ai-provider openai` (no model) — `ai_provider_active?` is
  #     false, AI never runs, user just gets a plain scan
  #   * `--ai-model gpt-4` (no provider) — same outcome
  # The ACP family is the one exception: `acp:claude` / `acp:codex`
  # carry their own default model, so no `--ai-model` is required.
  def self.validate_ai_provider_pair!(options : Hash(String, YAML::Any))
    provider = options["ai_provider"]?.try(&.to_s) || ""
    model = options["ai_model"]?.try(&.to_s) || ""

    if !model.empty? && provider.empty?
      raise Error.new("--ai-model needs a companion --ai-provider. Set both, e.g. `noir scan ./app --ai-provider openai --ai-model #{model} --ai-key …`.")
    end

    return if provider.empty?

    is_acp = provider.downcase.starts_with?("acp:")
    return if is_acp || !model.empty?

    raise Error.new("--ai-provider '#{provider}' needs a companion --ai-model. Pass it with --ai-model, e.g. `noir scan ./app --ai-provider #{provider} --ai-model gpt-4 --ai-key …`. (ACP providers like `acp:claude` or `acp:codex` are the exception and don't need --ai-model.)")
  end

  # `--passive-scan-path PATH` accepts multiple entries (repeatable),
  # and each must exist + be a directory — `NoirPassiveScan.load_rules`
  # walks `PATH/**/*.{yml,yaml}` and Dir.glob silently returns zero
  # matches for non-existent paths. The result is a passive scan that
  # ran with 0 rules and surfaced 0 findings, with no indication that
  # the path was bogus. Surface the typo at CLI parse time instead.
  def self.validate_passive_scan_paths!(options : Hash(String, YAML::Any))
    raw = options["passive_scan_path"]?
    return if raw.nil?
    paths = raw.raw
    return unless paths.is_a?(Array)

    paths.each do |entry|
      path = entry.to_s
      next if path.empty?
      raise Error.new("--passive-scan-path does not exist: #{path}") unless File.exists?(path)
      raise Error.new("--passive-scan-path is not a directory: #{path}") unless File.directory?(path)
    end
  end

  # `--probe-match` and `--probe-skip` only run inside the Deliver
  # pipeline (the code that ships endpoints to --probe / --probe-via /
  # --export-es / --export-webhook). With no delivery target
  # configured they silently no-op — a real surprise for users who
  # set the flags expecting stdout output to be filtered. Warn at
  # CLI parse time so the gap is obvious.
  def self.warn_about_unused_delivery_flags(options : Hash(String, YAML::Any))
    has_matchers = non_empty_array?(options["probe_match"]?)
    has_filters = non_empty_array?(options["probe_skip"]?)
    return unless has_matchers || has_filters

    delivery_active = (options["probe"]?.try(&.raw) == true) ||
                      !(options["probe_via"]?.try(&.to_s) || "").empty? ||
                      !(options["export_es"]?.try(&.to_s) || "").empty? ||
                      !(options["export_webhook"]?.try(&.to_s) || "").empty?
    return if delivery_active

    flags = [] of String
    flags << "--probe-match" if has_matchers
    flags << "--probe-skip" if has_filters
    STDERR.puts "WARNING: #{flags.join(" / ")} set but no delivery target (--probe / --probe-via / --export-es / --export-webhook). These flags only filter what gets delivered, not what's written to stdout.".colorize(:yellow)
  end

  private def self.non_empty_array?(value : YAML::Any?) : Bool
    return false if value.nil?
    raw = value.raw
    return false unless raw.is_a?(Array)
    !raw.empty?
  end

  # `-t/--techs`, `--only-techs`, `--exclude-techs` should reject
  # unknown tech names eagerly. Pre-fix, a typo like `--only-techs
  # falsk` (instead of `flask`) silently dropped through
  # `NoirTechs.similar_to_tech` returning "" and the scan produced
  # zero endpoints without explanation — indistinguishable from
  # "no flask code found here". Surfacing the typo at CLI parse
  # time saves the surprise.
  def self.validate_tech_names!(options : Hash(String, YAML::Any))
    {"techs", "only_techs", "exclude_techs"}.each do |key|
      raw = options[key]?.try(&.to_s) || ""
      next if raw.empty?
      unknown = raw.split(",").map(&.strip).reject(&.empty?).reject do |tech|
        !NoirTechs.similar_to_tech(tech).empty?
      end
      next if unknown.empty?
      cli_flag = case key
                 when "techs"         then "-t/--techs"
                 when "only_techs"    then "--only-techs"
                 when "exclude_techs" then "--exclude-techs"
                 else                      key
                 end
      raise Error.new("#{cli_flag}: unknown tech#{"es" if unknown.size > 1} #{unknown.map(&.inspect).join(", ")}. List supported names with `noir list techs`.")
    end
  end

  # `--config-file PATH` needs to exist, be a file (not a directory),
  # and parse as a YAML mapping. The previous shape let `File.read` /
  # `YAML.parse` raise straight through to the user, producing a
  # Crystal stack trace for what should be a one-line "wrong path"
  # message.
  def self.validate_config_file!(options : Hash(String, YAML::Any))
    path = options["config_file"]?.try(&.to_s)
    return if path.nil? || path.empty?

    raise Error.new("--config-file does not exist: #{path}") unless File.exists?(path)
    raise Error.new("--config-file is not a file: #{path}") if File.directory?(path)

    begin
      content = File.read(path)
      parsed = YAML.parse(content)
    rescue ex : YAML::ParseException
      raise Error.new("--config-file contains invalid YAML: #{path}\n  #{ex.message}")
    rescue ex : IO::Error
      raise Error.new("--config-file could not be read: #{path}\n  #{ex.message}")
    end

    # Empty files parse to nil; that's OK (treated as "no overrides").
    return if parsed.raw.nil?
    raise Error.new("--config-file must be a YAML mapping at the top level: #{path}") unless parsed.raw.is_a?(Hash)
  end

  def self.validate_base_paths!(options : Hash(String, YAML::Any))
    base_paths = options["base"].as_a.map(&.to_s)
    if base_paths.empty?
      raise Error.new(<<-MSG)
        No path to scan was given.
        Pass one or more directories as positional arguments (or repeat -b/--base-path):
          noir scan ./app
          noir scan ./api ./worker
        Run `noir help scan` for the full flag list.
        MSG
    end

    base_paths.each do |base_path|
      unless File.exists?(base_path)
        raise Error.new("Base path does not exist: #{base_path}")
      end

      unless File.directory?(base_path)
        raise Error.new("Base path is not a directory: #{base_path}")
      end
    end
  end

  def self.validate_output_format!(options : Hash(String, YAML::Any))
    format = options["format"].to_s
    return if VALID_OUTPUT_FORMATS.includes?(format)

    raise Error.new("Invalid output format '#{format}'. Valid formats: #{VALID_OUTPUT_FORMATS.join(", ")}")
  end

  def self.validate_concurrency!(options : Hash(String, YAML::Any))
    raw_value = options["concurrency"].to_s
    value = raw_value.to_i?
    if value.nil? || value < 1
      raise Error.new("Invalid concurrency '#{raw_value}'. Concurrency must be an integer greater than or equal to 1.")
    end

    options["concurrency"] = YAML::Any.new(value)
  end

  def self.validate_output_path!(options : Hash(String, YAML::Any))
    output_path = options["output"].to_s
    return if output_path.empty?

    if File.exists?(output_path) && File.directory?(output_path)
      raise Error.new("Output path is a directory: #{output_path}")
    end

    output_dir = File.dirname(output_path)
    return if output_dir == "." || output_dir.empty?
    return if Dir.exists?(output_dir)

    raise Error.new("Output directory does not exist: #{output_dir}")
  end

  def self.validate_tagger_names!(options : Hash(String, YAML::Any))
    use_taggers = options["use_taggers"].to_s
    return if use_taggers.empty?

    unknown_taggers = NoirTaggers.unknown_tagger_names(use_taggers)
    return if unknown_taggers.empty?

    raise Error.new("Unknown tagger(s): #{unknown_taggers.join(", ")}. Use --list-taggers to see available taggers.")
  end

  def self.exit_with_error(message : String) : NoReturn
    lines = message.lines
    STDERR.puts "ERROR: #{lines.first}".colorize(:yellow)
    lines[1..]?.try do |rest|
      rest.each { |line| STDERR.puts line }
    end
    exit(1)
  end
end
