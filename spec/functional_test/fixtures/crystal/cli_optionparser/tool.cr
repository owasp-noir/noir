require "option_parser"

verbose = false
name = ""
OptionParser.parse do |parser|
  parser.on("-v", "--verbose", "Verbose output") { verbose = true }
  parser.on("-n NAME", "--name=NAME", "Name") { |n| name = n }
end

token = ENV["API_TOKEN"]
first = ARGV[0]
puts "#{verbose} #{name} #{token} #{first}"
