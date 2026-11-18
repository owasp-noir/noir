case ARGV[0]?
when nil
  abort "usage: counter N"
when /^\d+$/
  puts "number"
end
