require "../../engines/crystal_engine"

module Analyzer::Crystal
  class Grip < CrystalEngine
    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). The verb set is fixed, so precompile the
    # per-verb route matchers once at load time.
    VERB_ROUTE_PATTERNS = %w[get post put patch delete options head].map do |method|
      {method, /(?:^|[^.\w])#{method}\s+['"](.+?)['"]/}
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = [] of String

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        file.each_line do |line|
          lines << line
        end
      end
      lines = mask_crystal_heredocs(lines)

      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      actions = include_callee ? collect_controller_actions(lines, path) : Hash(String, Array(Noir::CrystalCalleeExtractor::Entry)).new
      last_endpoint = Endpoint.new("", "")
      scope_stack = [] of NamedTuple(prefix: String, indent: Int32)

      lines.each_with_index do |line, index|
        details = Details.new(PathInfo.new(path, index + 1))

        # Open a scope block, recording its indentation.
        if scope_match = line.match(/^(\s*)scope\s+['"](.+?)['"].*\bdo\b/)
          scope_stack << {prefix: scope_match[2], indent: scope_match[1].size}
          next
        end

        # Close the innermost scope only when an `end` lines up with the
        # indentation of the `scope ... do` that opened it; inner if/case/def/do
        # `end`s sit at a deeper indent and must not pop the scope.
        unless scope_stack.empty?
          if end_match = line.match(/^(\s*)end\b/)
            if end_match[1].size == scope_stack.last[:indent]
              scope_stack.pop
              next
            end
          end
        end

        current_scopes = scope_stack.map(&.[:prefix])

        # Parse HTTP method calls
        endpoint = line_to_endpoint(line, current_scopes)
        unless endpoint.method.empty?
          endpoint.details = details
          attach_route_callees(endpoint, line, actions) if include_callee
          endpoints << endpoint
          last_endpoint = endpoint
        end

        # Parse parameters
        param = line_to_param(line)
        unless param.name.empty?
          unless last_endpoint.method.empty?
            last_endpoint.push_param(param)
          end
        end

        # Parse WebSocket routes
        ws_endpoint = line_to_websocket(line, current_scopes)
        unless ws_endpoint.url.empty?
          ws_endpoint.details = details
          attach_websocket_callees(ws_endpoint, line, actions) if include_callee
          endpoints << ws_endpoint
        end
      end

      endpoints
    end

    private def collect_controller_actions(lines : Array(String), path : String) : Hash(String, Array(Noir::CrystalCalleeExtractor::Entry))
      actions = Hash(String, Array(Noir::CrystalCalleeExtractor::Entry)).new
      scope_stack = [] of Tuple(String, String)

      lines.each_with_index do |line, index|
        stripped = Noir::CrystalCalleeExtractor.strip_comment(line).strip

        if stripped == "end" || stripped.starts_with?("end ")
          scope_stack.pop? unless scope_stack.empty?
          next
        end

        if module_match = stripped.match(/^module\s+([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)\b/)
          scope_stack << {"module", qualified_crystal_const(module_match[1], scope_stack)}
          next
        end

        if class_match = stripped.match(/^class\s+([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)\b/)
          scope_stack << {"class", qualified_crystal_const(class_match[1], scope_stack)}
          next
        end

        if (current_class = current_direct_crystal_class(scope_stack)) &&
           (def_match = stripped.match(/^(?:(?:private|protected)\s+)?def\s+([A-Za-z_]\w*[!?=]?)/))
          method_body = extract_crystal_def_block(lines, index)
          if method_body
            body, body_start_line = method_body
            callees = Noir::CrystalCalleeExtractor.callees_for_body(body, path, body_start_line)
            actions[controller_action_key(current_class, def_match[1])] = callees
          end
          scope_stack << {"block", ""} unless stripped.match(/\bend\b/)
          next
        end

        crystal_do_block_open_delta(stripped).times do
          scope_stack << {"block", ""}
        end
      end

      actions
    end

    private def qualified_crystal_const(name : String, scope_stack : Array(Tuple(String, String))) : String
      return name if name.includes?("::")

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
      return if scope_stack.empty?
      kind, name = scope_stack.last
      return unless kind == "class"

      name
    end

    private def attach_route_callees(endpoint : Endpoint,
                                     line : String,
                                     actions : Hash(String, Array(Noir::CrystalCalleeExtractor::Entry)))
      route_target = extract_route_target(line)
      return unless route_target

      controller, action = route_target
      if callees = actions[controller_action_key(controller, action)]?
        attach_crystal_callees(endpoint, callees)
      end
    end

    private def attach_websocket_callees(endpoint : Endpoint,
                                         line : String,
                                         actions : Hash(String, Array(Noir::CrystalCalleeExtractor::Entry)))
      route_target = extract_websocket_target(line)
      return unless route_target

      controller, action = route_target
      if callees = actions[controller_action_key(controller, action)]?
        attach_crystal_callees(endpoint, callees)
      end
    end

    private def extract_route_target(line : String) : Tuple(String, String)?
      if match = line.match(/\b(get|post|put|patch|delete|options|head)\s+['"][^'"]+['"]\s*,\s*([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)(?:\s*,\s*as:\s*:(\w+))?/)
        action = match[3]? || match[1]
        {match[2], action}
      end
    end

    private def extract_websocket_target(line : String) : Tuple(String, String)?
      if match = line.match(/\bws\s+['"][^'"]+['"]\s*,\s*([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)(?:\s*,\s*as:\s*:(\w+))?/)
        {match[1], match[2]? || "on_message"}
      end
    end

    private def controller_action_key(controller : String, action : String) : String
      "#{controller}##{action}"
    end

    def line_to_param(content : String) : Param
      # Grip context parameter parsing
      if content.includes?("context.fetch_path_params")
        # Extract parameter name from context.fetch_path_params["param_name"]
        if match = content.match(/context\.fetch_path_params\["(.+?)"\]/)
          param_name = match[1]
          return Param.new(param_name, "", "path")
        end
      end

      if content.includes?("context.fetch_query_params")
        if match = content.match(/context\.fetch_query_params\["(.+?)"\]/)
          param_name = match[1]
          return Param.new(param_name, "", "query")
        end
      end

      if content.includes?("context.fetch_form_params")
        if match = content.match(/context\.fetch_form_params\["(.+?)"\]/)
          param_name = match[1]
          return Param.new(param_name, "", "form")
        end
      end

      if content.includes?("context.fetch_json_params")
        if match = content.match(/context\.fetch_json_params\["(.+?)"\]/)
          param_name = match[1]
          return Param.new(param_name, "", "json")
        end
      end

      if content.includes?("context.fetch_headers")
        if match = content.match(/context\.fetch_headers\["(.+?)"\]/)
          param_name = match[1]
          return Param.new(param_name, "", "header")
        end
      end

      if content.includes?("context.fetch_cookies")
        if match = content.match(/context\.fetch_cookies\["(.+?)"\]/)
          param_name = match[1]
          return Param.new(param_name, "", "cookie")
        end
      end

      Param.new("", "", "")
    end

    def line_to_endpoint(content : String, scopes : Array(String)) : Endpoint
      scope_prefix = scopes.join("")

      # Match HTTP method calls: get "/path", Controller
      VERB_ROUTE_PATTERNS.each do |method, route_pattern|
        if content.includes?("#{method} ") && content.includes?("\"")
          # Require a token boundary so `input "/x"` isn't read as `put "/x"`.
          if match = content.match(route_pattern)
            path = normalize_crystal_interpolation(match[1])
            full_path = scope_prefix + path
            return Endpoint.new(full_path, method.upcase)
          end
        end
      end

      Endpoint.new("", "")
    end

    def line_to_websocket(content : String, scopes : Array(String)) : Endpoint
      scope_prefix = scopes.join("")

      if content.includes?("ws ") && content.includes?("\"")
        if match = content.match(/(?:^|[^.\w])ws\s+['"](.+?)['"]/)
          path = normalize_crystal_interpolation(match[1])
          full_path = scope_prefix + path
          endpoint = Endpoint.new(full_path, "GET")
          endpoint.protocol = "ws"
          return endpoint
        end
      end

      Endpoint.new("", "")
    end
  end
end
