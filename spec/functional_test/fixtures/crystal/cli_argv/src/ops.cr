require "option_parser"

url = ENV["DEMO_DB_URL"]
case ARGV.shift?
when "item-add"
  name, kind = ARGV
  puts name, kind
when "item-remove"
  id = ARGV[0]?.try(&.to_i64?)
  puts id
when "item-list"
  limit = 10
  OptionParser.parse(ARGV) do |parser|
    parser.on("--limit=N", "Max rows") { |v| limit = v.to_i }
  end
  puts limit
when "--help", "-h"
  puts "usage"
else
  exit 2
end
