require "../../models/analyzer"

class AnalyzerSpring < Analyzer
  def analyze
    # Source Analysis
    Dir.glob("#{@base_path}/**/*") do |path|
      spawn do
        next if File.directory?(path)

        if File.exists?(path)
          File.open(path, "r") do |file|
            file.each_line do |line|
              if line.includes? "RequestMapping"
                path_with_slash = mapping_to_path(line)
                if line.includes? "RequestMethod"
                  define_requestmapping_handlers(["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE"])
                else
                  @result << Endpoint.new("#{@url}#{path_with_slash}", "GET")
                end
              end

              if line.includes? "PostMapping"
                path_with_slash = mapping_to_path(line)
                @result << Endpoint.new("#{@url}#{path_with_slash}", "POST")
              end
              if line.includes? "PutMapping"
                path_with_slash = mapping_to_path(line)
                @result << Endpoint.new("#{@url}#{path_with_slash}", "PUT")
              end
              if line.includes? "DeleteMapping"
                path_with_slash = mapping_to_path(line)
                @result << Endpoint.new("#{@url}#{path_with_slash}", "DELETE")
              end
              if line.includes? "PatchMapping"
                path_with_slash = mapping_to_path(line)
                @result << Endpoint.new("#{@url}#{path_with_slash}", "PATCH")
              end
              if line.includes? "GetMapping"
                path_with_slash = mapping_to_path(line)
                @result << Endpoint.new("#{@url}#{path_with_slash}", "GET")
              end
            end
          end
        end
      end
    end
    Fiber.yield

    @result
  end

  def mapping_to_path(content : String)
    splited_line = content.strip.split("(")
    if splited_line.size > 1
      line = splited_line[1].gsub(/"|\)|{|}| /, "")
      if line.size > 0
        if line[0].to_s == "/"
          return line
        else
          if line.to_s.includes? "="
            tmp = line.gsub(",", "=").split("=")
            i = 0
            tmp.each do
              if tmp[i].strip == "value"
                return tmp[i + 1].gsub(/"|\)/, "").strip.split(",")[0].strip
              end
              i += 1
            end
          end
          return "/#{line}"
        end
      end
    end

    ""
  end

  def extract_param(content : String)
    # TODO
    # case1 -> @RequestParam("a")
    # case2 -> String a = param.get("a");
    # case3 -> String a = request.getParameter("a");
    # case4 -> (PATH) @PathVariable("a")
  end

  macro define_requestmapping_handlers(methods)
    {% for method, index in methods %}
      if line.includes? "RequestMethod.{{method.id}}"
        @result << Endpoint.new("#{@url}#{path_with_slash}", "{{method.id}}")
      end
    {% end %}
  end
end

def analyzer_spring(options : Hash(Symbol, String))
  instance = AnalyzerSpring.new(options)
  instance.analyze
end
