require "option_parser"
require "./models/noir.cr"

module Noir
  VERSION = "0.1.0"
end

noir_options = {:base => ".", :url => "", :format => "plain", :output => ""}
OptionParser.parse do |parser|
  parser.banner = "Usage: noir <flags>"
  parser.on "-b PATH", "--base-path PATH", "Set base path" { |var| noir_options[:base] = var }
  parser.on "-u URL", "--url URL", "Set base url" { |var| noir_options[:url] = var }
  parser.on "-f FORMAT", "--format PATH", "Set output format [plain/json]" { |var| noir_options[:format] = var }
  parser.on "-o PATH", "--output PATH", "Write result to file" { |var| noir_options[:output] = var }
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
app.run
