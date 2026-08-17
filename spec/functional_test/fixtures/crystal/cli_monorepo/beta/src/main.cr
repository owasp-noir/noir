require "option_parser"

OptionParser.parse do |parser|
  parser.on("--beta-only", "beta") { }
end
