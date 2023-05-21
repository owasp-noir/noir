require "option_parser"

def cmd
  noir_options = { :base => ".", :url => "", :format => "plain", :output => "" }
  OptionParser.parse do |parser|
    parser.banner = "Usage: noir <flags>"
    parser.on "-b", "--base-path", "Set base path" { |var| noir_options[:base] = var }
    parser.on "-u", "--url", "Set base url" { |var| noir_options[:url] = var}
    parser.on "-f", "--format", "Set output format [plain/json]" { |var| noir_options[:format] = var}
    parser.on "-o", "--output", "Write result to file" { |var| noir_options[:output] = var }
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
  puts noir_options
  noir_options
end
