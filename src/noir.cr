require "option_parser"
require "./models/noir.cr"

module Noir
  VERSION = "0.1.0"
end

noir_options = {:base => ".", :url => "", :format => "plain", :output => "", :techs => ""}
OptionParser.parse do |parser|
  parser.banner = "Usage: noir <flags>"
  parser.on "-b PATH", "--base-path ./app", "Set base path" { |var| noir_options[:base] = var }
  parser.on "-u URL", "--url http://..", "Set base url" { |var| noir_options[:url] = var }
  parser.on "-f FORMAT", "--format json", "Set output format [plain/json/curl/httpie]" { |var| noir_options[:format] = var }
  parser.on "-o PATH", "--output out.txt", "Write result to file" { |var| noir_options[:output] = var }
  parser.on "-t TECHS", "--techs rails,php", "Set technologies to use" { |var| noir_options[:techs] = var }
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

app = NoirRunner.new noir_options
puts "[+] Detecting technologies..."
app.detect
puts "[+] Found #{app.techs.join(" ")} techs."
puts "[+] Start Analyzing..."
app.analyze
puts "[+] Finish"
puts ""
app.report
