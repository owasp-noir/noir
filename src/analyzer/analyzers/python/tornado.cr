require "../../../models/analyzer"
require "../../../minilexers/python"
require "../../../miniparsers/python"
require "./python"

module Analyzer::Python
  class Tornado < Python
    # Reference: https://tornadoweb.org/en/stable/web.html
    # Reference: https://tornadoweb.org/en/stable/httputil.html#tornado.httputil.HTTPServerRequest
    REQUEST_PARAM_FIELDS = {
      "arguments"      => {["GET"], "query"},
      "body_arguments" => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "files"          => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "body"           => {["POST", "PUT", "PATCH", "DELETE"], "body"},
      "headers"        => {nil, "header"},
      "cookies"        => {nil, "cookie"},
    }

    REQUEST_PARAM_TYPES = {
      "query"  => nil,
      "form"   => ["POST", "PUT", "PATCH", "DELETE"],
      "body"   => ["POST", "PUT", "PATCH", "DELETE"],
      "cookie" => nil,
      "header" => nil,
    }

    @file_content_cache = Hash(::String, ::String).new
    @parsers = Hash(::String, PythonParser).new
    @routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String))).new
    @import_modules_cache = Hash(::String, Hash(::String, Tuple(::String, Int32))).new

    def analyze
      tornado_app_instances = Hash(::String, ::String).new
      tornado_app_instances["app"] ||= "" # Common tornado app instance name
      path_api_instances = Hash(::String, Hash(::String, ::String)).new

      # Iterate through all Python files in all base paths
      base_paths.each do |current_base_path|
        Dir.glob("#{escape_glob_path(current_base_path)}/**/*.py") do |path|
          next if File.directory?(path)
          next if path.includes?("/site-packages/")
          @logger.debug "Analyzing #{path}"

          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            lines = file.each_line.to_a
            next unless lines.any?(&.includes?("tornado"))
            api_instances = Hash(::String, ::String).new
            path_api_instances[path] = api_instances

            lines.each_with_index do |line, line_index|
              line = line.gsub(" ", "") # remove spaces for easier regex matching

              # Identify Tornado Application instance assignments
              app_match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:tornado\.web\.)?Application\(/
              if app_match
                app_instance_name = app_match[1]
                api_instances[app_instance_name] ||= ""
                tornado_app_instances[app_instance_name] ||= ""
              end

              # Look for URL routing patterns in tornado.web.Application
              # Pattern: [(r"/path", HandlerClass), ...]
              if line.includes?("Application(") || line.includes?("Application([")
                # Extract URL patterns from this and following lines
                extract_url_patterns_from_application(lines, line_index, path, api_instances)
              end
            end
          end
        end
      end

      result = [] of Endpoint

      # Process route handlers
      path_api_instances.each do |path, _|
        @routes[path]?.try &.each do |route_info|
          line_index, method, route_path, handler_class = route_info
          endpoints = extract_endpoints_from_handler(path, route_path, handler_class, method)
          endpoints.each do |endpoint|
            details = Details.new(PathInfo.new(path, line_index + 1))
            endpoint.details = details
            result << endpoint
          end
        end
      end

      result
    end

    private def extract_url_patterns_from_application(lines : Array(::String), start_index : Int32, file_path : ::String, api_instances : Hash(::String, ::String))
      @routes[file_path] ||= [] of Tuple(Int32, ::String, ::String, ::String)

      app_line = lines[start_index].strip.gsub(" ", "")

      # Check if Application() is called with a variable name (not an inline list)
      # e.g. Application(routes) but NOT Application([...])
      var_match = app_line.match /Application\(([a-zA-Z_][a-zA-Z0-9_]*)/
      if var_match
        var_name = var_match[1]
        # Find the variable definition in the file
        extract_routes_from_variable(lines, var_name, file_path)
        return
      end

      # Inline list: Application([(...), ...])
      extract_routes_from_lines(lines, start_index, file_path)
    end

    private def extract_routes_from_variable(lines : Array(::String), var_name : ::String, file_path : ::String)
      lines.each_with_index do |line, line_index|
        stripped = line.strip.gsub(" ", "")
        # Match: var_name = [
        if stripped.starts_with?("#{var_name}=[")
          extract_routes_from_lines(lines, line_index, file_path)
          return
        end
      end
    end

    private def extract_routes_from_lines(lines : Array(::String), start_index : Int32, file_path : ::String)
      bracket_depth = 0
      found_opening = false
      i = start_index
      while i < lines.size
        line = lines[i].strip.gsub(" ", "")

        # Track bracket depth, skipping characters inside string literals
        in_string = false
        string_char = '"'
        line.each_char do |c|
          if in_string
            in_string = false if c == string_char
          elsif c == '"' || c == '\''
            in_string = true
            string_char = c
          elsif c == '['
            bracket_depth += 1
            found_opening = true
          elsif c == ']'
            bracket_depth -= 1
          end
        end

        # Match URL pattern: (r"/path", HandlerClass)
        pattern_match = line.match /\(r?["']([^"']+)["'],\s*([^),]+)/
        if pattern_match
          route_path = pattern_match[1]
          handler_class = pattern_match[2]
          @routes[file_path] << {i, "ALL", route_path, handler_class}
        end

        # Stop when bracket depth returns to 0 (end of the list)
        break if found_opening && bracket_depth <= 0
        i += 1
      end
    end

    private def extract_endpoints_from_handler(file_path : ::String, route_path : ::String, handler_class : ::String, default_method : ::String) : Array(Endpoint)
      endpoints = [] of Endpoint

      # First try to find the handler class in the application file
      found = extract_endpoints_from_class_in_file(file_path, route_path, handler_class, endpoints)

      # If not found locally, resolve imports
      unless found
        import_map = resolve_imports(file_path)
        if import_map.has_key?(handler_class)
          resolved_path, _ = import_map[handler_class]
          if File.exists?(resolved_path)
            extract_endpoints_from_class_in_file(resolved_path, route_path, handler_class, endpoints)
          end
        end
      end

      # Only fall back to default GET if handler was not found anywhere
      if endpoints.empty?
        endpoint = Endpoint.new(route_path, "GET")
        endpoints << endpoint
      end

      endpoints
    end

    private def extract_endpoints_from_class_in_file(file_path : ::String, route_path : ::String, handler_class : ::String, endpoints : Array(Endpoint)) : Bool
      lines = read_file_lines(file_path)

      class_found = false
      lines.each_with_index do |line, line_index|
        if line.strip.starts_with?("class #{handler_class}")
          class_found = true
          next
        end

        next unless class_found

        # Look for HTTP method handlers (both sync and async)
        HTTP_METHODS.each do |http_method|
          stripped = line.strip
          if stripped.starts_with?("def #{http_method}(") || stripped.starts_with?("async def #{http_method}(")
            params = extract_params_from_method(lines, line_index, file_path)
            endpoint = Endpoint.new(route_path, http_method.upcase, params)
            endpoints << endpoint
          end
        end

        # Stop when we reach the next class
        if line.strip.starts_with?("class ") && !line.strip.starts_with?("class #{handler_class}")
          break
        end
      end

      class_found
    end

    private def resolve_imports(file_path : ::String) : Hash(::String, Tuple(::String, Int32))
      return @import_modules_cache[file_path] if @import_modules_cache.has_key?(file_path)
      content = read_file_content(file_path)
      import_map = find_imported_modules(base_paths[0], file_path, content)
      @import_modules_cache[file_path] = import_map
      import_map
    end

    private def read_file_lines(file_path : ::String) : Array(::String)
      content = read_file_content(file_path)
      content.split("\n")
    end

    private def read_file_content(file_path : ::String) : ::String
      return @file_content_cache[file_path] if @file_content_cache.has_key?(file_path)
      content = File.read(file_path, encoding: "utf-8", invalid: :skip)
      @file_content_cache[file_path] = content
      content
    end

    private def extract_params_from_method(lines : Array(::String), method_line_index : Int32, file_path : ::String) : Array(Param)
      params = [] of Param

      # Parse the method body for parameter extraction patterns
      i = method_line_index + 1
      while i < lines.size
        line = lines[i].strip

        # Stop at the next method or class
        break if line.starts_with?("def ") || line.starts_with?("async def ") || line.starts_with?("class ")

        # Extract Tornado parameter patterns
        extract_tornado_params(line, params)

        i += 1
      end

      params
    end

    private def extract_tornado_params(line : ::String, params : Array(Param))
      # self.get_argument("param_name")
      if match = line.match /self\.get_argument\(["']([^"']+)["']/
        param_name = match[1]
        params << Param.new(param_name, "", "query")
      end

      # self.get_body_argument("param_name")
      if match = line.match /self\.get_body_argument\(["']([^"']+)["']/
        param_name = match[1]
        params << Param.new(param_name, "", "form")
      end

      # self.get_cookie("cookie_name")
      if match = line.match /self\.get_cookie\(["']([^"']+)["']/
        param_name = match[1]
        params << Param.new(param_name, "", "cookie")
      end

      # self.request.headers.get("header_name")
      if match = line.match /self\.request\.headers\.get\(["']([^"']+)["']/
        param_name = match[1]
        params << Param.new(param_name, "", "header")
      end

      # self.get_arguments("param_name") — plural form for multi-value query params
      if match = line.match /self\.get_arguments\(["']([^"']+)["']/
        param_name = match[1]
        params << Param.new(param_name, "", "query")
      end

      # JSON body parsing: tornado.escape.json_decode(self.request.body)
      if line.includes?("json_decode") && line.includes?("self.request.body")
        params << Param.new("", "", "json")
      end

      # JSON body parsing: json.loads(self.request.body)
      if line.includes?("json.loads") && line.includes?("self.request.body")
        params << Param.new("", "", "json")
      end
    end
  end
end
