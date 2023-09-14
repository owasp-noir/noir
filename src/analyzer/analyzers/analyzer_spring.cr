require "../../models/analyzer"

class AnalyzerSpring < Analyzer
  REGEX_CLASS_DEFINITION  = /^(((public|private|protected|default)\s+)|^)class\s+/
  REGEX_ROUTER_CODE_BLOCK = /route\(\)?.*?\);/m
  REGEX_ROUTE_CODE_LINE   = /((?:andRoute|route)\s*\(|\.)\s*(GET|POST|DELETE|PUT)\(\s*"([^"]*)/

  def analyze
    # Source Analysis
    begin
      Dir.glob("#{@base_path}/**/*") do |path|
        next if File.directory?(path)

        url = @url
        if File.exists?(path) && (path.ends_with?(".java") || path.ends_with?(".kt"))
          content = File.read(path, encoding: "utf-8", invalid: :skip)

          # Spring MVC
          has_class_been_imported = false
          content.each_line do |line|
            if has_class_been_imported == false && REGEX_CLASS_DEFINITION.match(line)
              has_class_been_imported = true
            end

            if line.includes? "RequestMapping"
              mapping_paths = mapping_to_path(line)
              if has_class_been_imported == false && mapping_paths.size > 0
                class_mapping_url = mapping_paths[0]

                if class_mapping_url.ends_with?("/*")
                  class_mapping_url = class_mapping_url[0..-3]
                end
                if class_mapping_url.ends_with?("/")
                  class_mapping_url = class_mapping_url[0..-2]
                end

                url = "#{@url}#{class_mapping_url}"
              else
                mapping_paths.each do |mapping_path|
                  if line.includes? "RequestMethod"
                    define_requestmapping_handlers(["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE"])
                  else
                    @result << Endpoint.new("#{url}#{mapping_path}", "GET")
                  end
                end
              end
            end

            if line.includes? "PostMapping"
              mapping_paths = mapping_to_path(line)
              mapping_paths.each do |mapping_path|
                @result << Endpoint.new("#{url}#{mapping_path}", "POST")
              end
            end
            if line.includes? "PutMapping"
              mapping_paths = mapping_to_path(line)
              mapping_paths.each do |mapping_path|
                @result << Endpoint.new("#{url}#{mapping_path}", "PUT")
              end
            end
            if line.includes? "DeleteMapping"
              mapping_paths = mapping_to_path(line)
              mapping_paths.each do |mapping_path|
                @result << Endpoint.new("#{url}#{mapping_path}", "DELETE")
              end
            end
            if line.includes? "PatchMapping"
              mapping_paths = mapping_to_path(line)
              mapping_paths.each do |mapping_path|
                @result << Endpoint.new("#{url}#{mapping_path}", "PATCH")
              end
            end
            if line.includes? "GetMapping"
              mapping_paths = mapping_to_path(line)
              mapping_paths.each do |mapping_path|
                @result << Endpoint.new("#{url}#{mapping_path}", "GET")
              end
            end
          end

          # Reactive Router
          content.scan(REGEX_ROUTER_CODE_BLOCK) do |route_code|
            method_code = route_code[0]
            method_code.scan(REGEX_ROUTE_CODE_LINE) do |match|
              next if match.size != 4
              method = match[2]
              endpoint = match[3].gsub(/\n/, "")
              @result << Endpoint.new("#{url}#{endpoint}", method)
            end
          end
        end
      end
    rescue e
      logger.debug e
    end
    Fiber.yield

    @result
  end

  def mapping_to_path(content : String)
    paths = Array(String).new

    splited_line = content.strip.split("(")
    if splited_line.size > 1
      line = splited_line[1].gsub(/"|\)| /, "").gsub(/\s/, "").strip
      if line.size > 0
        if line[0].to_s == "/"
          attribute_index = line.index(/,(\w)+=/)
          if !attribute_index.nil?
            attribute_index -= 1
            line = line[0..attribute_index]
          end

          paths << line
        else
          if is_bracket(line)
            line = line.gsub(/\{|\}/, "")
          end
          if line.size > 0 && line[0].to_s == "/"
            paths << line
          else
            value_flag = false
            line = comma_in_bracket(line)
            line.split(",").each do |comma_line|
              if comma_line.to_s.includes? "value="
                tmp = comma_line.split("=")
                tmp[1].gsub(/"|\)/, "").strip.split("_BRACKET_COMMA_").each do |path|
                  paths << "#{path.strip.gsub("\\", "").gsub(";", "")}"
                  value_flag = true
                end
              end
            end
            if value_flag == false
              paths << ""
            end
          end
        end
      else
        paths << ""
      end
    else
      paths << ""
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
        @result << Endpoint.new("#{url}#{mapping_path}", "{{method.id}}")
      end
    {% end %}
  end
end

def analyzer_spring(options : Hash(Symbol, String))
  instance = AnalyzerSpring.new(options)
  instance.analyze
end
