require "../../../models/analyzer"

module Analyzer::Javascript
  class Express < Analyzer
    def analyze
      # Source Analysis
      begin
        Dir.glob("#{base_path}/**/*") do |path|
          next if File.directory?(path)
          if File.exists?(path)
            File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
              last_endpoint = Endpoint.new("", "")
              file.each_line.with_index do |line, index|
                endpoint = line_to_endpoint(line)
                if endpoint.method != ""
                  details = Details.new(PathInfo.new(path, index + 1))
                  endpoint.details = details
                  result << endpoint
                  last_endpoint = endpoint
                end

                param = line_to_param(line)
                if param.name != ""
                  if last_endpoint.method != ""
                    last_endpoint.push_param(param)
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

    def line_to_param(line : String) : Param
      if line.includes? "req.body."
        param = line.split("req.body.")[1].split(")")[0].split("}")[0].split(";")[0]
        return Param.new(param, "", "json")
      end

      if line.includes? "req.query."
        param = line.split("req.query.")[1].split(")")[0].split("}")[0].split(";")[0]
        return Param.new(param, "", "query")
      end

      if line.includes? "req.cookies."
        param = line.split("req.cookies.")[1].split(")")[0].split("}")[0].split(";")[0]
        return Param.new(param, "", "cookie")
      end

      if line.includes? "req.header("
        param = line.split("req.header(")[1].split(")")[0].gsub(/['"]/, "")
        return Param.new(param, "", "header")
      end

      Param.new("", "", "")
    end

    def line_to_endpoint(line : String) : Endpoint
      if line.includes? ".get('/"
        api_path = express_get_endpoint(line)
        if api_path != ""
          return Endpoint.new(api_path, "GET")
        end
      end
      if line.includes? ".post('/"
        api_path = express_get_endpoint(line)
        if api_path != ""
          return Endpoint.new(api_path, "POST")
        end
      end
      if line.includes? ".put('/"
        api_path = express_get_endpoint(line)
        if api_path != ""
          return Endpoint.new(api_path, "PUT")
        end
      end
      if line.includes? ".delete('/"
        api_path = express_get_endpoint(line)
        if api_path != ""
          return Endpoint.new(api_path, "DELETE")
        end
      end
      if line.includes? ".patch('/"
        api_path = express_get_endpoint(line)
        if api_path != ""
          return Endpoint.new(api_path, "PATCH")
        end
      end

      Endpoint.new("", "")
    end
  end
end
