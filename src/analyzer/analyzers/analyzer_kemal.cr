require "../../models/analyzer"

class AnalyzerKemal < Analyzer
  def analyze
    # Source Analysis
    Dir.glob("#{@base_path}/**/*") do |path|
      next if File.directory?(path)
      if File.exists?(path) && File.extname(path) == ".cr" && !path.includes?("spec") && !path.includes?("lib")
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          last_endpoint = Endpoint.new("", "")
          file.each_line do |line|
            endpoint = line_to_endpoint(line)
            if endpoint.method != ""
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

    result
  end

  def line_to_param(content : String) : Param
    if content.includes? "env.params.query["
      param = content.split("env.params.query[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "query")
    end

    if content.includes? "env.params.json["
      param = content.split("env.params.json[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "json")
    end

    if content.includes? "env.params.body["
      param = content.split("env.params.body[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "body")
    end

    if content.includes? "env.response.headers["
      param = content.split("env.response.headers[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "header")
    end

    Param.new("", "", "")
  end

  def line_to_endpoint(content : String) : Endpoint
    content.scan(/get\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "GET")
      end
    end

    content.scan(/post\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "POST")
      end
    end

    content.scan(/put\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "PUT")
      end
    end

    content.scan(/delete\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "DELETE")
      end
    end

    content.scan(/patch\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "PATCH")
      end
    end

    content.scan(/head\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "HEAD")
      end
    end

    content.scan(/options\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "OPTIONS")
      end
    end

    content.scan(/ws\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        endpoint = Endpoint.new("#{@url}#{match[1]}", "GET")
        endpoint.set_protocol("ws")
        return endpoint
      end
    end

    Endpoint.new("", "")
  end
end

def analyzer_kemal(options : Hash(Symbol, String))
  instance = AnalyzerKemal.new(options)
  instance.analyze
end
