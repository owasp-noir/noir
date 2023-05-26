def analyzer_rails(options : Hash(Symbol, String))
  result = [] of Endpoint
  base_path = options[:base]
  url = options[:url]

  # Public Dir Analysis
  Dir.glob("#{base_path}/public/**/*") do |file|
    next if File.directory?(file)
    relative_path = file.sub("#{base_path}/public/", "")
    result << Endpoint.new("#{url}/#{relative_path}", "GET")
  end

  # Config Analysis
  File.open("#{base_path}/config/routes.rb", "r") do |file|
    file.each_line do |line|
      stripped_line = line.strip
      if stripped_line.size > 0 && stripped_line[0] != '#'
        line.scan(/resource\s+:.*/) do |match|
          splited = match[0].split(":")
          if splited.size > 1
            resource = splited[1].split(",")[0]
            result << Endpoint.new("#{url}/#{resource}", "GET")
            result << Endpoint.new("#{url}/#{resource}", "POST")
            result << Endpoint.new("#{url}/#{resource}/1", "GET")
            result << Endpoint.new("#{url}/#{resource}/1", "PUT")
            result << Endpoint.new("#{url}/#{resource}/1", "DELETE")
            result << Endpoint.new("#{url}/#{resource}/1", "PATCH")
          end
        end

        line.scan(/get\s+['"](.+?)['"]/) do |match|
          result << Endpoint.new("#{url}/#{match[1]}", "GET")
        end
        line.scan(/post\s+['"](.+?)['"]/) do |match|
          result << Endpoint.new("#{url}/#{match[1]}", "POST")
        end
        line.scan(/put\s+['"](.+?)['"]/) do |match|
          result << Endpoint.new("#{url}/#{match[1]}", "PUT")
        end
        line.scan(/delete\s+['"](.+?)['"]/) do |match|
          result << Endpoint.new("#{url}/#{match[1]}", "DELETE")
        end
        line.scan(/patch\s+['"](.+?)['"]/) do |match|
          result << Endpoint.new("#{url}/#{match[1]}", "PATCH")
        end
      end
    end
  end

  result
end
