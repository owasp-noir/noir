require "./completions.cr"
require "./config_initializer.cr"
require "./banner.cr"
require "yaml"

private def append_to_yaml_array(hash : Hash(String, YAML::Any), key : String, value : String)
  arr = (hash[key]? || YAML::Any.new([] of YAML::Any)).as_a.dup
  arr << YAML::Any.new(value)
  hash[key] = YAML::Any.new(arr)
end

# Append a value onto a comma-separated string option, accumulating across
# repeated flags instead of overwriting (so `--flag a --flag b` keeps both).
# When `reset_if` equals the current value — e.g. an untouched default list —
# the accumulation starts fresh so the first user value replaces the default
# rather than appending to it.
private def append_to_csv_option(hash : Hash(String, YAML::Any), key : String, value : String, reset_if : String? = nil)
  existing = (hash[key]? || YAML::Any.new("")).to_s
  existing = "" if reset_if && existing == reset_if
  combined = existing.empty? ? value : "#{existing},#{value}"
  hash[key] = YAML::Any.new(combined)
end

# Pre-scan ARGV for `--config-file PATH` / `--config-file=PATH` so
# `run_options_parser` can hand the path to ConfigInitializer
# before any YAML is read. Returns the last occurrence (matching
# OptionParser's last-wins semantics for repeated value flags).
# Doesn't strip the token from ARGV — OptionParser still sees it
# and writes `config_file` into noir_options for downstream
# CliValidation. Returns nil when the flag isn't present.
private def scan_config_file_override(args : Array(String)) : String?
  found : String? = nil
  i = 0
  while i < args.size
    arg = args[i]
    if arg == "--config-file"
      if i + 1 < args.size
        found = args[i + 1]
        i += 2
        next
      end
    elsif arg.starts_with?("--config-file=")
      found = arg.split("=", 2)[1]
    end
    i += 1
  end
  found
end

# Validate a CLI flag value that needs to be a positive (>=1)
# integer. `String#to_i` raises ArgumentError on non-numeric input
# and silently produces 0 for "" — both surface as Crystal stack
# traces, which `--ai-max-token abc` used to do. Centralize the
# guard so every numeric flag prints the same friendly error.
private def positive_int_or_die!(flag : String, raw : String) : Int32
  value = raw.to_i?
  if value.nil? || value < 1
    STDERR.puts "ERROR: Invalid #{flag} '#{raw}'. Must be a positive integer.".colorize(:yellow)
    exit(1)
  end
  value
end

private def process_override_flag(
  flag : String, option_key : String,
  noir_options : Hash(String, YAML::Any),
  args : Array(String), i : Int32,
) : Int32
  if i + 1 < args.size && !args[i + 1].starts_with?("-")
    noir_options[option_key] = YAML::Any.new(args[i + 1])
    i + 2
  else
    STDERR.puts "ERROR: #{flag} requires an argument.".colorize(:yellow)
    exit(1)
  end
end

def extract_hidden_prompt_flags(noir_options : Hash(String, YAML::Any)) : Array(String)
  args = ARGV.dup
  filtered = [] of String
  i = 0
  override_flags = {
    "--override-analyze-prompt"        => "override_analyze_prompt",
    "--override-llm-optimize-prompt"   => "override_llm_optimize_prompt",
    "--override-bundle-analyze-prompt" => "override_bundle_analyze_prompt",
    "--override-filter-prompt"         => "override_filter_prompt",
  }

  while i < args.size
    arg = args[i]
    if override_flags.has_key?(arg)
      i = process_override_flag(arg, override_flags[arg], noir_options, args, i)
    else
      filtered << arg
      i += 1
    end
  end
  filtered = normalize_ai_context_flag(filtered)
  filtered = extract_legacy_aliases(filtered, noir_options)
  filtered
end

# Silently translate v0 flag spellings to their v1 storage. Keeping the
# work here (instead of `parser.on "--include-path"`) means the legacy
# names no longer clutter `noir scan -h`, while every v0 script keeps
# working untouched in v1.x.
LEGACY_PVALUE_TARGETS = {
  "--set-pvalue"        => "set_pvalue",
  "--set-pvalue-header" => "set_pvalue_header",
  "--set-pvalue-cookie" => "set_pvalue_cookie",
  "--set-pvalue-query"  => "set_pvalue_query",
  "--set-pvalue-form"   => "set_pvalue_form",
  "--set-pvalue-json"   => "set_pvalue_json",
  "--set-pvalue-path"   => "set_pvalue_path",
}

LEGACY_INCLUDE_TARGETS = {
  "--include-path"   => "include_path",
  "--include-techs"  => "include_techs",
  "--include-callee" => "include_callee",
}

def extract_legacy_aliases(args : Array(String), noir_options : Hash(String, YAML::Any)) : Array(String)
  result = [] of String
  i = 0
  while i < args.size
    arg = args[i]
    if key = LEGACY_INCLUDE_TARGETS[arg]?
      noir_options[key] = YAML::Any.new(true)
      i += 1
    elsif pvalue_key = LEGACY_PVALUE_TARGETS[arg]?
      if i + 1 >= args.size
        STDERR.puts "ERROR: #{arg} requires an argument.".colorize(:yellow)
        exit(1)
      end
      append_to_yaml_array(noir_options, pvalue_key, args[i + 1])
      i += 2
    else
      result << arg
      i += 1
    end
  end
  result
end

# `--ai-context` accepts an optional comma-separated feature list. Crystal's
# OptionParser cannot express "optional positional value", so we rewrite
# the few well-defined ambiguous forms upfront:
#
#   --ai-context                 → --ai-context=         (bare, all features)
#   --ai-context=guards,sinks    → unchanged             (explicit value)
#   --ai-context guards,sinks    → --ai-context=guards,sinks (heuristic)
#   --ai-context ./app           → --ai-context=         (next token is a path)
#
# The heuristic for "is the next token a feature list?" is intentionally
# tight: lowercase comma-separated words drawn from a fixed vocabulary.
# This keeps `noir scan --ai-context ./app` working as a positional path.
AI_CONTEXT_FEATURES = ["guards", "sinks", "validators", "signals", "callee", "all"]

def normalize_ai_context_flag(args : Array(String)) : Array(String)
  result = [] of String
  i = 0
  while i < args.size
    arg = args[i]
    if arg == "--ai-context"
      if i + 1 < args.size && ai_context_feature_list?(args[i + 1])
        result << "--ai-context=#{args[i + 1]}"
        i += 2
      else
        result << "--ai-context="
        i += 1
      end
    else
      result << arg
      i += 1
    end
  end
  result
end

private def ai_context_feature_list?(token : String) : Bool
  return false if token.starts_with?("-")
  return false unless token.matches?(/\A[a-z,]+\z/)
  tokens = token.split(',').reject(&.empty?)
  return false if tokens.empty?
  tokens.all? { |t| AI_CONTEXT_FEATURES.includes?(t) }
end

private def base_help : String
  <<-HELP
    #{"USAGE:".colorize(:green)}
      noir scan [PATHS...] [flags]

    #{"EXAMPLES:".colorize(:green)}
      #{"Basic scan".colorize(:yellow)}
        noir scan ./myapp

      #{"JSON output to file".colorize(:yellow)}
        noir scan ./myapp -f json -o endpoints.json

      #{"Enable passive security scan".colorize(:yellow)}
        noir scan ./myapp -P

      #{"AI integration".colorize(:yellow)}
        $ noir scan . --ai-provider openai --ai-model gpt-5.5 --ai-key YOUR_API_KEY
        $ noir scan . --ai-provider acp:codex
        $ noir scan . --ai-provider acp:claude

      #{"Replay endpoints through Burp/ZAP".colorize(:yellow)}
        noir scan ./myapp --probe-via http://127.0.0.1:8080 -u http://target

    HELP
end

def run_options_parser
  # Resolve `--config-file PATH` (if present in ARGV) before
  # ConfigInitializer reads the file, so the user-supplied path
  # becomes the source ConfigInitializer parses. Defaults < file <
  # CLI flag falls out naturally because OptionParser writes CLI
  # values on top of `noir_options` after the file is merged.
  override_config_path = scan_config_file_override(ARGV)
  config_init = ConfigInitializer.new(override_config_path)
  noir_options = config_init.read_config
  noir_options["config_file"] = YAML::Any.new(override_config_path) if override_config_path

  extracted_args = extract_hidden_prompt_flags(noir_options)

  OptionParser.parse(extracted_args) do |parser|
    parser.banner = base_help

    parser.separator "FLAGS:".colorize(:green)

    parser.separator " BASE:".colorize(:blue)
    parser.on "-b PATH", "--base-path PATH", "Add a base path to scan (positional paths work too; repeatable)" do |v|
      append_to_yaml_array(noir_options, "base", v)
    end
    parser.on "-u URL", "--url http://...", "Prepend this base URL to every discovered path; required for --status-codes, --probe, and --probe-via" do |v|
      noir_options["url"] = YAML::Any.new(v)
    end

    parser.separator "\n OUTPUT:".colorize(:blue)
    parser.on "-f FMT", "--format json", <<-DESC do |v|
      Output format:
        plain                Plain text (default)
        yaml                 YAML
        json                 JSON
        jsonl                JSON Lines
        toml                 TOML
        markdown-table       Markdown table
        sarif                SARIF format
        html                 HTML report
        curl                 cURL commands
        httpie               HTTPie commands
        powershell           PowerShell Invoke-WebRequest commands
        adb                  ADB commands for Android entry points
        simctl               simctl commands for iOS entry points
        oas2                 OpenAPI 2.0 (Swagger)
        oas3                 OpenAPI 3.0
        postman              Postman collection
        only-url             Only endpoint URLs
        only-param           Only parameters
        only-header          Only headers
        only-cookie          Only cookies
        only-tag             Only tags
        mermaid              Mermaid diagram
      DESC
      noir_options["format"] = YAML::Any.new(v)
    end
    parser.on "-o PATH", "--output out.txt", "Write result to file" do |v|
      noir_options["output"] = YAML::Any.new(v)
    end

    parser.on "--pvalue TYPE=VAL", "Set parameter value (TYPE: any|header|cookie|query|form|json|path; repeatable)" do |v|
      handle_pvalue(noir_options, v)
    end

    parser.on "--status-codes", "Display HTTP status codes" do
      noir_options["status_codes"] = YAML::Any.new(true)
    end
    parser.on "--exclude-codes 404,500", "Exclude HTTP codes (comma-separated; repeatable)" do |v|
      # Accumulate same as --exclude-path / --use-taggers / -t etc.
      # so users can repeat the flag (`--exclude-codes 404
      # --exclude-codes 500`) without losing the first value.
      append_to_csv_option(noir_options, "exclude_codes", v)
    end
    parser.on "--exclude-path PATTERN", "Exclude files by glob (e.g. *.test.js,*_test.go; repeatable)" do |v|
      # Storage is a comma-separated string (the detector splits on
      # `,` per-file). Pre-fix, the second `--exclude-path` clobbered
      # the first via plain `=`. Concatenate instead so users can
      # repeat the flag OR pack patterns into one comma list — both
      # shapes accumulate to the same final list.
      append_to_csv_option(noir_options, "exclude_path", v)
    end
    parser.on "--include LIST", "Enrich plain output (comma-separated: path,techs,callee)" do |v|
      apply_include_list(noir_options, v)
    end
    parser.on "--ai-context [LIST]", <<-DESC do |v|
      Include aggregated AI review context. With no argument, emits every
      category (guards, callees, sinks, validators, signals). Pass a
      comma-separated subset to narrow the output:
        --ai-context guards,sinks
        --ai-context=callee
      DESC
      apply_ai_context(noir_options, v)
    end
    parser.on "--no-color", "Disable color output" do
      noir_options["color"] = YAML::Any.new(false)
    end
    parser.on "--no-spinner", "Disable loading spinner animations" do
      noir_options["no_spinner"] = YAML::Any.new(true)
    end
    parser.on "--no-log", "Show only results" do
      noir_options["nolog"] = YAML::Any.new(true)
    end

    parser.separator "\n PASSIVE SCAN:".colorize(:blue)
    parser.on "-P", "--passive-scan", "Enable passive security scan" do
      noir_options["passive_scan"] = YAML::Any.new(true)
    end
    parser.on "--passive-scan-path PATH", "Use a custom passive-rule directory (replaces the bundled rules; repeatable)" do |v|
      append_to_yaml_array(noir_options, "passive_scan_path", v)
    end
    parser.on "--passive-scan-severity LVL", "Min severity (critical|high|medium|low, default: high)" do |v|
      lvl = v.downcase
      if lvl.in?(%w[critical high medium low])
        noir_options["passive_scan_severity"] = YAML::Any.new(lvl)
      else
        STDERR.puts "ERROR: Invalid severity '#{v}'. Valid: critical, high, medium, low".colorize(:yellow)
        exit(1)
      end
    end
    parser.on "--passive-scan-auto-update", "Auto-update rules at startup" do
      noir_options["passive_scan_auto_update"] = YAML::Any.new(true)
    end
    parser.on "--passive-scan-no-update-check", "Skip rule update check" do
      noir_options["passive_scan_no_update_check"] = YAML::Any.new(true)
    end

    parser.separator "\n TAGGER:".colorize(:blue)
    parser.on "-T", "--use-all-taggers", "Activate all taggers" do
      noir_options["all_taggers"] = YAML::Any.new(true)
    end
    parser.on "--use-taggers LIST", "Activate specific taggers (comma-separated; repeatable)" do |v|
      # Same comma-storage pattern as --exclude-path: repeated flags
      # accumulate into one comma list so the downstream parser
      # (`NoirTaggers.run_tagger`) gets the union, not just the last
      # `--use-taggers` value. Pre-fix `--use-taggers hunt
      # --use-taggers cors` silently dropped `hunt` because the
      # second assignment overwrote the first.
      append_to_csv_option(noir_options, "use_taggers", v)
    end

    # PROBE — fire HTTP requests against the endpoints noir just
    # discovered (active replay). The v0 deliver flag names
    # (`--send-req`, `--send-proxy`, `--with-headers`, `--use-matchers`,
    # `--use-filters`) are rewritten to the v1 spellings in
    # `Noir::CLI::Legacy.translate_flag_aliases` before this parser
    # sees ARGV, so old CI scripts and Dockerfiles still parse
    # without polluting `scan -h` with a LEGACY section.
    parser.separator "\n PROBE:".colorize(:blue)
    parser.on "--probe", "Fire HTTP requests at discovered endpoints (needs -u)" do
      noir_options["probe"] = YAML::Any.new(true)
    end
    parser.on "--probe-via URL", "Route probes through this proxy URL" do |v|
      noir_options["probe_via"] = YAML::Any.new(v)
    end
    parser.on "--probe-header VAL", "Add header to each probe (repeatable)" do |v|
      append_to_yaml_array(noir_options, "probe_header", v)
    end
    parser.on "--probe-match VAL", "Only probe endpoints matching pattern (repeatable)" do |v|
      append_to_yaml_array(noir_options, "probe_match", v)
    end
    parser.on "--probe-skip VAL", "Skip endpoints matching pattern (repeatable)" do |v|
      append_to_yaml_array(noir_options, "probe_skip", v)
    end

    # EXPORT — ship the endpoint catalog to an external data store.
    # Categorically different from probing: no HTTP traffic to the
    # endpoints themselves, just data shipping.
    parser.separator "\n EXPORT:".colorize(:blue)
    parser.on "--export-es URL", "Index endpoints in Elasticsearch" do |v|
      noir_options["export_es"] = YAML::Any.new(v)
    end
    parser.on "--export-opensearch URL", "Index endpoints in OpenSearch (ES-protocol compatible)" do |v|
      # OpenSearch speaks the same HTTP protocol as Elasticsearch for
      # the `POST /_doc` shape noir uses, so the existing
      # SendElasticSearch delivery class talks to OpenSearch
      # unmodified. Same internal key on purpose.
      noir_options["export_es"] = YAML::Any.new(v)
    end
    parser.on "--export-webhook URL", "POST endpoint catalog as JSON to a webhook URL" do |v|
      noir_options["export_webhook"] = YAML::Any.new(v)
    end

    parser.separator "\n AI Integration:".colorize(:blue)
    parser.on "--ai-provider PREFIX|URL", <<-DESC do |v|
      Specify AI provider prefix or full custom URL (required for AI features).

      Supported prefixes:
        openai     → https://api.openai.com/v1
        xai        → https://api.x.ai/v1
        github     → https://models.github.ai/inference
        azure      → https://models.inference.ai.azure.com
        openrouter → https://openrouter.ai/api/v1
        ollama     → http://localhost:11434/v1
        lmstudio   → http://localhost:1234/v1
        vllm       → http://localhost:8000/v1
        acp:codex  → npx @zed-industries/codex-acp
        acp:gemini → gemini --experimental-acp
        acp:claude → npx @zed-industries/claude-agent-acp

      Or use a custom URL directly:
        --ai-provider http://localhost:8000/v1
      DESC
      noir_options["ai_provider"] = YAML::Any.new(v)
    end
    parser.on "--ai-model NAME", "Model name (optional for acp:* providers)" do |v|
      noir_options["ai_model"] = YAML::Any.new(v)
    end
    parser.on "--ai-key KEY", "API key (or set NOIR_AI_KEY env)" do |v|
      noir_options["ai_key"] = YAML::Any.new(v)
    end
    parser.on "--ai-agent", "Enable agentic AI workflow (iterative tool-calling loop)" do
      noir_options["ai_agent"] = YAML::Any.new(true)
    end
    parser.on "--ai-agent-max-steps N", "Max steps for AI agent loop (default: 20)" do |v|
      validated = positive_int_or_die!("--ai-agent-max-steps", v)
      noir_options["ai_agent_max_steps"] = YAML::Any.new(validated)
    end
    parser.on "--ai-native-tools-allowlist LIST", "Provider allowlist for native tool-calling (comma-separated; repeatable; default: #{LLM::NativeToolCalling.default_allowlist_csv})" do |v|
      # Accumulate so users can layer providers across multiple
      # `--ai-native-tools-allowlist` invocations the same way they
      # do for `--use-taggers`, `--exclude-techs`, etc. The default
      # is the global CSV — once any user value arrives, replace
      # the default before extending. Without this guard, the user's
      # first `--ai-native-tools-allowlist openai` would land
      # appended onto the default list ("openai,anthropic,gemini,…
      # ,openai") instead of replacing it.
      append_to_csv_option(noir_options, "ai_native_tools_allowlist", v, reset_if: LLM::NativeToolCalling.default_allowlist_csv)
    end
    parser.on "--ai-max-token N", "Max tokens per request" do |v|
      validated = positive_int_or_die!("--ai-max-token", v)
      noir_options["ai_max_token"] = YAML::Any.new(validated)
    end

    parser.separator "\n DIFF:".colorize(:blue)
    parser.on "--diff-path PATH", "Old code version for diff" do |v|
      noir_options["diff"] = YAML::Any.new(v)
    end

    # Three flags act at different stages of the tech pipeline:
    #   --techs        — append to the analyzer set after detection
    #                    runs (auto-detection still happens, these
    #                    techs are *added* on top)
    #   --only-techs   — restrict the detector pool, so auto-detection
    #                    can only surface these techs
    #   --exclude-techs — drop these techs from the final result
    #                    (post-detection filter)
    # All three are independent; users who really want "only scan as
    # flask, suppress detection entirely" combine `--only-techs flask`
    # (so detection can't find anything else) with `--techs flask`
    # (so flask still runs even if detection misses it).
    parser.separator "\n TECHNOLOGIES:".colorize(:blue)
    # All three flags accept either a comma-separated list value
    # (`-t flask,python_django`) or repeated invocations
    # (`-t flask -t python_django`). Both shapes accumulate into
    # the same comma-string storage that the detector splits on.
    # Pre-fix the repeated form was last-write: `-t flask` got
    # silently clobbered by a following `-t python_django`,
    # masked only when auto-detection happened to re-surface the
    # dropped tech. `--only-techs` and `--exclude-techs` had the
    # same shape.
    parser.on "-t LIST", "--techs rails,php", "Add these techs to the analyzer set (in addition to auto-detected ones; repeatable)" do |v|
      append_to_csv_option(noir_options, "techs", v)
    end
    parser.on "--only-techs LIST", "Restrict auto-detection to these tech detectors (repeatable)" do |v|
      append_to_csv_option(noir_options, "only_techs", v)
    end
    parser.on "--exclude-techs LIST", "Drop these techs from the final result after detection (repeatable)" do |v|
      append_to_csv_option(noir_options, "exclude_techs", v)
    end

    parser.separator "\n CONFIG:".colorize(:blue)
    parser.on "--config-file PATH", "YAML config file" do |v|
      noir_options["config_file"] = YAML::Any.new(v)
    end
    parser.on "--concurrency N", "Concurrency level" do |v|
      value = v.to_i?
      if value.nil? || value < 1
        STDERR.puts "ERROR: Invalid concurrency '#{v}'. Concurrency must be an integer greater than or equal to 1.".colorize(:yellow)
        exit(1)
      end

      noir_options["concurrency"] = YAML::Any.new(value)
    end
    parser.separator "\n CACHE:".colorize(:blue)
    parser.on "--cache-disable", "Disable LLM cache" do
      noir_options["cache_disable"] = YAML::Any.new(true)
    end
    parser.on "--cache-clear", "Clear LLM cache before run" do
      noir_options["cache_clear"] = YAML::Any.new(true)
    end

    parser.separator "\n DEBUG:".colorize(:blue)
    parser.on "-d", "--debug", "Enable debug messages" do
      noir_options["debug"] = YAML::Any.new(true)
    end
    parser.on "--verbose", "Verbose mode (+ --include path + --use-all-taggers)" do
      noir_options["verbose"] = YAML::Any.new(true)
      noir_options["include_path"] = YAML::Any.new(true)
      noir_options["all_taggers"] = YAML::Any.new(true)
    end

    parser.on "-h", "--help", "Show this help" do
      puts parser
      exit
    end

    parser.invalid_option do |flag|
      case flag
      when "--ollama", "--ollama-model"
        STDERR.puts "ERROR: #{flag} was removed in v1.0.".colorize(:yellow)
        STDERR.puts "       Use --ai-provider ollama [--ai-model NAME] instead."
        STDERR.puts "       Example: noir scan ./app --ai-provider ollama --ai-model llama3"
        exit(1)
      else
        STDERR.puts "ERROR: #{flag} is not a valid option.".colorize(:yellow)
        STDERR.puts parser
        exit(1)
      end
    end

    parser.missing_option do |flag|
      STDERR.puts "ERROR: #{flag} requires an argument.".colorize(:yellow)
      exit(1)
    end
  end

  # Anything left in `extracted_args` after OptionParser ran is a
  # positional argument. In v1 scan, those are treated as additional
  # base paths so `noir scan ./a ./b` mirrors `-b ./a -b ./b`.
  extracted_args.each do |positional|
    next if positional.starts_with?("-")
    append_to_yaml_array(noir_options, "base", positional)
  end

  noir_options
end

# Split `TYPE=VAL` (or bare `VAL` → all-types) and route it into the
# right slot in noir_options. `--pvalue` may be repeated to set multiple
# values across different types.
PVALUE_TYPE_KEYS = {
  "any"    => "set_pvalue",
  "all"    => "set_pvalue",
  "header" => "set_pvalue_header",
  "cookie" => "set_pvalue_cookie",
  "query"  => "set_pvalue_query",
  "form"   => "set_pvalue_form",
  "json"   => "set_pvalue_json",
  "path"   => "set_pvalue_path",
}

def handle_pvalue(noir_options : Hash(String, YAML::Any), spec : String)
  type, value = if idx = spec.index('=')
                  {spec[0...idx], spec[(idx + 1)..]}
                else
                  {"any", spec}
                end

  key = PVALUE_TYPE_KEYS[type]?
  if key.nil?
    STDERR.puts "ERROR: --pvalue: unknown type '#{type}'. Valid: #{PVALUE_TYPE_KEYS.keys.join(", ")}.".colorize(:yellow)
    exit(1)
  end

  append_to_yaml_array(noir_options, key, value)
end

INCLUDE_TARGETS = {
  "path"   => "include_path",
  "techs"  => "include_techs",
  "callee" => "include_callee",
}

def apply_include_list(noir_options : Hash(String, YAML::Any), spec : String)
  spec.split(',').reject(&.empty?).each do |raw|
    target = raw.strip.downcase
    key = INCLUDE_TARGETS[target]?
    if key.nil?
      STDERR.puts "ERROR: --include: unknown target '#{raw.strip}'. Valid: #{INCLUDE_TARGETS.keys.join(", ")}.".colorize(:yellow)
      exit(1)
    end
    noir_options[key] = YAML::Any.new(true)
  end
end

# `--ai-context[=LIST]` always enables AI context output. An empty LIST
# means "every category"; a non-empty LIST narrows the output to the
# named categories.
AI_CONTEXT_VALID_FEATURES = {"guards", "sinks", "validators", "signals", "callee", "all"}

def apply_ai_context(noir_options : Hash(String, YAML::Any), spec : String)
  noir_options["ai_context"] = YAML::Any.new(true)

  raw_list = spec.split(',').map(&.strip).reject(&.empty?)
  list = raw_list.map(&.downcase)
  return if list.empty? || list.includes?("all")

  list.each_with_index do |feature, idx|
    unless AI_CONTEXT_VALID_FEATURES.includes?(feature)
      # Echo the user's original spelling (not the lowercased form)
      # in the error so a typo like `Sinkz` reads as the user wrote
      # it.
      STDERR.puts "ERROR: --ai-context: unknown feature '#{raw_list[idx]}'. Valid: #{(AI_CONTEXT_VALID_FEATURES.to_a - ["all"]).join(", ")}.".colorize(:yellow)
      exit(1)
    end
  end

  noir_options["ai_context_features"] = YAML::Any.new(list.join(","))
end
