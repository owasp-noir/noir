require "option_parser"

# Usage example:
#   parser.on("--old-flag", "removed in 2.0") { }
#   puts File.read(ARGV[0])
OptionParser.parse do |parser|
  parser.on("--real", "the live option") { } # parser.on("--trailing", "x") { }
end
