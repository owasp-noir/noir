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
                mapping_paths = mapping_to_path(line)
                mapping_paths.each do |mapping_path|
                  if line.includes? "RequestMethod"
                    define_requestmapping_handlers(["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE"])
                  else
                    @result << Endpoint.new("#{@url}#{mapping_path}", "GET")
                  end
                end
              end

              if line.includes? "PostMapping"
                mapping_paths = mapping_to_path(line)
                mapping_paths.each do |mapping_path|
                  @result << Endpoint.new("#{@url}#{mapping_path}", "POST")
                end
              end
              if line.includes? "PutMapping"
                mapping_paths = mapping_to_path(line)
                mapping_paths.each do |mapping_path|
                  @result << Endpoint.new("#{@url}#{mapping_path}", "PUT")
                end
              end
              if line.includes? "DeleteMapping"
                mapping_paths = mapping_to_path(line)
                mapping_paths.each do |mapping_path|
                  @result << Endpoint.new("#{@url}#{mapping_path}", "DELETE")
                end
              end
              if line.includes? "PatchMapping"
                mapping_paths = mapping_to_path(line)
                mapping_paths.each do |mapping_path|
                  @result << Endpoint.new("#{@url}#{mapping_path}", "PATCH")
                end
              end
              if line.includes? "GetMapping"
                mapping_paths = mapping_to_path(line)
                mapping_paths.each do |mapping_path|
                  @result << Endpoint.new("#{@url}#{mapping_path}", "GET")
                end
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
    paths = Array(String).new

    splited_line = content.strip.split("(")
    if splited_line.size > 1
      line = splited_line[1].gsub(/"|\)| /, "").gsub("s", "").strip
      if line.size > 0
        if line[0].to_s == "/"
          paths << line
        else
          if is_bracket(line)
            line = line.gsub(/\{|\}/, "")
          end
          if line[0].to_s == "/"
            paths << line
          else
            line = comma_in_bracket(line)
            line.split(",").each do |comma_line|
              if comma_line.to_s.includes? "value="
                tmp = comma_line.split("=")
                tmp[1].gsub(/"|\)/, "").strip.split("_BRACKET_COMMA_").each do |path|
                  paths << "#{path.strip}"
                end
              end
            end
          end
        end
      end
    end

    paths
  end

  def is_bracket(content : String)
    content.gsub(/\s/, "")[0].to_s == "{"
  end

  def comma_in_bracket(content : String)
    result = content.gsub(/\{(.*?)\}/) do |match|
      match.gsub(",", "_BRACKET_COMMA_")
    end

    result.gsub("{", "").gsub("}", "")
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
        @result << Endpoint.new("#{@url}#{mapping_path}", "{{method.id}}")
      end
    {% end %}
  end
end

def analyzer_spring(options : Hash(Symbol, String))
  instance = AnalyzerSpring.new(options)
  instance.analyze
end
