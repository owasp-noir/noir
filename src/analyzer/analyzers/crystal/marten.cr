require "../../engines/crystal_engine"

module Analyzer::Crystal
  class Marten < CrystalEngine
    @handler_callees = Hash(String, Array(Noir::CrystalCalleeExtractor::Entry)).new

    def analyze
      collect_public_dir_endpoints
      @handler_callees = include_callee? ? collect_handler_callees : Hash(String, Array(Noir::CrystalCalleeExtractor::Entry)).new

      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end

      result
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = read_source_lines(path)

      last_endpoint = Endpoint.new("", "")
      lines.each_with_index do |line, index|
        # Parse route definitions
        endpoint = line_to_endpoint(line)
        if endpoint.method != ""
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint.details = details
          attach_route_callees(endpoint, line) if include_callee?
          endpoints << endpoint
          last_endpoint = endpoint
        end

        # Parse parameter usage
        param = line_to_param(line)
        if param.name != ""
          if last_endpoint.method != ""
            last_endpoint.push_param(param)
          end
        end
      end

      endpoints
    end

    private def collect_public_dir_endpoints
      get_public_files(@base_path).each do |file|
        # Extract the path after "/public/" regardless of depth
        if file =~ /\/public\/(.*)/
          relative_path = $1
          @result << Endpoint.new("/#{relative_path}", "GET")
        end
      end
    rescue e
      logger.debug e
    end

    private def include_callee? : Bool
      any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
    end

    private def read_source_lines(path : String) : Array(String)
      read_file_content(path).lines
    end

    private def collect_handler_callees : Hash(String, Array(Noir::CrystalCalleeExtractor::Entry))
      actions = Hash(String, Array(Noir::CrystalCalleeExtractor::Entry)).new

      get_files_by_extension(".cr").each do |path|
        next if File.directory?(path)
        next unless File.exists?(path)
        next if path.includes?("lib")

        collect_handler_callees_from_lines(read_source_lines(path), path, actions)
      rescue e
        logger.debug "Error collecting Marten handler callees from #{path}: #{e}"
      end

      actions
    end

    private def collect_handler_callees_from_lines(lines : Array(String),
                                                   path : String,
                                                   actions : Hash(String, Array(Noir::CrystalCalleeExtractor::Entry)))
      scope_stack = [] of Tuple(String, String)

      lines.each_with_index do |line, index|
        stripped = Noir::CrystalCalleeExtractor.strip_comment(line).strip

        if stripped == "end" || stripped.starts_with?("end ")
          scope_stack.pop? unless scope_stack.empty?
          next
        end

        if module_match = stripped.match(/^module\s+((?:::)?[A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)\b/)
          scope_stack << {"module", qualified_crystal_const(module_match[1], scope_stack)} unless stripped.match(/\bend\b/)
          next
        end

        if class_match = stripped.match(/^class\s+((?:::)?[A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)\b/)
          scope_stack << {"class", qualified_crystal_const(class_match[1], scope_stack)} unless stripped.match(/\bend\b/)
          next
        end

        if (current_class = current_direct_crystal_class(scope_stack)) &&
           (def_match = stripped.match(/^(?:(?:private|protected)\s+)?def\s+(get)\b/))
          method_body = extract_crystal_def_block(lines, index)
          if method_body
            body, body_start_line = method_body
            callees = Noir::CrystalCalleeExtractor.callees_for_body(body, path, body_start_line)
            actions[handler_action_key(current_class, def_match[1])] = callees
          end
          scope_stack << {"block", ""} unless stripped.match(/\bend\b/)
          next
        end

        crystal_do_block_open_delta(stripped).times do
          scope_stack << {"block", ""}
        end
      end
    end

    private def attach_route_callees(endpoint : Endpoint, line : String)
      handler = extract_route_target(line)
      return unless handler

      if callees = @handler_callees[handler_action_key(handler, "get")]?
        attach_crystal_callees(endpoint, callees)
      end
    end

    private def extract_route_target(line : String) : String?
      if match = line.match(/\bpath\s+['"][^'"]+['"]\s*,\s*((?:::)?[A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)/)
        normalize_absolute_crystal_const(match[1])
      end
    end

    private def qualified_crystal_const(name : String, scope_stack : Array(Tuple(String, String))) : String
      return normalize_absolute_crystal_const(name) if name.starts_with?("::")

      prefix = current_crystal_const_scope(scope_stack)
      prefix.empty? ? name : "#{prefix}::#{name}"
    end

    private def current_crystal_const_scope(scope_stack : Array(Tuple(String, String))) : String
      scope_stack.reverse_each do |kind, name|
        return name if kind == "module" || kind == "class"
      end

      ""
    end

    private def current_direct_crystal_class(scope_stack : Array(Tuple(String, String))) : String?
      scope_stack.reverse_each do |kind, name|
        return name if kind == "class"
      end

      nil
    end

    private def normalize_absolute_crystal_const(name : String) : String
      name.starts_with?("::") ? name[2, name.size - 2] : name
    end

    private def handler_action_key(handler : String, action : String) : String
      "#{handler}##{action}"
    end

    def line_to_param(content : String) : Param
      content = Noir::CrystalCalleeExtractor.strip_comment(content)

      # Query parameters: request.query_params["param"]
      if content.includes? "request.query_params["
        param = content.split("request.query_params[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "query")
      end

      # Form/JSON data: request.data["param"]
      if content.includes? "request.data["
        param = content.split("request.data[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "form")
      end

      # Headers: request.headers["header"]
      if content.includes? "request.headers["
        param = content.split("request.headers[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "header")
      end

      # Cookies: request.cookies["cookie"]
      if content.includes? "request.cookies["
        param = content.split("request.cookies[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "cookie")
      end

      # Path parameters: params["param"]
      if content.includes? "params["
        param = content.split("params[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "path")
      end

      Param.new("", "", "")
    end

    def line_to_endpoint(content : String) : Endpoint
      content = Noir::CrystalCalleeExtractor.strip_comment(content)

      # Parse Marten route definitions: path "/route", Handler
      content.scan(/(?:^|[^.\w])path\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        if match.size > 1
          route = match[1].to_s

          # Extract HTTP methods from handler class patterns
          # For now, assume GET for routes, but could be enhanced to detect handler methods
          return Endpoint.new(route, "GET")
        end
      end

      # Parse handler method definitions for specific HTTP methods
      content.scan(/\bdef\s+(get|post|put|delete|patch|head|options)\s*/) do |match|
        if match.size > 1
          method = match[1].to_s.upcase
          # Note: For handler methods, we'd need to associate them with routes
          # This is a simplified version that just detects method handlers exist
          return Endpoint.new("", method)
        end
      end

      Endpoint.new("", "")
    end
  end
end
