case ARGV[0]?
when "-v", "--version"
  puts "0.1"
else
  puts File.read(ARGV[0])
end
