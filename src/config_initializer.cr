require "file"
require "log"
require "yaml"
require "./utils/home.cr"
require "./llm/native_tool_calling"

class ConfigInitializer
  # Keys that should be coerced from a legacy "yes" / "no" string into
  # a real Bool when parsed from config.yaml. Every boolean field in
  # default_options must be listed here; otherwise direct comparisons
  # like `options["cache_disable"] == true` in scan.cr would miss a
  # legacy `cache_disable: yes` entry and silently leave the flag off.
  BOOLEAN_CONFIG_KEYS = %w[
    color
    debug
    verbose
    include_path
    include_techs
    include_callee
    ai_context
    nolog
    no_spinner
    probe # legacy `send_req` is migrated to `probe` before this coercion runs
    all_taggers
    status_codes
    passive_scan
    passive_scan_auto_update
    passive_scan_no_update_check
    ai_agent
    cache_disable
    cache_clear
    analyze_feign
  ]

  # Keys whose value should always end up as an Array(YAML::Any) so
  # callers can iterate without per-call type checks.
  ARRAY_CONFIG_KEYS = %w[
    base
    probe_header
    probe_skip
    probe_match
    set_pvalue
    set_pvalue_header
    set_pvalue_cookie
    set_pvalue_query
    set_pvalue_form
    set_pvalue_json
    set_pvalue_path
    passive_scan_path
  ]

  # v0 config-key → v1 config-key map. Applied during `read_config`
  # so a `~/.config/noir/config.yaml` written by v0.x with the old
  # deliver/probe keys still loads under v1 without surprises.
  # Mirrors the LEGACY CLI flag aliases in src/options.cr.
  LEGACY_CONFIG_KEY_MAP = {
    "send_req"          => "probe",
    "send_proxy"        => "probe_via",
    "send_es"           => "export_es",
    "send_with_headers" => "probe_header",
    "use_matchers"      => "probe_match",
    "use_filters"       => "probe_skip",
  }

  @config_dir : String
  @config_file : String
  @is_override : Bool

  # `override_path` is the value of CLI `--config-file PATH`. When
  # present, ConfigInitializer reads from that file instead of
  # `$NOIR_HOME/config.yaml`. This makes `--config-file` flow
  # through the same path as the default config — defaults < file <
  # CLI — so a `base:` (or any other key) declared in the user's
  # custom config file is actually applied. Pre-fix the
  # `--config-file PATH` value was only used by validation and a
  # post-CLI merge inside NoirRunner that re-overwrote everything
  # the CLI had just set.
  def initialize(override_path : String? = nil)
    @config_dir = get_home

    if override_path && !override_path.empty?
      @config_file = override_path
      @is_override = true
    else
      @config_file = File.join(@config_dir, "config.yaml")
      @is_override = false
    end

    @config_dir = File.expand_path(@config_dir)
    @config_file = File.expand_path(@config_file)
  end

  def setup
    # Create the directory if it doesn't exist
    Dir.mkdir(@config_dir) unless Dir.exists?(@config_dir)
    Dir.mkdir("#{@config_dir}/passive_rules") unless Dir.exists?("#{@config_dir}/passive_rules")

    # Create the config file if it doesn't exist — but only when this
    # is the *default* config path. When the user passed
    # `--config-file PATH`, a missing file is a user error and is
    # surfaced by CliValidation later; auto-creating a default
    # template at the user-supplied path would silently mask the
    # typo with a generated file.
    return if @is_override
    File.write(@config_file, generate_config_file) unless File.exists?(@config_file)
  rescue e
    # Silent failures here made permission/disk-full problems during startup
    # hard to diagnose. Log at debug level so --debug surfaces the cause
    # without noising up normal runs.
    Log.debug { "ConfigInitializer.setup failed: #{e.message} (#{e.class})" }
  end

  def read_config
    # Ensure the config file is set up
    setup

    # Read the config file, or use the default config if reading fails
    begin
      parsed_yaml = YAML.parse(File.read(@config_file)).as_h
      symbolized_hash = parsed_yaml.transform_keys(&.to_s)

      # Migrate v0 deliver/probe keys to their v1 equivalents before
      # any downstream code looks them up. New keys present in the
      # config win — v0 entry is dropped on collision so the user's
      # explicit v1 setting is never silently overwritten.
      LEGACY_CONFIG_KEY_MAP.each do |old_key, new_key|
        next unless symbolized_hash.has_key?(old_key)
        symbolized_hash[new_key] = symbolized_hash[old_key] unless symbolized_hash.has_key?(new_key)
        symbolized_hash.delete(old_key)
      end

      # Coerce legacy "yes" / "no" strings into Bool for keys the
      # downstream code compares against `true` / `false` directly.
      # `[key]?` is critical: a partial config that only sets one key
      # would otherwise raise KeyError on the next iteration, get
      # swallowed by the outer rescue, and silently revert every
      # setting to defaults.
      BOOLEAN_CONFIG_KEYS.each do |key|
        value = symbolized_hash[key]?
        next if value.nil?

        case value.to_s
        when "yes"
          symbolized_hash[key] = YAML::Any.new(true)
        when "no"
          symbolized_hash[key] = YAML::Any.new(false)
        end
      end

      # Normalize array-style keys: empty string → empty array,
      # bare string → single-element array, real array → unchanged.
      ARRAY_CONFIG_KEYS.each do |key|
        value = symbolized_hash[key]?
        next if value.nil?

        if value.to_s.empty?
          symbolized_hash[key] = YAML::Any.new([] of YAML::Any)
        else
          begin
            value.as_a
          rescue
            symbolized_hash[key] = YAML::Any.new([YAML::Any.new(value.to_s)])
          end
        end
      end

      final_options = default_options.merge(symbolized_hash) { |_, _, new_val| new_val }
      final_options
    rescue e
      # Falling back silently made malformed-YAML bugs hard to track down.
      # Log the cause at debug level and keep the existing default-options
      # fallback so behavior is unchanged.
      Log.debug { "ConfigInitializer.read_config failed, using defaults: #{e.message} (#{e.class})" }
      default_options
    end
  end

  # Default concurrency scales with the host's CPU count, clamped to a
  # safe window. The lower bound of 4 keeps low-core CI runners from
  # serializing on a single worker; the upper bound of 32 keeps
  # channel-synchronisation overhead and (under MT) GC pressure in check
  # on very large boxes. Users who want a specific value still get it
  # via `--concurrency N` or `concurrency:` in the config file — those
  # paths overwrite this default.
  def default_concurrency : String
    System.cpu_count.clamp(4, 32).to_s
  end

  def default_options
    noir_options = {
      "base"                         => YAML::Any.new([] of YAML::Any),
      "color"                        => YAML::Any.new(true),
      "config_file"                  => YAML::Any.new(""),
      "concurrency"                  => YAML::Any.new(default_concurrency),
      "debug"                        => YAML::Any.new(false),
      "verbose"                      => YAML::Any.new(false),
      "exclude_codes"                => YAML::Any.new(""),
      "exclude_path"                 => YAML::Any.new(""),
      "exclude_techs"                => YAML::Any.new(""),
      "only_techs"                   => YAML::Any.new(""),
      "format"                       => YAML::Any.new("plain"),
      "include_path"                 => YAML::Any.new(false),
      "include_techs"                => YAML::Any.new(false),
      "include_callee"               => YAML::Any.new(false),
      "ai_context"                   => YAML::Any.new(false),
      "nolog"                        => YAML::Any.new(false),
      "no_spinner"                   => YAML::Any.new(false),
      "output"                       => YAML::Any.new(""),
      "export_es"                    => YAML::Any.new(""),
      "probe_via"                    => YAML::Any.new(""),
      "probe"                        => YAML::Any.new(false),
      "probe_header"                 => YAML::Any.new([] of YAML::Any),
      "export_webhook"               => YAML::Any.new(""),
      "set_pvalue"                   => YAML::Any.new([] of YAML::Any),
      "set_pvalue_header"            => YAML::Any.new([] of YAML::Any),
      "set_pvalue_cookie"            => YAML::Any.new([] of YAML::Any),
      "set_pvalue_query"             => YAML::Any.new([] of YAML::Any),
      "set_pvalue_form"              => YAML::Any.new([] of YAML::Any),
      "set_pvalue_json"              => YAML::Any.new([] of YAML::Any),
      "set_pvalue_path"              => YAML::Any.new([] of YAML::Any),
      "status_codes"                 => YAML::Any.new(false),
      "techs"                        => YAML::Any.new(""),
      "url"                          => YAML::Any.new(""),
      "probe_skip"                   => YAML::Any.new([] of YAML::Any),
      "probe_match"                  => YAML::Any.new([] of YAML::Any),
      "all_taggers"                  => YAML::Any.new(false),
      "use_taggers"                  => YAML::Any.new(""),
      "diff"                         => YAML::Any.new(""),
      "passive_scan"                 => YAML::Any.new(false),
      "passive_scan_path"            => YAML::Any.new([] of YAML::Any),
      "passive_scan_severity"        => YAML::Any.new("high"),
      "passive_scan_auto_update"     => YAML::Any.new(false),
      "passive_scan_no_update_check" => YAML::Any.new(false),
      "ai_provider"                  => YAML::Any.new(""),
      "ai_model"                     => YAML::Any.new(""),
      "ai_context_features"          => YAML::Any.new(""),
      "ai_key"                       => YAML::Any.new(""),
      "ai_agent"                     => YAML::Any.new(false),
      "ai_agent_max_steps"           => YAML::Any.new(20),
      "ai_native_tools_allowlist"    => YAML::Any.new(LLM::NativeToolCalling.default_allowlist_csv),
      "ai_max_token"                 => YAML::Any.new(0),
      "cache_disable"                => YAML::Any.new(false),
      "cache_clear"                  => YAML::Any.new(false),
      "analyze_feign"                => YAML::Any.new(false),
    }

    noir_options
  end

  def generate_config_file
    options = default_options
    content = <<-YAML
      ---
      # Noir configuration file
      # This file is used to store the configuration options for Noir.
      # You can edit this file to change the configuration options.

      # Config values are defaults; CLI options take precedence.
      # **************************************************************

      # Base directory for the application (can be an array for multiple paths)
      base: []

      # Whether to use color in the output
      color: #{options["color"]}

      # The configuration file to use
      config_file: "#{options["config_file"]}"

      # The number of concurrent operations to perform
      concurrency: "#{options["concurrency"]}"

      # Whether to enable debug mode
      debug: #{options["debug"]}

      # Whether to enable verbose mode
      verbose: #{options["verbose"]}

      # The status codes to exclude
      exclude_codes: "#{options["exclude_codes"]}"

      # Technologies to exclude
      exclude_techs: "#{options["exclude_techs"]}"

      # File paths to exclude (comma-separated glob patterns, e.g. "*.test.js,*_test.go")
      exclude_path: "#{options["exclude_path"]}"

      # The format to use for the output
      format: "#{options["format"]}"

      # Whether to include the path in the output
      include_path: #{options["include_path"]}

      # Whether to include the technology in the output
      include_techs: #{options["include_techs"]}

      # Whether to include 1-hop handler callees in the output
      include_callee: #{options["include_callee"]}

      # Whether to include aggregated AI review context in the output
      ai_context: #{options["ai_context"]}

      # Optional comma-separated subset of AI-context categories to emit
      # (empty = all). Valid: guards, sinks, validators, signals, callee.
      ai_context_features: "#{options["ai_context_features"]}"

      # Whether to disable logging
      nolog: #{options["nolog"]}

      # Whether to disable loading spinners while keeping normal logs
      no_spinner: #{options["no_spinner"]}

      # The output file to write to
      output: "#{options["output"]}"

      # The Elasticsearch / OpenSearch server to export endpoints to
      # e.g http://localhost:9200
      export_es: "#{options["export_es"]}"

      # The proxy URL to route HTTP probes through
      # e.g http://localhost:8080
      probe_via: "#{options["probe_via"]}"

      # Whether to fire HTTP probes at discovered endpoints
      probe: #{options["probe"]}

      # Per-probe headers (Array of strings)
      # e.g "Authorization: Bearer token"
      probe_header:

      # The webhook URL to POST the endpoint catalog as JSON
      # (Slack incoming webhook, Discord webhook, custom receiver, ...)
      # e.g https://hooks.slack.com/services/T0/B0/XXXX
      export_webhook: "#{options["export_webhook"]}"

      # The value to set for pvalue (Array of strings)
      set_pvalue:
      set_pvalue_header:
      set_pvalue_cookie:
      set_pvalue_query:
      set_pvalue_form:
      set_pvalue_json:
      set_pvalue_path:

      # The status codes to use
      status_codes: #{options["status_codes"]}

      # The technologies to use
      techs: "#{options["techs"]}"

      # The URL to use
      url: "#{options["url"]}"

      # Probe-side skip patterns (Array of strings)
      # URL substring, HTTP method, or "method:URL"
      probe_skip:

      # Probe-side match patterns (Array of strings)
      # URL substring, HTTP method, or "method:URL"
      probe_match:

      # Whether to use all taggers
      all_taggers: #{options["all_taggers"]}

      # The taggers to use
      # e.g "tagger1,tagger2"
      # To see the list of all taggers, please use the noir command with --list-taggers
      use_taggers: "#{options["use_taggers"]}"

      # The diff file to use
      diff: "#{options["diff"]}"

      # The passive rules to use
      # e.g /path/to/rules
      passive_scan: false
      passive_scan_path: []

      # Minimum severity level for passive scan (critical, high, medium, low)
      # Default: high (detects high and critical severity issues)
      passive_scan_severity: "high"

      # Automatically update passive rules from repository at startup
      passive_scan_auto_update: false

      # Skip checking for passive rules updates at startup
      passive_scan_no_update_check: false

      # The AI server URL
      ai_provider: "#{options["ai_provider"]}"

      # The AI model to use
      ai_model: "#{options["ai_model"]}"

      # The API key for the AI server
      ai_key: "#{options["ai_key"]}"

      # Enable agentic LLM workflow with iterative tool-calling loop
      ai_agent: #{options["ai_agent"]}

      # The maximum number of steps for the AI agent loop
      ai_agent_max_steps: #{options["ai_agent_max_steps"]}

      # Provider allowlist for native tool-calling (comma-separated)
      ai_native_tools_allowlist: "#{options["ai_native_tools_allowlist"]}"

      # The maximum number of tokens for AI requests (0 = no limit)
      ai_max_token: #{options["ai_max_token"]}

      # CACHE:
      # Disable LLM disk cache for this run
      cache_disable: #{options["cache_disable"]}

      # Clear LLM cache directory before run
      cache_clear: #{options["cache_clear"]}

      YAML

    content
  end
end
