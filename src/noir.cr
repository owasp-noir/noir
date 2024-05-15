require "option_parser"
require "colorize"
require "./models/noir.cr"
require "./banner.cr"
require "./options.cr"
require "./techs/techs.cr"

module Noir
  VERSION = "0.15.1"
end

banner()
noir_options = run_options_parser()

if noir_options[:base] == ""
  STDERR.puts "ERROR: Base path is required."
  STDERR.puts "Please use -b or --base-path to set base path."
  STDERR.puts "If you need help, use -h or --help."
  exit(1)
end

app = NoirRunner.new noir_options
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

app.logger.system "Detecting technologies to base directory."
app.detect

if app.techs.size == 0
  app.logger.info "No technologies detected."
  if app.options[:url] != ""
    app.logger.system "Start file-based analysis as the -u flag has been used."
  else
    exit(0)
  end
else
  app.logger.info "Detected #{app.techs.size} technologies."
  app.techs.each do |tech|
    app.logger.info_sub "#{tech}"
  end
  app.logger.system "Start code analysis based on the detected technology."
end

app.analyze
app.logger.info "Finally identified #{app.endpoints.size} endpoints."

app.logger.system "Generating Report."
app.report
