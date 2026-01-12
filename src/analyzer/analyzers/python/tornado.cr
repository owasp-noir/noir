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

      # Look for URL patterns in Application constructor
      i = start_index
      while i < lines.size
        line = lines[i].strip.gsub(" ", "")

        # Match URL pattern: (r"/path", HandlerClass)
        pattern_match = line.match /\(r?["']([^"']+)["'],\s*([^),]+)/
        if pattern_match
          route_path = pattern_match[1]
          handler_class = pattern_match[2]
          @routes[file_path] << {i, "ALL", route_path, handler_class}
        end

        # Stop if we reach the end of the Application constructor
        break if line.includes?(")]") || line.includes?("))")
        i += 1
      end
    end

    private def extract_endpoints_from_handler(file_path : ::String, route_path : ::String, handler_class : ::String, default_method : ::String) : Array(Endpoint)
      endpoints = [] of Endpoint

      # Find the handler class definition and extract HTTP methods
      File.open(file_path, "r", encoding: "utf-8", invalid: :skip) do |file|
        lines = file.each_line.to_a

        # Find class definition
        class_found = false
        lines.each_with_index do |line, line_index|
          if line.strip.starts_with?("class #{handler_class}")
            class_found = true
            next
          end

          next unless class_found

          # Look for HTTP method handlers
          HTTP_METHODS.each do |http_method|
            if line.strip.starts_with?("def #{http_method}(")
              # Extract parameters from this method
              params = extract_params_from_method(lines, line_index, file_path)
              endpoint = Endpoint.new(route_path, http_method.upcase, params)
              endpoints << endpoint
            end
          end

          # Stop when we reach the next class or end of current class
          if line.strip.starts_with?("class ") && !line.strip.starts_with?("class #{handler_class}")
            break
          end
        end
      end

      # If no specific HTTP methods found, create a GET endpoint
      if endpoints.empty?
        endpoint = Endpoint.new(route_path, "GET")
        endpoints << endpoint
      end

      endpoints
    end

    private def extract_params_from_method(lines : Array(::String), method_line_index : Int32, file_path : ::String) : Array(Param)
      params = [] of Param

      # Parse the method body for parameter extraction patterns
      i = method_line_index + 1
      while i < lines.size
        line = lines[i].strip

        # Stop at the next method or class
        break if line.starts_with?("def ") || line.starts_with?("class ")

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

      # JSON body parsing: tornado.escape.json_decode(self.request.body)
      if line.includes?("json_decode") && line.includes?("self.request.body")
        # This indicates JSON body usage but we can't extract specific param names statically
        params << Param.new("", "", "json")
      end
    end
  end
end
