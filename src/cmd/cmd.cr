require "option_parser"

OptionParser.parse do |parser|
    parser.banner = "Usage: noir <path> <flags>"
    parser.on "-u", "--url", "Set base URL" do
      # TODO
    end
    parser.on "-o", "--output", "Write result to file" do
      # TODO
    end
    parser.on "-f", "--format", "Set output format [plain/json]" do
      # TODO
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