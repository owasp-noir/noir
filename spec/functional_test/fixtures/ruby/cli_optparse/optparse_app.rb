require "optparse"

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: optparser [options]"
  opts.on("-v", "--verbose", "Run verbosely") { options[:verbose] = true }
  opts.on("-p", "--port PORT", Integer, "Port to bind") { |p| options[:port] = p }
end.parse!

db = ENV["DATABASE_URL"]
puts db
