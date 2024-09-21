require "option_parser"
require "colorize"
require "./models/noir.cr"
require "./banner.cr"
require "./options.cr"
require "./techs/techs.cr"

module Noir
  VERSION = "0.17.0"
end

# Print banner
banner()

# Run options parser
noir_options = run_options_parser()

# Check base path
if noir_options["base"] == ""
  STDERR.puts "ERROR: Base path is required.".colorize(:yellow)
  STDERR.puts "Please use -b or --base-path to set base path."
  STDERR.puts "If you need help, use -h or --help."
  exit(1)
end

if noir_options["url"] != "" && noir_options["url"].to_s.starts_with?("http") == false
  STDERR.puts "ERROR: Invalid URL format: '#{noir_options["url"]}' (missing HTTP protocol).".colorize(:yellow)
  noir_options["url"] = YAML::Any.new("http://#{noir_options["url"]}")
end

# Check URL
if noir_options["show_status"] == true && noir_options["url"] == ""
  STDERR.puts "ERROR: --show-status requires -u or --url flag.".colorize(:yellow)
  STDERR.puts "Please use -u or --url to set the URL."
  STDERR.puts "If you need help, use -h or --help."
  exit(1)
end

# Check URL
if noir_options["exclude_status"] != ""
  if noir_options["url"] == ""
    STDERR.puts "ERROR: --exclude-status requires -u or --url flag.".colorize(:yellow)
    STDERR.puts "Please use -u or --url to set the URL."
    STDERR.puts "If you need help, use -h or --help."
    exit(1)
  end

  noir_options["exclude_status"].to_s.split(",").each do |code|
    begin
      code.strip.to_i
    rescue
      STDERR.puts "ERROR: Invalid --exclude-status option: '#{code}'".colorize(:yellow)
      STDERR.puts "Please use comma-separated numbers."
      exit(1)
    end
  end
end

# Run Noir
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

if app.techs.size == 0
  app.logger.warning "No technologies detected."
  app.logger.sub "➔ If you know the technology, use the -t flag to specify it."
  app.logger.sub "➔ Please check tech lists using the --list-techs flag."
  if app.options["url"] != ""
    app.logger.info "Start file-based analysis as the -u flag has been used."
  else
    exit(0)
  end
else
  if app.techs.size > 0
    app.logger.success "Detected #{app.techs.size} technologies."
    app.techs.each_with_index do |tech, index|
      if index < app.techs.size - 1
        app.logger.sub "├── #{tech}"
      else
        app.logger.sub "└── #{tech}"
      end
    end
    app.logger.info "Start code analysis based on the detected technology."
  end
end

app.analyze
app.logger.success "Finally identified #{app.endpoints.size} endpoints."

# Check and print scan time
end_time = Time.monotonic
elapsed_time = end_time - start_time

app.logger.info "Scan completed in #{elapsed_time.total_milliseconds.round} ms."

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
