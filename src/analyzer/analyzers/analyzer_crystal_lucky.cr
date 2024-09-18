require "../../models/analyzer"

class AnalyzerCrystalLucky < Analyzer
  def analyze
    # Public Dir Analysis
    begin
      Dir.glob("#{@base_path}/public/**/*") do |file|
        next if File.directory?(file)
        real_path = "#{@base_path}/public/".gsub(/\/+/, '/')
        relative_path = file.sub(real_path, "")
        @result << Endpoint.new("/#{relative_path}", "GET")
      end
    rescue e
      logger.debug e
    end

    # Source Analysis
    begin
      Dir.glob("#{@base_path}/**/*") do |path|
        next if File.directory?(path)
        if File.exists?(path) && File.extname(path) == ".cr" && !path.includes?("lib")
          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            last_endpoint = Endpoint.new("", "")
            file.each_line.with_index do |line, index|
              endpoint = line_to_endpoint(line)
              if endpoint.method != ""
                details = Details.new(PathInfo.new(path, index + 1))
                endpoint.set_details(details)
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
      logger.debug e
    end

    result
  end

  def line_to_param(content : String) : Param
    if content.includes? "params.from_query[\""
      param = content.split("params.from_query[\"")[1].split("\"]")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "query")
    end

    if content.includes? "params.from_json[\""
      param = content.split("params.from_json[\"")[1].split("\"]")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "json")
    end

    if content.includes? "params.from_form_data[\""
      param = content.split("params.from_form_data[\"")[1].split("\"]")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "form")
    end

    if content.includes? "params.get("
      param = content.split("params.get(")[1].split(")")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param.gsub(":", ""), "", "query")
    end

    if content.includes? "request.headers["
      param = content.split("request.headers[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "header")
    end

    if content.includes? "cookies.get("
      param = content.split("cookies.get(")[1].split(")")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "cookie")
    end

    if content.includes? "cookies["
      param = content.split("cookies[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "cookie")
    end

    Param.new("", "", "")
  end

  def line_to_endpoint(content : String) : Endpoint
    content.scan(/get\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{match[1]}", "GET")
      end
    end

    content.scan(/post\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{match[1]}", "POST")
      end
    end

    content.scan(/put\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{match[1]}", "PUT")
      end
    end

    content.scan(/delete\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{match[1]}", "DELETE")
      end
    end

    content.scan(/patch\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{match[1]}", "PATCH")
      end
    end

    content.scan(/trace\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{match[1]}", "TRACE")
      end
    end

    content.scan(/ws\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        endpoint = Endpoint.new("#{match[1]}", "GET")
        endpoint.set_protocol("ws")
        return endpoint
      end
    end

    Endpoint.new("", "")
  end
end

def analyzer_crystal_lucky(options : Hash(String, YAML::Any))
  instance = AnalyzerCrystalLucky.new(options)
  instance.analyze
end
