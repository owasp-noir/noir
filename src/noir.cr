require "option_parser"
require "colorize"
require "./models/noir.cr"
require "./banner.cr"
require "./options.cr"

module Noir
  VERSION = "0.1.0"
  TECHS   = [
    "ruby_rails",
    "ruby_sinatra",
    "go_echo",
    "java_spring",
    "python_django",
    "python_flask",
    "php_pure",
    "java_jsp",
    "js_express",
  ]
end

noir_options = default_options()
banner()

OptionParser.parse do |parser|
  parser.banner = "Usage: noir <flags>"
  parser.separator "  Basic:".colorize(:blue)
  parser.on "-b PATH", "--base-path ./app", "(Required) Set base path" { |var| noir_options[:base] = var }
  parser.on "-u URL", "--url http://..", "Set base url for endpoints" { |var| noir_options[:url] = var }
  parser.on "-s SCOPE", "--scope url,param", "Set scope for detection" { |var| noir_options[:scope] = var }

  parser.separator "\n  Output:".colorize(:blue)

  parser.on "-f FORMAT", "--format json", "Set output format [plain/json/markdown-table/curl/httpie]" { |var| noir_options[:format] = var }
  parser.on "-o PATH", "--output out.txt", "Write result to file" { |var| noir_options[:output] = var }
  parser.on "--no-color", "Disable color output" do
    noir_options[:color] = "no"
  end

  parser.separator "\n  Deliver:".colorize(:blue)
  parser.on "--send-proxy http://proxy..", "Send the results to the web request via http proxy" { |var| noir_options[:send_proxy] = var }

  parser.separator "\n  Technologies:".colorize(:blue)
  parser.on "-t TECHS", "--techs rails,php", "Set technologies to use" { |var| noir_options[:techs] = var }
  parser.on "--techs-list", "Show all technologies" do
    puts "Available technologies:"
    puts Noir::TECHS.join("\n")
    exit
  end

  parser.separator "\n  Others:".colorize(:blue)
  parser.on "-d", "--debug", "Show debug messages" do
    noir_options[:debug] = "yes"
  end
  parser.on "-v", "--version", "Show version" do
    puts Noir::VERSION
    exit
  end
  parser.on "-h", "--help", "Show help" do
    puts parser
    exit
  end
  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end

if noir_options[:base] == ""
  STDERR.puts "ERROR: Base path is required."
  STDERR.puts "Please use -b or --base-path to set base path."
  STDERR.puts "If you need help, use -h or --help."
  exit(1)
end

app = NoirRunner.new noir_options
app.logger.debug("Start Debug mode")
app.logger.debug("Noir version: #{Noir::VERSION}")
app.logger.debug("Noir options: #{noir_options}")

app.logger.info "Detecting technologies..."
app.detect
if app.techs.size == 0
  app.logger.info "No technologies detected."
  exit(1)
else
  app.logger.info "==> Found #{app.techs.size} techs."
  app.logger.info "==> Techs: #{app.techs.join(" ")}"
  app.logger.info "Analyzing..."
  app.analyze
  app.logger.info "==> Finish! Found #{app.endpoints.size} endpoints."
  app.logger.info "Generating Report..."
  app.report
end
