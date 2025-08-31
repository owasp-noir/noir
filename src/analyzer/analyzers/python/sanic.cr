require "../../../models/analyzer"
require "../../../minilexers/python"
require "../../../miniparsers/python"
require "./python"

module Analyzer::Python
  class Sanic < Python
    # Reference: https://sanic.readthedocs.io/en/stable/sanic/request.html
    REQUEST_PARAM_FIELDS = {
      "args"    => {["GET"], "query"},
      "form"    => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "files"   => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "json"    => {["POST", "PUT", "PATCH", "DELETE"], "json"},
      "cookies" => {nil, "cookie"},
      "headers" => {nil, "header"},
    }

    REQUEST_PARAM_TYPES = {
      "query"  => nil,
      "form"   => ["POST", "PUT", "PATCH", "DELETE"],
      "json"   => ["POST", "PUT", "PATCH", "DELETE"],
      "cookie" => nil,
      "header" => nil,
    }

    @file_content_cache = Hash(::String, ::String).new
    @parsers = Hash(::String, PythonParser).new
    @routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String))).new

    def analyze
      sanic_instances = Hash(::String, ::String).new
      sanic_instances["app"] ||= "" # Common sanic instance name
      blueprint_prefixes = Hash(::String, ::String).new
      path_api_instances = Hash(::String, Hash(::String, ::String)).new

      # Iterate through all Python files in the base path
      Dir.glob("#{base_path}/**/*.py") do |path|
        next if File.directory?(path)
        next if path.includes?("/site-packages/")
        @logger.debug "Analyzing #{path}"

        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          lines = file.each_line.to_a
          next unless lines.any?(&.includes?("sanic"))
          api_instances = Hash(::String, ::String).new
          path_api_instances[path] = api_instances

          lines.each_with_index do |line, line_index|
            line = line.gsub(" ", "") # remove spaces for easier regex matching

            # Identify Sanic instance assignments
            sanic_match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:sanic\.)?Sanic\(/
            if sanic_match
              sanic_instance_name = sanic_match[1]
              api_instances[sanic_instance_name] ||= ""
              sanic_instances[sanic_instance_name] ||= ""
            end

            # Identify Blueprint instance assignments
            blueprint_match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:sanic\.)?Blueprint\(/
            if blueprint_match
              prefix = ""
              blueprint_instance_name = blueprint_match[1]
              param_codes = line.split("Blueprint", 2)[1]
              prefix_match = param_codes.match /url_prefix=[rf]?['"]([^'"]*)['"]/
              if !prefix_match.nil? && prefix_match.size == 2
                prefix = prefix_match[1]
              end

              blueprint_prefixes[blueprint_instance_name] ||= prefix
              api_instances[blueprint_instance_name] ||= prefix
            end

            # Identify Sanic route decorators
            line.scan(/@(#{PYTHON_VAR_NAME_REGEX})\.route\([rf]?['"]([^'"]*)['"](.*)/) do |_match|
              if _match.size > 0
                router_name = _match[1]
                route_path = _match[2]
                extra_params = _match[3]
                router_info = Tuple(Int32, ::String, ::String, ::String).new(line_index, path, route_path, extra_params)
                @routes[router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String)
                @routes[router_name] << router_info
              end
            end

            # Also detect method-specific decorators like @app.get, @app.post, etc.
            HTTP_METHODS.each do |method|
              line.scan(/@(#{PYTHON_VAR_NAME_REGEX})\.#{method.downcase}\([rf]?['"]([^'"]*)['"](.*)/) do |_match|
                if _match.size > 0
                  router_name = _match[1]
                  route_path = _match[2]
                  extra_params = "methods=['#{method.upcase}']"
                  router_info = Tuple(Int32, ::String, ::String, ::String).new(line_index, path, route_path, extra_params)
                  @routes[router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String)
                  @routes[router_name] << router_info
                end
              end
            end
          end
        end
      end

      # Iterate through the routes and extract endpoints
      @routes.each do |router_name, router_info_list|
        router_info_list.each do |router_info|
          line_index, path, route_path, extra_params = router_info
          lines = fetch_file_content(path).lines
          expect_params, class_def_index = extract_params_from_decorator(path, lines, line_index)
          api_instances = path_api_instances[path]
          if api_instances.has_key?(router_name)
            prefix = api_instances[router_name]
          else
            prefix = ""
          end

          is_class_router = false
          indent = lines[class_def_index].index("def") || 0
          unless lines[class_def_index].lstrip.starts_with?("def ") || lines[class_def_index].lstrip.starts_with?("async def ")
            if lines[class_def_index].lstrip.starts_with?("class ")
              indent = lines[class_def_index].index("class") || 0
              is_class_router = true
            else
              next # Skip if not a function and not a class
            end
          end

          i = class_def_index
          function_name_locations = Array(Tuple(Int32, ::String)).new
          while i < lines.size
            def_match = lines[i].match /(\s*)(async\s+)?def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/
            if def_match
              # Stop when the indentation is less than or equal to the class indentation
              break if is_class_router && def_match[1].size <= indent

              # Stop when the first function is found
              function_name_locations << Tuple.new(i, def_match[3])
              break unless is_class_router
            end

            # Stop when the next class definition is found
            if is_class_router && i != class_def_index
              class_match = lines[i].match /(\s*)class\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*/
              if class_match
                break if class_match[1].size <= indent
              end
            end

            i += 1
          end

          function_name_locations.each do |_class_def_index, _function_name|
            if is_class_router
              # Replace the class expect params with the function expect params
              def_expect_params, _ = extract_params_from_decorator(path, lines, _class_def_index, :up)
              if def_expect_params.size > 0
                expect_params = def_expect_params
              end
            end

            codeblock = parse_code_block(lines[_class_def_index..])
            next if codeblock.nil?
            codeblock_lines = codeblock.split("\n")

            # Get the HTTP method from the function name when it is not specified in the route decorator
            method = HTTP_METHODS.find { |http_method| _function_name.downcase == http_method.downcase } || "GET"
            get_endpoints(method, route_path, extra_params, codeblock_lines, prefix).each do |endpoint|
              details = Details.new(PathInfo.new(path, line_index + 1))
              endpoint.details = details

              # Add expect params as endpoint params
              expect_params.each do |expect_param|
                endpoint.push_param(expect_param)
              end

              result << endpoint
            end
          end
        end
      end

      result
    end

    private def fetch_file_content(path : ::String) : ::String
      unless @file_content_cache.has_key?(path)
        @file_content_cache[path] = File.read(path, encoding: "utf-8", invalid: :skip)
      end
      @file_content_cache[path]
    end

    private def extract_params_from_decorator(path : ::String, lines : Array(::String), line_index : Int32, direction : Symbol = :down) : Tuple(Array(Param), Int32)
      params = [] of Param
      found_def_index = line_index

      # Find the function definition based on direction
      if direction == :down
        i = line_index + 1
        while i < lines.size
          line_content = lines[i]
          # Skip additional decorators and empty lines
          if line_content.strip.starts_with?("@") || line_content.strip.empty?
            i += 1
            next
          end
          # Found function or class definition
          if line_content.lstrip.starts_with?("def ") || line_content.lstrip.starts_with?("async def ") || line_content.lstrip.starts_with?("class ")
            found_def_index = i
            break
          end
          # If we hit something else (not a decorator or function), stop
          break
        end
      else
        i = line_index - 1
        while i >= 0
          if lines[i].lstrip.starts_with?("def ") || lines[i].lstrip.starts_with?("async def ") || lines[i].lstrip.starts_with?("class ")
            found_def_index = i
            break
          end
          i -= 1
        end
      end

      {params, found_def_index}
    end

    private def get_endpoints(method : String, route_path : String, extra_params : String, codeblock_lines : Array(String), prefix : String = "")
      endpoints = [] of Endpoint
      params = [] of Param

      # Extract HTTP methods from extra_params
      methods = [method]
      if extra_params.includes?("methods")
        methods_match = extra_params.match /methods\s*=\s*\[([^\]]*)\]/
        if methods_match
          methods_str = methods_match[1]
          methods = methods_str.scan(/['"]([^'"]*)['"']/).map(&.[1]).map(&.upcase)
        end
      end

      # Parse the codeblock for request parameter usage
      json_variable_names = [] of String

      # First pass: identify JSON variable assignments
      codeblock_lines.each do |code_line|
        # Look for patterns like: record = request.json
        json_match = code_line.match /([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*request\.json/
        if json_match
          json_variable_names << json_match[1]
        end
      end

      # Second pass: extract parameters
      codeblock_lines.each do |code_line|
        REQUEST_PARAM_FIELDS.each do |field, (http_methods, param_type)|
          if code_line.includes?("request.#{field}")
            # Extract parameter access patterns
            param_regex = /request\.#{field}(?:\.get)?\(['"']([^'"']+)['"']\)/
            code_line.scan(param_regex) do |match|
              param_name = match[1]
              param = Param.new(param_name, "", param_type)
              params << param unless params.any? { |p| p.name == param_name && p.param_type == param_type }
            end

            # Handle bracket notation: request.args['param']
            bracket_regex = /request\.#{field}\[['"']([^'"']+)['"']\]/
            code_line.scan(bracket_regex) do |match|
              param_name = match[1]
              param = Param.new(param_name, "", param_type)
              params << param unless params.any? { |p| p.name == param_name && p.param_type == param_type }
            end
          end
        end

        # Extract JSON parameters from variable usage
        json_variable_names.each do |json_var|
          # Look for patterns like: json_var['param_name']
          bracket_regex = /#{json_var}\[['"']([^'"']+)['"']\]/
          code_line.scan(bracket_regex) do |match|
            param_name = match[1]
            param = Param.new(param_name, "", "json")
            params << param unless params.any? { |p| p.name == param_name && p.param_type == "json" }
          end

          # Look for patterns like: json_var.get('param_name')
          get_regex = /#{json_var}\.get\(['"']([^'"']+)['"']\)/
          code_line.scan(get_regex) do |match|
            param_name = match[1]
            param = Param.new(param_name, "", "json")
            params << param unless params.any? { |p| p.name == param_name && p.param_type == "json" }
          end
        end
      end

      # Create endpoints for each method
      methods.each do |http_method|
        # Create endpoint with the prefix
        full_path = prefix.empty? ? route_path : "#{prefix}#{route_path}"
        filtered_params = get_filtered_params(http_method, params.dup)
        endpoint = Endpoint.new(full_path, http_method, filtered_params)
        endpoints << endpoint
      end

      endpoints
    end

    # Filters the parameters based on the HTTP method (similar to Flask analyzer)
    private def get_filtered_params(method : String, params : Array(Param)) : Array(Param)
      filtered_params = Array(Param).new
      upper_method = method.upcase

      params.each do |param|
        is_support_param = false
        support_methods = REQUEST_PARAM_TYPES.fetch(param.param_type, nil)
        if !support_methods.nil?
          support_methods.each do |support_method|
            if upper_method == support_method.upcase
              is_support_param = true
            end
          end
        else
          is_support_param = true
        end

        filtered_params.each do |filtered_param|
          if filtered_param.name == param.name && filtered_param.param_type == param.param_type
            is_support_param = false
            break
          end
        end

        if is_support_param
          filtered_params << param
        end
      end

      filtered_params
    end

    private def parse_code_block(lines : Array(String)) : String?
      return nil if lines.empty?

      # Find the indentation of the function definition
      def_line = lines.first
      return nil unless def_line.includes?("def ")

      base_indent = def_line.index(/\S/) || 0
      codeblock_lines = [] of String

      # Add the function definition line
      codeblock_lines << def_line

      # Collect all lines that belong to this function (same or greater indentation)
      lines[1..].each do |line|
        if line.strip.empty?
          codeblock_lines << line
          next
        end

        current_indent = line.index(/\S/) || 0
        if current_indent > base_indent
          codeblock_lines << line
        else
          break
        end
      end

      codeblock_lines.join("\n")
    end
  end
end
