require "../../models/analyzer"

class AnalyzerRubySinatra < Analyzer
  def analyze
    # Source Analysis
    begin
      Dir.glob("#{@base_path}/**/*") do |path|
        next if File.directory?(path)
        if File.exists?(path)
          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            last_endpoint = Endpoint.new("", "")
            file.each_line do |line|
              endpoint = line_to_endpoint(line)
              if endpoint.method != ""
                @result << endpoint
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
      logger.debug e
    end

    @result
  end

  def line_to_param(content : String) : Param
    if content.includes? "param["
      param = content.split("param[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "query")
    end

    if content.includes? "params["
      param = content.split("params[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "query")
    end

    if content.includes? "request.env["
      param = content.split("request.env[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "header")
    end

    if content.includes? "headers["
      param = content.split("headers[")[1].split("]")[0].gsub("\"", "").gsub("'", "").gsub(":", "")
      return Param.new(param, "", "header")
    end

    if content.includes? "cookies["
      param = content.split("cookies[")[1].split("]")[0].gsub("\"", "").gsub("'", "").gsub(":", "")
      return Param.new(param, "", "cookie")
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

    Endpoint.new("", "")
  end
end

def analyzer_ruby_sinatra(options : Hash(Symbol, String))
  instance = AnalyzerRubySinatra.new(options)
  instance.analyze
end
