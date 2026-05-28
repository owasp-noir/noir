require "../../engines/elixir_engine"
require "../../../utils/url_path"

module Analyzer::Elixir
  class Phoenix < ElixirEngine
    alias ScopeEntry = NamedTuple(prefix: String, module_prefix: String, indent: Int32)

    # Store mapping of route -> controller/action for parameter extraction
    @route_map : Hash(String, ControllerAction) = Hash(String, ControllerAction).new

    struct ControllerAction
      property controller : String
      property action : String

      def initialize(@controller : String, @action : String)
      end
    end

    def analyze
      # First pass: collect routes via the engine's parallel file scan.
      super

      # Second pass: extract parameters from controller files
      extract_controller_params

      @result
    end

    def analyze_file(path : String) : Array(Endpoint)
      return [] of Endpoint unless File.extname(path) == ".ex"

      endpoints = [] of Endpoint
      scope_stack = [] of ScopeEntry
      in_triple_double = false
      in_triple_single = false

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        file.each_line.with_index do |line, index|
          if line.includes?("\"\"\"")
            line.scan(/"""/).size.times { in_triple_double = !in_triple_double }
            next
          end
          if line.includes?("'''")
            line.scan(/'''/).size.times { in_triple_single = !in_triple_single }
            next
          end
          next if in_triple_double || in_triple_single

          stripped = line.strip
          next if stripped.starts_with?("#")

          if !scope_stack.empty?
            if end_match = line.match(/^(\s*)end\b/)
              end_indent = end_match[1].size
              if end_indent == scope_stack.last[:indent]
                scope_stack.pop
                next
              end
            end
          end

          if match = line.match(/^(\s*)scope\s*(?:\(\s*)?["']([^"']+)["'](?:\s*,\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*))?/)
            scope_stack << {prefix: match[2], module_prefix: match[3]? || "", indent: match[1].size}
            next
          end

          scope_prefix = current_scope_prefix(scope_stack)
          scope_module = current_scope_module(scope_stack)
          line_to_endpoint(line, path, scope_prefix, scope_module).each do |endpoint|
            next if endpoint.method.empty?
            endpoint.details = Details.new(PathInfo.new(path, index + 1))
            endpoints << endpoint
          end
        end
      end
      endpoints
    end

    def extract_controller_params
      # Find all controller files and extract parameters. Pulls from the
      # detector-built file_map so subtree pruning and --exclude-path
      # apply to this pass too.
      base_dir_prefixes = base_paths.map { |bp| bp.ends_with?("/") ? bp : "#{bp}/" }
      controller_files = get_files_by_extension(".ex").select do |path|
        next false unless path.ends_with?("_controller.ex")
        base_paths.includes?(path) || base_dir_prefixes.any? { |p| path.starts_with?(p) }
      end

      controller_files.each do |controller_path|
        next unless File.exists?(controller_path)

        begin
          content = read_file_content(controller_path)
          controller_name = File.basename(controller_path, ".ex")
          controller_module = extract_controller_module(content) || controller_name

          # Extract parameters from each action in the controller
          extract_params_from_controller(content, controller_module, controller_path)
        rescue e
          logger.debug "Error reading controller file #{controller_path}: #{e}"
        end
      end
    end

    def extract_params_from_controller(content : String, controller_name : String, controller_path : String)
      lines = content.lines
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      # Find all function definitions and extract parameters
      lines.each_with_index do |line, index|
        # Match public function definitions only: def action_name(conn, _params) do
        # Exclude private functions (defp)
        next if line.match(/^\s*defp\s/)
        if match = line.match(/^\s*def\s+(\w+)\(conn,/)
          action_name = match[1]

          matching_endpoints = @result.select do |endpoint|
            should_extract_params_for_endpoint?(endpoint, controller_name, action_name)
          end
          next if matching_endpoints.empty?

          # Find the end of the function block once per controller action.
          block_end = find_function_end(lines, index)
          next if block_end == -1

          callees = include_callee ? callees_from_function_block(lines, index, block_end, controller_path) : nil

          matching_endpoints.each do |endpoint|
            append_code_path(endpoint.details, PathInfo.new(controller_path, index + 1))

            # Extract parameters from the function block
            params = extract_params_from_function_block(lines, index, block_end, endpoint.method)
            params.each { |param| endpoint.push_param(param) }

            attach_elixir_callees(endpoint, callees) if callees
          end
        end
      end
    end

    def should_extract_params_for_endpoint?(endpoint : Endpoint, controller_name : String, action_name : String) : Bool
      # Check if the endpoint's route_map entry matches this controller/action
      route_key = "#{endpoint.method}::#{endpoint.url}"
      if @route_map.has_key?(route_key)
        mapping = @route_map[route_key]
        normalized_controller = normalize_controller_ref(controller_name)
        normalized_mapping = normalize_controller_ref(mapping.controller)
        controller_matches = if mapping.controller.includes?(".")
                               normalized_controller == normalized_mapping
                             else
                               normalized_controller.split('.').last == normalized_mapping
                             end
        return controller_matches && mapping.action == action_name
      end

      # Fallback: try to match by conventional naming
      # For example, resources routes: GET /posts -> PostController.index
      false
    end

    def find_function_end(lines : Array(String), start_index : Int32) : Int32
      # Find the matching "end" for the function starting with "def"
      return -1 if start_index >= lines.size

      depth = 1
      (start_index + 1...lines.size).each do |i|
        line = lines[i].strip

        # Count keywords that increase depth (excluding 'fn' which has different end syntax)
        depth += line.scan(/\b(do|def|defp|case|cond|if|unless)\b/).size

        # Count "end" keywords that decrease depth
        depth -= line.scan(/\bend\b/).size

        return i if depth == 0
      end

      -1
    end

    def extract_params_from_function_block(lines : Array(String), start_index : Int32, end_index : Int32, method : String) : Array(Param)
      params = Array(Param).new
      seen_params = Set(String).new # Track seen params for O(1) lookup

      # Extract parameters from the function block content
      (start_index..end_index).each do |i|
        line = lines[i]

        # Extract query parameters (conn.query_params["param"])
        line.scan(/conn\.query_params\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_key = "query:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "query")
            seen_params << param_key
          end
        end

        # Extract params (could be query for GET or form for POST/PUT/PATCH)
        line.scan(/conn\.params\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_type = (method == "GET") ? "query" : "form"
          param_key = "#{param_type}:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", param_type)
            seen_params << param_key
          end
        end

        # Extract body parameters (conn.body_params["param"])
        line.scan(/conn\.body_params\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_key = "form:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "form")
            seen_params << param_key
          end
        end

        # Extract header parameters (get_req_header(conn, "header-name"))
        line.scan(/get_req_header\(conn,\s*["']([^"']+)["']\)/) do |match|
          param_name = match[1]
          param_key = "header:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "header")
            seen_params << param_key
          end
        end

        # Extract cookie parameters (conn.cookies["cookie_name"])
        line.scan(/conn\.cookies\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_key = "cookie:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "cookie")
            seen_params << param_key
          end
        end
      end

      params
    end

    private def append_code_path(details : Details, path_info : PathInfo)
      return if details.code_paths.any? { |existing| existing == path_info }
      details.add_path(path_info)
    end

    private def callees_from_function_block(lines : Array(String),
                                            start_index : Int32,
                                            end_index : Int32,
                                            controller_path : String) : Array(Noir::ElixirCalleeExtractor::Entry)
      return [] of Noir::ElixirCalleeExtractor::Entry if end_index <= start_index

      body_lines = lines[(start_index + 1)...end_index]
      return [] of Noir::ElixirCalleeExtractor::Entry if body_lines.empty?

      Noir::ElixirCalleeExtractor.callees_for_lines(body_lines, controller_path, start_index + 2)
    end

    private def extract_controller_module(content : String) : String?
      content.each_line do |line|
        if match = line.match(/^\s*defmodule\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s+do\b/)
          return match[1]
        end
      end
    end

    private def normalize_controller_ref(controller : String) : String
      normalized = controller.downcase.gsub("_controller", "controller")
      normalized.ends_with?("controller") ? normalized[0, normalized.size - "controller".size] : normalized
    end

    private def current_scope_prefix(scope_stack : Array(ScopeEntry)) : String
      prefix = ""
      scope_stack.each do |scope|
        prefix = Noir::URLPath.join(prefix, scope[:prefix])
      end
      prefix
    end

    private def current_scope_module(scope_stack : Array(ScopeEntry)) : String
      scope_module = ""
      scope_stack.each do |scope|
        module_prefix = scope[:module_prefix]
        next if module_prefix.empty?

        if scope_module.empty? || module_prefix.starts_with?("#{scope_module}.")
          scope_module = module_prefix
        else
          scope_module = "#{scope_module}.#{module_prefix}"
        end
      end
      scope_module
    end

    private def scoped_route_path(scope_prefix : String, route_path : String) : String
      Noir::URLPath.join(
        normalize_elixir_interpolation(scope_prefix),
        normalize_elixir_interpolation(route_path),
      )
    end

    # Elixir double-quoted strings interpolate `#{expr}`, and the
    # Phoenix Router DSL captures the literal characters between
    # quotes. Without normalization, `get "/api/#{@version}/items"`
    # produced URL `/api/#{@version}/items` with the `#{@…}` syntax
    # leaking into the path. Rewrite each interpolation site to a
    # `{name}` placeholder (stripping any leading `@` module-
    # attribute sigil) so the path-parameter extractor recognises
    # it and the URL template reads cleanly. Mirrors the Python
    # f-string, Ruby `#{}`, PHP `$var`, and Crystal `#{}` fixes.
    private def normalize_elixir_interpolation(path : String) : String
      path.gsub(/\#\{([^}]+)\}/) do |_|
        token = $~[1].strip.lstrip('@')
        "{#{token}}"
      end
    end

    private def scoped_controller(scope_module : String, controller : String) : String
      return controller if scope_module.empty?
      return controller if controller.starts_with?("#{scope_module}.")
      "#{scope_module}.#{controller}"
    end

    def line_to_endpoint(line : String, file_path : String, scope_prefix : String = "", scope_module : String = "") : Array(Endpoint)
      endpoints = Array(Endpoint).new

      # Standard HTTP methods - extract controller and action info
      add_standard_route(endpoints, line, "get", "GET", scope_prefix, scope_module)
      add_standard_route(endpoints, line, "post", "POST", scope_prefix, scope_module)
      add_standard_route(endpoints, line, "patch", "PATCH", scope_prefix, scope_module)
      add_standard_route(endpoints, line, "put", "PUT", scope_prefix, scope_module)
      add_standard_route(endpoints, line, "delete", "DELETE", scope_prefix, scope_module)

      # Socket routes
      line.scan(/(?:^|[^.\w])socket\s*(?:\(\s*)?['"](.+?)['"]\s*,\s*(.+?)\s*/) do |match|
        tmp = Endpoint.new(scoped_route_path(scope_prefix, match[1]), "GET")
        tmp.protocol = "ws"
        endpoints << tmp
      end

      # LiveView routes
      line.scan(/(?:^|[^.\w])live\s*(?:\(\s*)?['"](.+?)['"]\s*,\s*(.+?)\s*/) do |match|
        endpoints << Endpoint.new(scoped_route_path(scope_prefix, match[1]), "GET")
      end

      # Phoenix.LiveDashboard and forwarded plugs expose mounted HTTP surfaces.
      line.scan(/(?:^|[^.\w])live_dashboard\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        endpoints << Endpoint.new(scoped_route_path(scope_prefix, match[1]), "GET")
      end

      line.scan(/(?:^|[^.\w])forward\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        endpoints << Endpoint.new(scoped_route_path(scope_prefix, match[1]), "FORWARD")
      end

      if via_match = line.match(/(?:^|[^.\w])match\s*(?:\(\s*)?['"]([^'"]+)['"]\s*,\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*,\s*:(\w+[!?]?)[^\]]*via:\s*\[([^\]]+)\]/)
        path = scoped_route_path(scope_prefix, via_match[1])
        controller = scoped_controller(scope_module, via_match[2])
        controller_action = via_match[3]
        via_match[4].scan(/:(\w+)/) do |method_match|
          http_method = method_match[1].upcase
          @route_map["#{http_method}::#{path}"] = ControllerAction.new(controller, controller_action)
          endpoints << Endpoint.new(path, http_method)
        end
      end

      if match = line.match(/(?:^|[^.\w])match\s*(?:\(\s*)?:(\w+|\*)\s*,\s*['"]([^'"]+)['"]\s*,\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*,\s*:(\w+[!?]?)/)
        http_methods = match_route_methods(match[1])
        path = scoped_route_path(scope_prefix, match[2])
        controller = scoped_controller(scope_module, match[3])
        controller_action = match[4]
        http_methods.each do |http_method|
          @route_map["#{http_method}::#{path}"] = ControllerAction.new(controller, controller_action)
          endpoints << Endpoint.new(path, http_method)
        end
      end

      # Resources macro - generates standard REST routes
      if match = line.match(/(?:^|[^.\w])resources\s*(?:\(\s*)?['"]([^'"]+)['"]\s*,\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)(?:\s*,\s*only:\s*\[([^\]]+)\])?(?:\s*,\s*except:\s*\[([^\]]+)\])?/)
        base_path = scoped_route_path(scope_prefix, match[1])
        controller = scoped_controller(scope_module, match[2])
        only_actions = match[3]?
        except_actions = match[4]?

        if only_actions
          # Parse only: [:index, :show, :create, etc.]
          actions = only_actions.scan(/:(\w+)/).map { |m| m[1] }
        else
          # Default to all REST actions
          actions = ["index", "show", "create", "update", "delete", "new", "edit"]
        end
        if except_actions
          excluded = except_actions.scan(/:(\w+)/).map { |m| m[1] }
          actions = actions.reject { |action| excluded.includes?(action) }
        end

        actions.each do |action|
          case action
          when "index"
            endpoint = Endpoint.new(base_path, "GET")
            @route_map["GET::#{base_path}"] = ControllerAction.new(controller, "index")
            endpoints << endpoint
          when "show"
            endpoint = Endpoint.new("#{base_path}/:id", "GET")
            @route_map["GET::#{base_path}/:id"] = ControllerAction.new(controller, "show")
            endpoints << endpoint
          when "create"
            endpoint = Endpoint.new(base_path, "POST")
            @route_map["POST::#{base_path}"] = ControllerAction.new(controller, "create")
            endpoints << endpoint
          when "update"
            put_endpoint = Endpoint.new("#{base_path}/:id", "PUT")
            @route_map["PUT::#{base_path}/:id"] = ControllerAction.new(controller, "update")
            endpoints << put_endpoint

            patch_endpoint = Endpoint.new("#{base_path}/:id", "PATCH")
            @route_map["PATCH::#{base_path}/:id"] = ControllerAction.new(controller, "update")
            endpoints << patch_endpoint
          when "delete"
            endpoint = Endpoint.new("#{base_path}/:id", "DELETE")
            @route_map["DELETE::#{base_path}/:id"] = ControllerAction.new(controller, "delete")
            endpoints << endpoint
          when "new"
            endpoint = Endpoint.new("#{base_path}/new", "GET")
            @route_map["GET::#{base_path}/new"] = ControllerAction.new(controller, "new")
            endpoints << endpoint
          when "edit"
            endpoint = Endpoint.new("#{base_path}/:id/edit", "GET")
            @route_map["GET::#{base_path}/:id/edit"] = ControllerAction.new(controller, "edit")
            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    private def add_standard_route(endpoints : Array(Endpoint),
                                   line : String,
                                   route_macro : String,
                                   http_method : String,
                                   scope_prefix : String,
                                   scope_module : String)
      pattern = Regex.new("(?:^|[^.\\w])#{route_macro}\\s*(?:\\(\\s*)?['\"]([^'\"]+)['\"]\\s*,\\s*([A-Za-z_]\\w*(?:\\.[A-Za-z_]\\w*)*)\\s*,\\s*:(\\w+[!?]?)")
      line.scan(pattern) do |match|
        full_path = scoped_route_path(scope_prefix, match[1])
        endpoint = Endpoint.new(full_path, http_method)
        @route_map["#{http_method}::#{full_path}"] = ControllerAction.new(scoped_controller(scope_module, match[2]), match[3])
        endpoints << endpoint
      end
    end

    private def match_route_methods(method : String) : Array(String)
      return ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"] if method == "*"
      [method.upcase]
    end
  end
end
