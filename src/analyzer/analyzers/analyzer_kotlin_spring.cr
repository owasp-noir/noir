require "../../models/analyzer"

class AnalyzerKotlinSpring < Analyzer
  REGEX_CLASS_DEFINITION  = /^(((public|private|protected|default)\s+)|^)class\s+/
  REGEX_ROUTER_CODE_BLOCK = /route\(\)?.*?\);/m
  REGEX_ROUTE_CODE_LINE   = /((?:andRoute|route)\s*\(|\.)\s*(GET|POST|DELETE|PUT)\(\s*"([^"]*)/

  def analyze
    # Source Analysis
    begin
      Dir.glob("#{@base_path}/**/*") do |path|
        next if File.directory?(path)

        url = ""
        if File.exists?(path) && path.ends_with?(".kt")
          content = File.read(path, encoding: "utf-8", invalid: :skip)
          last_endpoint = Endpoint.new("", "")

          # Spring MVC
          has_class_been_imported = false
          content.each_line.with_index do |line, index|
            details = Details.new(PathInfo.new(path, index + 1))
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

                url = "#{class_mapping_url}"
              else
                mapping_paths.each do |mapping_path|
                  if line.includes? "RequestMethod"
                    define_requestmapping_handlers(["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE"])
                  else
                    endpoint = Endpoint.new("#{url}#{mapping_path}", "GET", details)
                    last_endpoint = endpoint
                    @result << last_endpoint
                  end
                end
              end
            end

            if line.includes? "PostMapping"
              mapping_paths = mapping_to_path(line)
              mapping_paths.each do |mapping_path|
                endpoint = Endpoint.new("#{url}#{mapping_path}", "POST", details)
                last_endpoint = endpoint
                @result << last_endpoint
              end
            end
            if line.includes? "PutMapping"
              mapping_paths = mapping_to_path(line)
              mapping_paths.each do |mapping_path|
                endpoint = Endpoint.new("#{url}#{mapping_path}", "PUT", details)
                last_endpoint = endpoint
                @result << last_endpoint
              end
            end
            if line.includes? "DeleteMapping"
              mapping_paths = mapping_to_path(line)
              mapping_paths.each do |mapping_path|
                endpoint = Endpoint.new("#{url}#{mapping_path}", "DELETE", details)
                last_endpoint = endpoint
                @result << last_endpoint
              end
            end
            if line.includes? "PatchMapping"
              mapping_paths = mapping_to_path(line)
              mapping_paths.each do |mapping_path|
                endpoint = Endpoint.new("#{url}#{mapping_path}", "PATCH", details)
                last_endpoint = endpoint
                @result << last_endpoint
              end
            end
            if line.includes? "GetMapping"
              mapping_paths = mapping_to_path(line)
              mapping_paths.each do |mapping_path|
                endpoint = Endpoint.new("#{url}#{mapping_path}", "GET", details)
                last_endpoint = endpoint
                @result << last_endpoint
              end
            end

            # Param Analysis
            param = line_to_param(line)
            if param.name != ""
              if last_endpoint.method != ""
                last_endpoint.push_param(param)
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
              details = Details.new(PathInfo.new(path))
              @result << Endpoint.new("#{url}#{endpoint}", method, details)
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

  def line_to_param(line : String) : Param
    if line.includes? "getParameter("
      param = line.split("getParameter(")[1].split(")")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "query")
    end

    if line.includes? "@RequestParam("
      param = line.split("@RequestParam(")[1].split(")")[0].gsub("\"", "").gsub("'", "")
      return Param.new(param, "", "query")
    end

    Param.new("", "", "")
  end

  def mapping_to_path(line : String)
    unless line.includes? "("
      # no path
      return [""]
    end

    paths = Array(String).new
    splited_line = line.strip.split("(")
    if splited_line.size > 1 && splited_line[1].includes? ")"
      params = splited_line[1].split(")")[0]
      params = params.gsub(/\s/, "") # remove space
      if params.size > 0
        path = nil
        # value parameter
        if params.includes? "value="
          value = params.split("value=")[1]
          if value.size > 0
            if value[0] == '"'
              path = value.split("\"")[1]
            elsif value[0] == '{' && value.includes? "}"
              path = value[1..].split("}")[0]
            end
          end
        end

        # first parameter
        if path.nil?
          if params[0] == '"'
            path = params.split("\"")[1]
          elsif params[0] == '{' && params.includes? "}"
            path = params[1..].split("}")[0]
          end
        end

        # extract path
        if path.nil?
          # can't find path
          paths << ""
        else
          if path.size > 0 && path[0] == '"' && path.includes? ","
            # multiple path
            path.split(",").each do |each_path|
              if each_path.size > 0
                if each_path[0] == '"'
                  paths << each_path[1..-2]
                else
                  paths << ""
                end
              end
            end
          else
            # single path
            if path.size > 0 && path[0] == '"'
              path = path.split("\"")[1]
            end

            paths << path
          end
        end
      else
        # no path
        paths << ""
      end
    end

    # append slash
    (0..paths.size - 1).each do |i|
      path = paths[i]
      if path.size > 0 && !path.starts_with? "/"
        path = "/" + path
      end

      paths[i] = path
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

def analyzer_kotlin_spring(options : Hash(Symbol, String))
  instance = AnalyzerKotlinSpring.new(options)
  instance.analyze
end
