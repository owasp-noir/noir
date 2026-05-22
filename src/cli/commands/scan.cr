require "colorize"
require "yaml"
require "../common"
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
#   noir -b ./app                   # v0 long-running CI pattern (router default-route)
#   noir scan -b ./app --passive    # v1 explicit + flags
module Noir::CLI::ScanCommand
  def self.run(argv : Array(String))
    # Stage ARGV through OptionParser (positional path discovery happens
    # inside `run_options_parser`). Dup `argv` upfront because callers
    # commonly pass ARGV itself (which we are about to clear).
    args_copy = argv.dup
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

  # Extracted so `noir help scan` can describe the command without
  # actually parsing flags (avoids exit-on-error noise).
  def self.synopsis : String
    "noir scan [PATHS...] [flags]"
  end

  private def self.execute(noir_options : Hash(String, YAML::Any))
    if noir_options["cache_disable"] == true
      LLM::Cache.disable
    end
    if noir_options["cache_clear"] == true
      begin
        cleared = LLM::Cache.clear
        STDERR.puts "CACHE: Cleared #{cleared} entries."
      rescue
      end
    end

    if noir_options.has_key?("override_filter_prompt")
      LLM::PromptOverrides.filter_prompt = noir_options["override_filter_prompt"].to_s
    end
    if noir_options.has_key?("override_analyze_prompt")
      LLM::PromptOverrides.analyze_prompt = noir_options["override_analyze_prompt"].to_s
    end
    if noir_options.has_key?("override_bundle_analyze_prompt")
      LLM::PromptOverrides.bundle_analyze_prompt = noir_options["override_bundle_analyze_prompt"].to_s
    end
    if noir_options.has_key?("override_llm_optimize_prompt")
      LLM::PromptOverrides.llm_optimize_prompt = noir_options["override_llm_optimize_prompt"].to_s
    end

    if noir_options["url"] != "" && !noir_options["url"].to_s.includes?("://")
      STDERR.puts "WARNING: The protocol (http or https) is missing in the URL '#{noir_options["url"]}'. Defaulting to 'https://'.".colorize(Colorize::Color256.new(208))
      noir_options["url"] = YAML::Any.new("https://#{noir_options["url"]}")
    end

    if noir_options["status_codes"] == true && noir_options["url"] == ""
      Noir::CLI.die("--status-codes needs a target URL. Pass it with -u/--url, e.g. `noir scan ./app --status-codes -u http://localhost:3000`.")
    end

    if noir_options["exclude_codes"] != ""
      if noir_options["url"] == ""
        Noir::CLI.die("--exclude-codes needs a target URL. Pass it with -u/--url, e.g. `noir scan ./app --exclude-codes 404,500 -u http://localhost:3000`.")
      end

      noir_options["exclude_codes"].to_s.split(",").each do |code|
        begin
          code.strip.to_i
        rescue
          Noir::CLI.die("--exclude-codes only accepts comma-separated numbers; got '#{code}'.")
        end
      end
    end

    begin
      Noir::CliValidation.validate!(noir_options)
    rescue e : Noir::CliValidation::Error
      Noir::CliValidation.exit_with_error(e.message || "Invalid options.")
    end

    if noir_options["nolog"] == false
      banner()
    end

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
    if noir_options["diff"] != ""
      diff_options = noir_options.dup
      diff_options["base"] = YAML::Any.new([YAML::Any.new(noir_options["diff"].to_s)])
      diff_options["nolog"] = YAML::Any.new(false)

      app_diff = NoirRunner.new diff_options
      app.logger.info "Running Noir with Diff mode."
    end

    app.logger.info "Detecting technologies to base directory."
    app.detect

    if app.techs.empty?
      app.logger.warning "No technologies detected."
      app.logger.sub "➔ If you know the technology, use the -t flag to specify it."
      app.logger.sub "➔ Browse the supported tech list with `noir list techs`."
      if app.options["url"] != ""
        app.logger.info "Start file-based analysis as the -u flag has been used."
      elsif (app.options["ai_provider"] != "") && ((app.options["ai_model"] != "") || app.options["ai_provider"].to_s.downcase.starts_with?("acp:"))
        app.logger.info "Start AI-based analysis as the --ai-provider flag has been used."
      elsif app.passive_results.size > 0
        app.logger.info "Noir found #{app.passive_results.size} passive results."
        app.report
        exit(0)
      else
        exit(0)
      end
    else
      app.logger.success "Detected #{app.techs.size} technologies."

      exclude_techs = app.options["exclude_techs"]?.to_s.split(",") || [] of String
      filtered_techs = app.techs.reject do |tech|
        exclude_techs.any? { |exclude_tech| NoirTechs.similar_to_tech(exclude_tech).includes?(tech) }
      end

      app.techs.each_with_index do |tech, index|
        is_excluded = exclude_techs.any? { |exclude_tech| NoirTechs.similar_to_tech(exclude_tech).includes?(tech) }
        prefix = index < app.techs.size - 1 ? "├──" : "└──"
        status = is_excluded ? " (skip)" : ""
        app.logger.sub "#{prefix} #{tech}#{status}"
      end

      app.techs = filtered_techs
      app.logger.info "Start code analysis based on the detected technology."
    end

    app.analyze
    app.logger.success "Finally identified #{app.endpoints.size} endpoints."

    end_time = Time.instant
    elapsed_time = end_time - start_time

    app.logger.info "Scan completed in #{(elapsed_time.total_milliseconds / 1000.0).round(4)} s."

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
