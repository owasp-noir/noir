sync = ARGV[0]? == "sync"
purge = ARGV == ["purge", "--force"]
token = ENV["DEMO_TOKEN"]
mode = case ARGV[0]?
       when "report"
         ARGV[1]
       end
puts sync, purge, token, mode
