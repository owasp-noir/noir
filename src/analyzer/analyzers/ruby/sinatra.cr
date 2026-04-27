require "../../engines/ruby_engine"

module Analyzer::Ruby
  class Sinatra < RubyEngine
    def analyze
      parallel_file_scan do |path|
        next unless path.ends_with?(".rb") || path.ends_with?(".ru")
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          last_endpoint = Endpoint.new("", "")
          file.each_line.with_index do |line, index|
            next unless line.valid_encoding?
            endpoint = line_to_endpoint(line)
            if endpoint.method != ""
              details = Details.new(PathInfo.new(path, index + 1))
              endpoint.details = details
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
  end
end
