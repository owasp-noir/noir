require "../../utils/utils.cr"
require "../../models/analyzer"

class AnalyzerPhpPure < Analyzer
  def analyze
    # Source Analysis
    begin
      Dir.glob("#{base_path}/**/*") do |path|
        next if File.directory?(path)
        if base_path[-1].to_s == "/"
          relative_path = path.sub("#{base_path}", "").sub("./", "").sub("//", "/")
        else
          relative_path = path.sub("#{base_path}/", "").sub("./", "").sub("//", "/")
        end
        relative_path = remove_start_slash(relative_path)

        if File.exists?(path) && File.extname(path) == ".php"
          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            params_query = [] of Param
            params_body = [] of Param
            methods = [] of String

            file.each_line do |line|
              if allow_patterns.any? { |pattern| line.includes? pattern }
                match = line.strip.match(/\$_(.*?)\['(.*?)'\]/)

                if match
                  method = match[1]
                  param_name = match[2]

                  if method == "GET"
                    params_query << Param.new(param_name, "", "query")
                  elsif method == "POST"
                    params_body << Param.new(param_name, "", "form")
                    methods << "POST"
                  elsif method == "REQUEST"
                    params_query << Param.new(param_name, "", "query")
                    params_body << Param.new(param_name, "", "form")
                    methods << "POST"
                  elsif method == "SERVER"
                    if param_name.includes? "HTTP_"
                      param_name = param_name.sub("HTTP_", "").gsub("_", "-")
                      params_query << Param.new(param_name, "", "header")
                      params_body << Param.new(param_name, "", "header")
                    end
                  end
                end
              end
            rescue
              next
            end
            methods.each do |method|
              result << Endpoint.new("#{url}/#{relative_path}", method, params_body)
            end
            result << Endpoint.new("#{url}/#{relative_path}", "GET", params_query)
          end
        end
      end
    rescue e
      logger.debug e
    end
    Fiber.yield

    result
  end

  def allow_patterns
    ["$_GET", "$_POST", "$_REQUEST", "$_SERVER"]
  end
end

def analyzer_php_pure(options : Hash(Symbol, String))
  instance = AnalyzerPhpPure.new(options)
  instance.analyze
end
