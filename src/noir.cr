require "option_parser"
require "colorize"
require "./models/noir.cr"
require "./banner.cr"
require "./options.cr"
require "./techs/techs.cr"
require "./llm/cache"

module Noir
  VERSION = "0.23.1"
end

# Run options parser
noir_options = run_options_parser()

# Handle CACHE flags
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

# Check base path
if noir_options["base"] == ""
  STDERR.puts "ERROR: Base path is required.".colorize(:yellow)
  STDERR.puts "Please use -b or --base-path to set base path."
  STDERR.puts "If you need help, use -h or --help."
  exit(1)
end

if noir_options["url"] != "" && !noir_options["url"].to_s.includes?("://")
  STDERR.puts "WARNING: The protocol (http or https) is missing in the URL '#{noir_options["url"]}'.".colorize(Colorize::Color256.new(208))
  noir_options["url"] = YAML::Any.new("http://#{noir_options["url"]}")
end

# Check URL
if noir_options["status_codes"] == true && noir_options["url"] == ""
  STDERR.puts "ERROR: The --status-codes option requires the -u or --url flag to be specified.".colorize(:yellow)
  STDERR.puts "Please use -u or --url to set the URL."
  STDERR.puts "If you need help, use -h or --help."
  exit(1)
end

# Check URL
if noir_options["exclude_codes"] != ""
  if noir_options["url"] == ""
    STDERR.puts "ERROR: The --exclude-codes option requires the -u or --url flag to be specified.".colorize(:yellow)
    STDERR.puts "Please use -u or --url to set the URL."
    STDERR.puts "If you need help, use -h or --help."
    exit(1)
  end

  noir_options["exclude_codes"].to_s.split(",").each do |code|
    begin
      code.strip.to_i
    rescue
      STDERR.puts "ERROR: Invalid --exclude-codes option: '#{code}'".colorize(:yellow)
      STDERR.puts "Please use comma-separated numbers."
      exit(1)
    end
  end
end

# Run Noir
if noir_options["nolog"] == false
  banner()
end

app = NoirRunner.new noir_options
start_time = Time.monotonic

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
  # Diff mode
  diff_options = noir_options.dup
  diff_options["base"] = noir_options["diff"]
  diff_options["nolog"] = YAML::Any.new(false)

  app_diff = NoirRunner.new diff_options
  app.logger.info "Running Noir with Diff mode."
end

# Run Default mode
app.logger.info "Detecting technologies to base directory."
app.detect

if app.techs.empty?
  app.logger.warning "No technologies detected."
  app.logger.sub "➔ If you know the technology, use the -t flag to specify it."
  app.logger.sub "➔ Please check tech lists using the --list-techs flag."
  if app.options["url"] != ""
    app.logger.info "Start file-based analysis as the -u flag has been used."
  elsif (app.options["ollama"] != "") && (app.options["ollama_model"] != "")
    app.logger.info "Start AI-based analysis as the --ollama and --ollama-model flags have been used."
  elsif (app.options["ai_provider"] != "") && (app.options["ai_model"] != "")
    app.logger.info "Start AI-based analysis as the --ai-provider and --ai-model flags have been used."
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

# Check and print scan time
end_time = Time.monotonic
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
