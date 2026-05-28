require "colorize"
require "yaml"
require "../common"
require "../legacy"
require "../../options"
require "../../cli_validation"
require "../../banner"
require "../../models/noir"
require "../../techs/techs"
require "../../llm/cache"
require "../../llm/prompt_overrides"

# `noir scan [paths...] [flags]`
#
# Discovers endpoints across one or more code bases. Positional paths
# augment any `-b PATH` flags so both v0 and v1 invocation styles work:
#
#   noir scan ./app                 # v1 positional
#   noir scan ./api ./worker        # v1 multi-path positional
#   noir -b ./app                   # v0 (router default-routes to scan)
#   noir scan -b ./app --passive    # v1 explicit + flags
module Noir::CLI::ScanCommand
  # ANSI 256-color orange used for the protocol-missing warning. Kept
  # as a named constant so the call site reads as "warning color"
  # rather than a bare magic number.
  WARNING_COLOR = Colorize::Color256.new(208)

  # Output formats whose downstream consumers (jq, SARIF parsers,
  # CI report uploaders) treat empty stdout as a hard error. When a
  # scan finds no endpoints, we still emit a valid empty document
  # for these formats — `{"endpoints":[],"passive_results":[]}` for
  # json, the matching shape for the others. Plain / human-oriented
  # formats stay silent because there's nothing meaningful to render.
  STRUCTURED_OUTPUT_FORMATS = Set{"json", "yaml", "jsonl", "toml", "sarif"}

  def self.run(argv : Array(String))
    # Stage ARGV through OptionParser (positional path discovery happens
    # inside `run_options_parser`). Dup `argv` upfront because callers
    # commonly pass ARGV itself, which we are about to clear. The v0
    # deliver/probe flag tokens (`--send-req`, `--use-matchers`, etc.)
    # are rewritten to their v1 equivalents *before* the parser runs,
    # so the LEGACY surface never appears in `scan -h` and the parser
    # itself only needs to know about one set of names.
    args_copy = Noir::CLI::Legacy.translate_flag_aliases(argv.dup)
    saved = ARGV.dup
    begin
      ARGV.clear
      ARGV.concat(args_copy)

      noir_options = run_options_parser
    ensure
      ARGV.clear
      ARGV.concat(saved)
    end

    execute(noir_options)
  end

  private def self.execute(noir_options : Hash(String, YAML::Any))
    apply_cache_flags(noir_options)
    apply_prompt_overrides(noir_options)
    normalize_url!(noir_options)
    validate_url_dependent_flags(noir_options)
    validate_options!(noir_options)

    if noir_options["nolog"] == false
      banner()
    end

    run_scan(noir_options)
  end

  private def self.apply_cache_flags(noir_options : Hash(String, YAML::Any))
    LLM::Cache.disable if noir_options["cache_disable"] == true

    return unless noir_options["cache_clear"] == true

    begin
      outcome = LLM::Cache.clear
      msg = "CACHE: Cleared #{outcome.deleted} entries."
      msg += " (#{outcome.failed} failed)" if outcome.failed > 0
      STDERR.puts msg
    rescue
      # Cache may not be initialized yet; best-effort clear.
    end
  end

  PROMPT_OVERRIDE_SETTERS = {
    "override_filter_prompt"         => ->(v : String) { LLM::PromptOverrides.filter_prompt = v },
    "override_analyze_prompt"        => ->(v : String) { LLM::PromptOverrides.analyze_prompt = v },
    "override_bundle_analyze_prompt" => ->(v : String) { LLM::PromptOverrides.bundle_analyze_prompt = v },
    "override_llm_optimize_prompt"   => ->(v : String) { LLM::PromptOverrides.llm_optimize_prompt = v },
  }

  private def self.apply_prompt_overrides(noir_options : Hash(String, YAML::Any))
    PROMPT_OVERRIDE_SETTERS.each do |key, setter|
      setter.call(noir_options[key].to_s) if noir_options.has_key?(key)
    end
  end

  private def self.normalize_url!(noir_options : Hash(String, YAML::Any))
    url = noir_options["url"].to_s
    return if url.empty?

    # Protocol auto-fill when the user typed a bare host like
    # `-u example.com`. The scheme check below then re-runs against
    # the prepended form so a bare hostname falls through into the
    # http/https-only validation cleanly.
    unless url.includes?("://")
      STDERR.puts "WARNING: The protocol (http or https) is missing in the URL '#{url}'. Defaulting to 'https://'.".colorize(WARNING_COLOR)
      url = "https://#{url}"
      noir_options["url"] = YAML::Any.new(url)
    end

    # `-u` is the base URL that gets prepended to every discovered
    # path. Only http(s) make sense here — other schemes (file://,
    # ftp://, …) were silently concatenated pre-fix and produced
    # nonsense URLs like `file:///etc/passwd/sign`. Reject early.
    lowered = url.downcase
    unless lowered.starts_with?("http://") || lowered.starts_with?("https://")
      Noir::CLI.die("-u/--url must use http:// or https:// (got '#{url}').")
    end

    # Strip `?query` and `#fragment` from the base URL — they're
    # only valid at the end of a URL, so concatenating an endpoint
    # path after them produces a malformed URL
    # (`http://x?foo=bar/sign`). The user almost never meant to put
    # them on the base; warn and drop them.
    if (q = url.index('?')) || (f = url.index('#'))
      cut = [q, f].compact.min
      stripped = url[0...cut]
      dropped = url[cut..]
      STDERR.puts "WARNING: -u/--url should be a base URL — query string / fragment '#{dropped}' would corrupt the per-endpoint URL. Stripping.".colorize(WARNING_COLOR)
      noir_options["url"] = YAML::Any.new(stripped)
    end
  end

  private def self.validate_url_dependent_flags(noir_options : Hash(String, YAML::Any))
    url = noir_options["url"].to_s

    if noir_options["status_codes"] == true && url.empty?
      Noir::CLI.die("--status-codes needs a target URL. Pass it with -u/--url, e.g. `noir scan ./app --status-codes -u http://localhost:3000`.")
    end

    # `--probe` and `--probe-via` both fire HTTP requests against
    # `endpoint.url`, which is just the discovered path (e.g. `/sign`)
    # until `-u/--url` prepends a base. Without `-u` the request URL is
    # malformed and Crest raises — but the SendReq / SendWithProxy
    # delivery loops catch + log to debug level only, so the user sees
    # the normal JSON output with zero requests sent and no warning.
    # Fail early instead.
    if noir_options["probe"]? == YAML::Any.new(true) && url.empty?
      Noir::CLI.die("--probe needs a target URL. Pass it with -u/--url, e.g. `noir scan ./app --probe -u http://localhost:3000`.")
    end

    probe_via = noir_options["probe_via"]?.try(&.to_s) || ""
    if !probe_via.empty? && url.empty?
      Noir::CLI.die("--probe-via needs a target URL. Pass it with -u/--url, e.g. `noir scan ./app --probe-via #{probe_via} -u http://localhost:3000`.")
    end

    exclude_codes = noir_options["exclude_codes"].to_s
    return if exclude_codes.empty?

    if url.empty?
      Noir::CLI.die("--exclude-codes needs a target URL. Pass it with -u/--url, e.g. `noir scan ./app --exclude-codes 404,500 -u http://localhost:3000`.")
    end

    exclude_codes.split(",").each do |code|
      begin
        code.strip.to_i
      rescue
        Noir::CLI.die("--exclude-codes only accepts comma-separated numbers; got '#{code}'.")
      end
    end
  end

  private def self.validate_options!(noir_options : Hash(String, YAML::Any))
    Noir::CliValidation.validate!(noir_options)
  rescue e : Noir::CliValidation::Error
    Noir::CliValidation.exit_with_error(e.message || "Invalid options.")
  end

  # An AI provider is "active" when --ai-provider was set AND either
  # --ai-model was also set OR the provider is an ACP target (which
  # supplies its own default model).
  private def self.ai_provider_active?(options : Hash(String, YAML::Any)) : Bool
    provider = options["ai_provider"].to_s
    return false if provider.empty?

    !options["ai_model"].to_s.empty? || provider.downcase.starts_with?("acp:")
  end

  private def self.run_scan(noir_options : Hash(String, YAML::Any))
    app = NoirRunner.new noir_options
    start_time = Time.instant

    app.logger.debug("Start Debug mode")
    app.logger.debug("Noir version: #{Noir::VERSION}")
    app.logger.debug("Noir options from arguments:")
    noir_options.each do |k, v|
      app.logger.debug_sub("#{k}: #{v}")
    end

    app.logger.debug "Initialized Options:"
    app.options.each do |k, v|
      app.logger.debug_sub "#{k}: #{v}"
    end

    app_diff = nil
    unless noir_options["diff"].to_s.empty?
      diff_path = noir_options["diff"].to_s
      # Validate the diff target exists — without this, a misspelled
      # `--diff-path` silently treats every current endpoint as
      # "added" (because the missing directory analyzes to zero
      # endpoints), which is indistinguishable from "we made huge
      # changes" in CI diff pipelines.
      unless File.exists?(diff_path)
        Noir::CLI.die("--diff-path does not exist: #{diff_path}")
      end
      unless File.directory?(diff_path)
        Noir::CLI.die("--diff-path is not a directory: #{diff_path}")
      end

      diff_options = noir_options.dup
      diff_options["base"] = YAML::Any.new([YAML::Any.new(diff_path)])
      # `noir_options.dup` already carries over the parent's `nolog`
      # setting, so --no-log applies to both scans uniformly.
      # The previous shape force-set nolog=false for the diff side,
      # which mixed diff-scan progress (banner, "Optimizing
      # endpoints", "Found N endpoints") into the JSON stdout when
      # the user explicitly asked for quiet output.

      # Disable PROBE/EXPORT on the diff side. The diff scan is a
      # detection-only pass — its sole purpose is to enumerate the
      # *old* endpoints so the diff report can name what changed.
      # Pre-fix, `--probe --diff-path X` fired HTTP requests against
      # every base endpoint AND every old endpoint (so
      # unchanged-but-present URLs got hit twice and removed-only
      # URLs got hit once), and `--export-es --diff-path X` pushed
      # the stale catalog into the index alongside the current one.
      # Both surprised users running diff scans in CI.
      diff_options["probe"] = YAML::Any.new(false)
      diff_options["probe_via"] = YAML::Any.new("")
      diff_options["export_es"] = YAML::Any.new("")
      diff_options["export_webhook"] = YAML::Any.new("")

      app_diff = NoirRunner.new diff_options
      app.logger.info "Running Noir with Diff mode."
    end

    app.logger.loading "Detecting technologies in the base directory." do
      app.detect
    end

    analysis_message = "Starting code analysis."

    if app.techs.empty?
      app.logger.warning "No technologies detected."
      app.logger.sub "➔ If you know the technology, use the -t flag to specify it."
      app.logger.sub "➔ Browse the supported tech list with `noir list techs`."
      if !app.options["url"].to_s.empty?
        app.logger.info "Falling back to file-based analysis because -u was set."
      elsif ai_provider_active?(app.options)
        app.logger.info "Falling back to AI-based analysis because --ai-provider was set."
      elsif app.passive_results.size > 0
        app.logger.info "Noir found #{app.passive_results.size} passive results."
        app.report
        exit(0)
      else
        # Structured output formats need a valid empty document on
        # stdout even when no endpoints were discovered — downstream
        # `jq` / SARIF parsers / CI report uploaders treat zero bytes
        # as a hard error. Plain text formats stay silent because
        # there's nothing meaningful to render.
        if STRUCTURED_OUTPUT_FORMATS.includes?(app.options["format"].to_s)
          app.report
        end
        exit(0)
      end
    else
      app.logger.success "Detected #{app.techs.size} technologies."

      exclude_techs = app.options["exclude_techs"].to_s.split(",")
      app.techs.each_with_index do |tech, index|
        is_excluded = exclude_techs.any? { |t| NoirTechs.similar_to_tech(t).includes?(tech) }
        prefix = index < app.techs.size - 1 ? "├──" : "└──"
        status = is_excluded ? " (skip)" : ""
        app.logger.sub "#{prefix} #{tech}#{status}"
      end

      app.techs = app.techs.reject do |tech|
        exclude_techs.any? { |t| NoirTechs.similar_to_tech(t).includes?(tech) }
      end
      analysis_message = "Starting code analysis based on the detected technologies."
    end

    app.logger.loading analysis_message do
      app.analyze
    end
    app.logger.success "Identified #{app.endpoints.size} endpoints in total."

    elapsed = Time.instant - start_time
    app.logger.info "Scan completed in #{(elapsed.total_milliseconds / 1000.0).round(4)} s."

    if app_diff.nil?
      app.logger.info "Generating Report."
      app.report
    else
      app.logger.info "Diffing base and diff codebases."
      locator = CodeLocator.instance
      locator.clear_all
      app_diff.detect
      app_diff.analyze

      app.logger.info "Generating Diff Report."
      app.diff_report(app_diff)
    end
  end
end
