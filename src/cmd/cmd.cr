require "option_parser"

OptionParser.parse do |parser|
    parser.banner = "Usage: noir <flags>"
    parser.on "-b", "--base-path", "Set base path" do |var|
      Noir::OPTIONS[:base] = var
    end
    parser.on "-u", "--url", "Set base url" do |var|
      Noir::OPTIONS[:url] = var
    end
    parser.on "-f", "--format", "Set output format [plain/json]" do |var|
      Noir::OPTIONS[:format] = var
    end
    parser.on "-o", "--output", "Write result to file" do |var|
      Noir::OPTIONS[:output] = var
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