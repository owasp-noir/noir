require "../../models/analyzer"

class AnalyzerExpress < Analyzer
  def analyze
    # Source Analysis
    begin
      Dir.glob("#{base_path}/**/*") do |path|
        next if File.directory?(path)
        if File.exists?(path)
          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            file.each_line do |line|
              if line.includes? ".get('/"
                api_path = express_get_endpoint(line)
                if api_path != ""
                  endpoint = (url + api_path).gsub(/\/\//, "/")
                  result << Endpoint.new(endpoint, "GET")
                end
              end
              if line.includes? ".post('/"
                api_path = express_get_endpoint(line)
                if api_path != ""
                  endpoint = (url + api_path).gsub(/\/\//, "/")
                  result << Endpoint.new(endpoint, "POST")
                end
              end
              if line.includes? ".put('/"
                api_path = express_get_endpoint(line)
                if api_path != ""
                  result << Endpoint.new(url + api_path, "PUT")
                end
              end
              if line.includes? ".delete('/"
                api_path = express_get_endpoint(line)
                if api_path != ""
                  endpoint = (url + api_path).gsub(/\/\//, "/")
                  result << Endpoint.new(endpoint, "DELETE")
                end
              end
              if line.includes? ".patch('/"
                api_path = express_get_endpoint(line)
                if api_path != ""
                  endpoint = (url + api_path).gsub(/\/\//, "/")
                  result << Endpoint.new(endpoint, "PATCH")
                end
              end
            end
          end
        end
      end
    rescue e
      # TODO
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
end

def analyzer_express(options : Hash(Symbol, String))
  instance = AnalyzerExpress.new(options)
  instance.analyze
end
