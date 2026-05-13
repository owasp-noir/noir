require "../../engines/crystal_engine"

module Analyzer::Crystal
  class Grip < CrystalEngine
    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = [] of String

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        file.each_line do |line|
          lines << line
        end
      end

      include_callee = any_to_bool(@options["include_callee"]?)
      actions = include_callee ? collect_controller_actions(lines, path) : Hash(String, Array(Noir::CrystalCalleeExtractor::Entry)).new
      last_endpoint = Endpoint.new("", "")
      current_scopes = [] of String

      lines.each_with_index do |line, index|
        details = Details.new(PathInfo.new(path, index + 1))

        # Handle scope statements
        if line.includes?("scope ") && line.includes?(" do")
          scope_match = line.match(/scope\s+['"](.+?)['"]/)
          if scope_match && scope_match[1]?
            current_scopes << scope_match[1]
          end
        end

        # Handle end statements (basic detection)
        if line.strip == "end" && current_scopes.size > 0
          current_scopes.pop
        end

        # Parse HTTP method calls
        endpoint = line_to_endpoint(line, current_scopes)
        if endpoint.method != ""
          endpoint.details = details
          attach_route_callees(endpoint, line, actions) if include_callee
          endpoints << endpoint
          last_endpoint = endpoint
        end

        # Parse parameters
        param = line_to_param(line)
        if param.name != ""
          if last_endpoint.method != ""
            last_endpoint.push_param(param)
          end
        end

        # Parse WebSocket routes
        ws_endpoint = line_to_websocket(line, current_scopes)
        if ws_endpoint.url != ""
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
      %w[get post put patch delete options head].each do |method|
        if content.includes?("#{method} ") && content.includes?("\"")
          if match = content.match(/#{method}\s+['"](.+?)['"]/)
            path = match[1]
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
        if match = content.match(/ws\s+['"](.+?)['"]/)
          path = match[1]
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
