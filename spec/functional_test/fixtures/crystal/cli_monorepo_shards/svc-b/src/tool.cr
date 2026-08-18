require "option_parser"

OptionParser.parse do |parser|
  parser.on("--only-b", "b") { }
end
