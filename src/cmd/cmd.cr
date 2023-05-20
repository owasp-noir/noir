require "option_parser"

OptionParser.parse do |parser|
  parser.banner = "Usage: noir <flags>"
  parser.on "-b", "--base-path", "Set base path" { |var| Noir::OPTIONS[:base] = var }
  parser.on "-u", "--url", "Set base url" { |var| Noir::OPTIONS[:url] = var}
  parser.on "-f", "--format", "Set output format [plain/json]" { |var| Noir::OPTIONS[:format] = var}
  parser.on "-o", "--output", "Write result to file" { |var| Noir::OPTIONS[:output] = var}
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