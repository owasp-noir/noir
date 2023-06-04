require "option_parser"
require "./models/noir.cr"

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
  ]
end

noir_options = {:base => "", :url => "", :format => "plain", :output => "", :techs => ""}
OptionParser.parse do |parser|
  parser.banner = "Usage: noir <flags>"
  parser.separator "  Basic:"
  parser.on "-b PATH", "--base-path ./app", "(Required) Set base path" { |var| noir_options[:base] = var }
  parser.on "-u URL", "--url http://..", "Set base url for endpoints" { |var| noir_options[:url] = var }

  parser.separator "\n  Output:"
  parser.on "-f FORMAT", "--format json", "Set output format [plain/json/curl/httpie]" { |var| noir_options[:format] = var }
  parser.on "-o PATH", "--output out.txt", "Write result to file" { |var| noir_options[:output] = var }

  parser.separator "\n  Technologies:"
  parser.on "-t TECHS", "--techs rails,php", "Set technologies to use" { |var| noir_options[:techs] = var }
  parser.on "-tl", "--techs-list", "Show all technologies" do
    puts "Available technologies:"
    puts Noir::TECHS.join(" ")
    exit
  end

  parser.separator "\n  Others:"
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

if noir_options[:base].empty?
  STDERR.puts "ERROR: Base path is required."
  STDERR.puts "Please use -b or --base-path to set base path."
  exit(1)
end

app = NoirRunner.new noir_options
puts "Detecting technologies..."
app.detect
puts "==> Found #{app.techs.join(" ")} techs."
puts "Start Analyzing..."
app.analyze
puts "==> Finish!"
puts ""
app.report
