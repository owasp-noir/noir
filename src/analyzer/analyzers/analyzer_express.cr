def analyzer_express(options : Hash(Symbol, String))
  result = [] of Endpoint
  base_path = options[:base]
  url = options[:url]
  _ = url

  # Source Analysis
  Dir.glob("#{base_path}/**/*") do |path|
    next if File.directory?(path)
    if File.exists?(path)
      File.open(path, "r") do |file|
        file.each_line do |line|
          if line.includes? ".get('/"
            api_path = express_get_endpoint(line)
            if api_path != ""
              result << Endpoint.new(api_path, "GET")
            end
          end
          if line.includes? ".post('/"
            api_path = express_get_endpoint(line)
            if api_path != ""
              result << Endpoint.new(api_path, "POST")
            end
          end
          if line.includes? ".put('/"
            api_path = express_get_endpoint(line)
            if api_path != ""
              result << Endpoint.new(api_path, "PUT")
            end
          end
          if line.includes? ".delete('/"
            api_path = express_get_endpoint(line)
            if api_path != ""
              result << Endpoint.new(api_path, "DELETE")
            end
          end
          if line.includes? ".patch('/"
            api_path = express_get_endpoint(line)
            if api_path != ""
              result << Endpoint.new(api_path, "PATCH")
            end
          end
        end
      end
    end
  end

  result
end

def express_get_endpoint(line : String)
  api_path = ""
  splited = line.split("(")
  if splited.size > 0
    api_path = splited[1].split(",")[0].gsub(/['"]/, "")
  end

  api_path
end
