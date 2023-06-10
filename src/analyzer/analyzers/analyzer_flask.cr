def analyzer_flask(options : Hash(Symbol, String))
  result = [] of Endpoint
  base_path = options[:base]
  url = options[:url]
  _ = url

  # Source Analysis
  Dir.glob("#{base_path}/**/*") do |path|
    spawn do
      next if File.directory?(path)
      if File.exists?(path) && File.extname(path) == ".py"
        File.open(path, "r") do |file|
          file.each_line do |line|
            line.strip.scan(/@app\.route\((.*)\)/) do |match|
              if match.size > 0
                splited = match[0].split("(")
                if splited.size > 1
                  endpoint_path = splited[1].gsub("\"", "").gsub("'", "").gsub(")", "").gsub(" ", "")
                  result << Endpoint.new("#{url}#{endpoint_path}", "GET")
                end
              end
            end
          end
        end
      end
    end
  end
  Fiber.yield

  result
end
