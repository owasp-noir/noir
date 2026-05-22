require "../../../miniparsers/python_route_extractor"
require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"

module Analyzer::Python
  class Aiohttp < PythonEngine
    # Reference: https://docs.aiohttp.org/en/stable/web_quickstart.html
    #
    # aiohttp supports two route registration styles:
    #
    #   1. Imperative: `app.router.add_get("/path", handler)`,
    #      `app.router.add_route("GET", "/path", handler)`, etc.
    #
    #   2. RouteTableDef decorators: `@routes.get("/path")`,
    #      `@routes.route("GET", "/path")`, etc. (shape is the same as
    #      Flask/Sanic and handled by PythonRouteExtractor.)
    #
    # Handlers receive a `request` object with attributes for reading
    # inputs:
    #   request.match_info["name"] / .get("name")            → path
    #   request.rel_url.query["x"] / request.query["x"]      → query
    #   request.headers["X-Foo"] / .get("X-Foo")             → header
    #   request.cookies["sid"] / .get("sid")                 → cookie
    #   await request.json()  (optionally assigned to a var) → json
    #   await request.post()  (optionally assigned to a var) → form
    #
    # Path parameters use `{name}` in the route string and are recorded
    # as `path` params, matching Bottle / FastAPI conventions.

    HTTP_METHOD_NAMES = %w[get post put delete patch head options]

    def analyze
      handler_routes = Hash(::String, Array(Tuple(::String, ::String, Int32, ::String))).new
      # path => [{route_path, http_method, line_index, handler_name}]
      class_view_routes = Hash(::String, Array(Tuple(::String, Int32, ::String))).new
      # path => [{route_path, line_index, class_name}]

      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        base_dir_prefix = current_base_path.ends_with?("/") ? current_base_path : "#{current_base_path}/"
        python_files.each do |path|
          next unless path.starts_with?(base_dir_prefix) || path == current_base_path
          next if path.includes?("/site-packages/")
          next if PythonEngine.python_test_path?(path)
          @logger.debug "Analyzing #{path}"

          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            file_content = file.gets_to_end
            lines = file_content.lines
            next unless lines.any?(&.includes?("aiohttp"))

            import_modules = find_imported_modules(current_base_path, path, file_content)
            app_prefixes = collect_app_prefixes(lines)
            route_table_prefixes = collect_route_table_prefixes(lines, app_prefixes)
            route_list_prefixes = collect_route_list_prefixes(lines, app_prefixes)

            handler_routes[path] ||= [] of Tuple(::String, ::String, Int32, ::String)
            class_view_routes[path] ||= [] of Tuple(::String, Int32, ::String)

            # Tree-sitter pre-pass for Style B decorators. aiohttp's
            # `@routes.route("METHOD", "/path")` has a method-first signature
            # that the generic extractor would misread as path="METHOD", so
            # we skip any decoration whose attribute is literally `route`
            # and fall back to a dedicated regex below for that shape only.
            view_attributes = {"view" => "GET"}
            Noir::TreeSitterPythonRouteExtractor.extract_decorations(file_content, extra_attributes: view_attributes).each do |deco|
              next if deco.attribute_name == "route"
              prefixes = route_table_prefixes[deco.router_name]? || [""]
              if deco.attribute_name == "view"
                prefixes.each do |prefix|
                  class_view_routes[path] << {join_paths(prefix, deco.path), deco.decorator_line, deco.def_name}
                end
                next
              end

              prefixes.each do |prefix|
                deco.methods.uniq.each do |deco_method|
                  def_line = deco.def_line >= 0 ? deco.def_line : deco.decorator_line
                  next if def_line == deco.decorator_line
                  emit_endpoint(
                    path,
                    lines,
                    def_line,
                    join_paths(prefix, deco.path),
                    deco_method,
                    deco.decorator_line,
                    definition_base_path: current_base_path,
                    source: file_content
                  )
                end
              end
            end

            lines.each_with_index do |line, line_index|
              stripped = line.gsub(" ", "")

              # Style B (continued): the method-first `@<router>.route("GET", "/path")`
              # shape kept as regex because tree-sitter's generic route
              # decoder assumes path-first.
              aiohttp_route_deco = stripped.match(/@(#{PYTHON_VAR_NAME_REGEX})\.route\([rf]?['"]([A-Za-z*]+)['"]\s*,\s*[rf]?['"]([^'"]*)['"]/)
              if aiohttp_route_deco
                method = aiohttp_route_deco[2].upcase
                route_path = aiohttp_route_deco[3]
                if orig_match = line.match(/@#{aiohttp_route_deco[1]}\s*\.\s*route\s*\(\s*[rf]?['"][A-Za-z*]+['"]\s*,\s*[rf]?['"]([^'"]*)['"]/)
                  route_path = orig_match[1]
                end
                process_decorator_route(
                  path,
                  lines,
                  line_index,
                  route_path,
                  method,
                  definition_base_path: current_base_path,
                  source: file_content
                )
              end

              # Style A: app.router.add_<method>("/path", handler)
              methods_re = HTTP_METHOD_NAMES.join("|")
              if add_match = stripped.match(/(#{DOT_NATION})\.add_(#{methods_re})\([rf]?['"]([^'"]*)['"]\s*,\s*(?:handler\s*=\s*)?(#{DOT_NATION})/)
                receiver = add_match[1]
                method_name = add_match[2]
                route_path = add_match[3]
                handler_name = add_match[4]
                if orig_match = line.match(/\.add_#{method_name}\s*\(\s*[rf]?['"]([^'"]*)['"]/)
                  route_path = orig_match[1]
                end
                prefixes_for_receiver(receiver, app_prefixes).each do |prefix|
                  handler_routes[path] << {join_paths(prefix, route_path), method_name.upcase, line_index, handler_name}
                end
              end

              # Static file route:
              #   app.router.add_static("/static/", path="...")
              # aiohttp serves all files below the mounted prefix, so expose
              # it as a GET wildcard endpoint. Respect sub-app prefixes via
              # the same receiver prefix table as imperative routes.
              if static_match = stripped.match(/(#{DOT_NATION})\.add_static\([rf]?['"]([^'"]*)['"]/)
                receiver = static_match[1]
                static_path = static_match[2]
                if orig_match = line.match(/\.add_static\s*\(\s*[rf]?['"]([^'"]*)['"]/)
                  static_path = orig_match[1]
                end
                prefixes_for_receiver(receiver, app_prefixes).each do |prefix|
                  full_path = static_route_path(join_paths(prefix, static_path))
                  result << Endpoint.new(full_path, "GET", Details.new(PathInfo.new(path, line_index + 1)))
                end
              end

              # Style A: app.router.add_route("METHOD", "/path", handler)
              add_route_match = stripped.match(/(#{DOT_NATION})\.add_route\([rf]?['"]([A-Za-z*]+)['"]\s*,\s*[rf]?['"]([^'"]*)['"]\s*,\s*(?:handler\s*=\s*)?(#{DOT_NATION})/)
              if add_route_match
                receiver = add_route_match[1]
                method = add_route_match[2].upcase
                route_path = add_route_match[3]
                handler_name = add_route_match[4]
                if orig_match = line.match(/\.add_route\s*\(\s*[rf]?['"][A-Za-z*]+['"]\s*,\s*[rf]?['"]([^'"]*)['"]/)
                  route_path = orig_match[1]
                end
                prefixes_for_receiver(receiver, app_prefixes).each do |prefix|
                  handler_routes[path] << {join_paths(prefix, route_path), method, line_index, handler_name}
                end
              end

              # Style D: class-based views via
              # `app.router.add_view("/path", ViewClass)`.
              if add_view_match = stripped.match(/(#{DOT_NATION})\.add_view\([rf]?['"]([^'"]*)['"]\s*,\s*(?:handler\s*=\s*)?(#{DOT_NATION})/)
                receiver = add_view_match[1]
                route_path = add_view_match[2]
                class_name = add_view_match[3].split(".").last
                if orig_match = line.match(/\.add_view\s*\(\s*[rf]?['"]([^'"]*)['"]/)
                  route_path = orig_match[1]
                end
                prefixes_for_receiver(receiver, app_prefixes).each do |prefix|
                  class_view_routes[path] << {join_paths(prefix, route_path), line_index, class_name}
                end
              end

              # Style C: `web.<method>("/path", handler)` route entries that
              # live inside `app.add_routes([...])` lists or in a
              # standalone `routes = [...]` literal passed to
              # `app.add_routes(routes)`. The list itself doesn't need
              # tracking — every `web.<method>(...)` call only exists as a
              # route declaration in real aiohttp code. Multi-line entries
              # are coalesced by `join_until_python_call_closes` so the
              # path/handler regex sees the full call.
              if stripped.match(/\bweb\.(?:#{methods_re})\s*\(/)
                effective_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, line_index, line) : line
                effective_line.scan(/\bweb\.(#{methods_re})\s*\(\s*[rf]?['"]([^'"]*)['"]\s*,\s*(?:handler\s*=\s*)?(#{DOT_NATION})/) do |web_match|
                  next if web_match.size < 4
                  method_name = web_match[1]
                  route_path = web_match[2]
                  handler_name = web_match[3]
                  prefixes_for_add_routes_call(effective_line, app_prefixes, route_list_prefixes, line_index).each do |prefix|
                    handler_routes[path] << {join_paths(prefix, route_path), method_name.upcase, line_index, handler_name}
                  end
                end
              end

              # Style D: class-based views via `web.view("/path", ViewClass)`.
              # aiohttp dispatches to async `get` / `post` / ... methods on
              # the class, so emit one endpoint per method definition.
              if stripped.match(/\bweb\.view\s*\(/)
                effective_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, line_index, line) : line
                effective_line.scan(/\bweb\.view\s*\(\s*[rf]?['"]([^'"]*)['"]\s*,\s*(?:handler\s*=\s*)?(#{DOT_NATION})/) do |view_match|
                  next if view_match.size < 3
                  route_path = view_match[1]
                  class_name = view_match[2].split(".").last
                  prefixes_for_add_routes_call(effective_line, app_prefixes, route_list_prefixes, line_index).each do |prefix|
                    class_view_routes[path] << {join_paths(prefix, route_path), line_index, class_name}
                  end
                end
              end
            end

            # Resolve add_X handler references by finding their def lines.
            handler_routes[path].each do |route_path, method, line_index, handler_name|
              def_index = find_handler_def(lines, handler_name)
              if def_index.nil?
                if emit_external_handler_endpoint(
                     path,
                     route_path,
                     method,
                     line_index,
                     handler_name,
                     import_modules,
                     definition_base_path: current_base_path
                   )
                  next
                end

                # Handler is defined in another module (common with
                # `app.add_routes([web.get("/x", handler_from_other_file)])`).
                # Emit the endpoint anyway with path params parsed from
                # the route literal; the body-side param extraction is
                # skipped because there's no local def to walk.
                details = Details.new(PathInfo.new(path, line_index + 1))
                endpoint = Endpoint.new(route_path, method, details)
                route_path.scan(/\{(\w+)(?::[^}]+)?\}/) do |path_match|
                  endpoint.push_param(Param.new(path_match[1], "", "path"))
                end
                result << endpoint
                next
              end
              emit_endpoint(
                path,
                lines,
                def_index,
                route_path,
                method,
                line_index,
                definition_base_path: current_base_path,
                source: file_content
              )
            end

            # Resolve class-based `web.view(...)` registrations by finding
            # HTTP verb methods on the referenced `web.View` subclass.
            class_view_routes[path].each do |route_path, line_index, class_name|
              emit_class_view_endpoints(
                path,
                lines,
                route_path,
                line_index,
                class_name,
                definition_base_path: current_base_path,
                source: file_content
              )
            end
          end
        end
      end

      result
    end

    private def emit_class_view_endpoints(path : ::String,
                                          lines : Array(::String),
                                          route_path : ::String,
                                          report_line : Int32,
                                          class_name : ::String,
                                          *,
                                          definition_base_path : ::String,
                                          source : ::String)
      class_index = find_class_def(lines, class_name)
      if class_index.nil?
        details = Details.new(PathInfo.new(path, report_line + 1))
        endpoint = Endpoint.new(route_path, "GET", details)
        route_path.scan(/\{(\w+)(?::[^}]+)?\}/) do |path_match|
          endpoint.push_param(Param.new(path_match[1], "", "path"))
        end
        result << endpoint
        return
      end

      method_defs = find_class_http_method_defs(lines, class_index)
      method_defs.each do |method, method_index|
        body = extract_function_body(lines, method_index)
        request_params = extract_request_params(body, method, "self.request")
        emit_endpoint_with_params_and_callees(
          path,
          route_path,
          method,
          report_line,
          method_index + 1,
          body,
          request_params,
          definition_base_path: definition_base_path,
          source: source
        )
      end
    end

    private def process_decorator_route(path : ::String,
                                        lines : Array(::String),
                                        line_index : Int32,
                                        route_path : ::String,
                                        method : ::String,
                                        *,
                                        definition_base_path : ::String,
                                        source : ::String)
      def_index = Noir::PythonRouteExtractor.find_def_line(lines, line_index)
      return if def_index == line_index
      emit_endpoint(
        path,
        lines,
        def_index,
        route_path,
        method,
        line_index,
        definition_base_path: definition_base_path,
        source: source
      )
    end

    private def emit_endpoint(path : ::String,
                              lines : Array(::String),
                              def_index : Int32,
                              route_path : ::String,
                              method : ::String,
                              report_line : Int32,
                              *,
                              definition_base_path : ::String,
                              source : ::String)
      function_body = extract_function_body(lines, def_index)
      request_params = extract_request_params(function_body, method)

      emit_endpoint_with_params_and_callees(
        path,
        route_path,
        method,
        report_line,
        def_index + 1,
        function_body,
        request_params,
        definition_base_path: definition_base_path,
        source: source
      )
    end

    private def emit_endpoint_with_params_and_callees(path : ::String,
                                                      route_path : ::String,
                                                      method : ::String,
                                                      report_line : Int32,
                                                      body_start_line : Int32,
                                                      function_body : ::String,
                                                      request_params : Array(Param),
                                                      *,
                                                      definition_base_path : ::String,
                                                      source : ::String,
                                                      handler_path : ::String? = nil)
      seen = Set(::String).new
      all_params = [] of Param

      route_path.scan(/\{(\w+)(?::[^}]+)?\}/) do |match|
        key = "path:#{match[1]}"
        unless seen.includes?(key)
          all_params << Param.new(match[1], "", "path")
          seen << key
        end
      end

      request_params.each do |p|
        key = "#{p.param_type}:#{p.name}"
        unless seen.includes?(key)
          all_params << p
          seen << key
        end
      end

      details = Details.new(PathInfo.new(path, report_line + 1))
      endpoint = Endpoint.new(route_path, method, details)
      endpoint.protocol = "ws" if websocket_response_body?(function_body)
      all_params.each { |p| endpoint.push_param(p) }

      push_callees_from(
        endpoint,
        function_body,
        body_start_line,
        handler_path || path,
        definition_base_path: definition_base_path,
        source: source
      )

      result << endpoint
    end

    private def emit_external_handler_endpoint(path : ::String,
                                               route_path : ::String,
                                               method : ::String,
                                               report_line : Int32,
                                               handler_name : ::String,
                                               import_modules : Hash(::String, Tuple(::String, Int32)),
                                               *,
                                               definition_base_path : ::String) : Bool
      resolved = resolve_external_handler(handler_name, path, import_modules)
      return false unless resolved

      handler_path, function_name = resolved
      return false unless File.exists?(handler_path)

      handler_source = read_file_content(handler_path)
      handler_lines = handler_source.lines
      def_index = find_handler_def(handler_lines, function_name)
      return false unless def_index

      function_body = extract_function_body(handler_lines, def_index)
      request_params = extract_request_params(function_body, method)
      emit_endpoint_with_params_and_callees(
        path,
        route_path,
        method,
        report_line,
        def_index + 1,
        function_body,
        request_params,
        definition_base_path: definition_base_path,
        source: handler_source,
        handler_path: handler_path
      )

      true
    end

    private def resolve_external_handler(handler_name : ::String,
                                         current_path : ::String,
                                         import_modules : Hash(::String, Tuple(::String, Int32))) : Tuple(::String, ::String)?
      reference = handler_name.strip
      return if reference.empty?

      if reference.includes?(".")
        receiver, function_name = reference.split(".", 2)
        if import_info = import_modules[receiver]?
          import_path = import_info.first
          return {import_path, function_name} unless import_path.empty?
        end

        sibling_module_path = File.join(File.dirname(current_path), "#{receiver}.py")
        return {sibling_module_path, function_name} if File.exists?(sibling_module_path)

        return
      end

      if import_info = import_modules[reference]?
        import_path = import_info.first
        return {import_path, reference} unless import_path.empty?
      end

      nil
    end

    private def websocket_response_body?(function_body : ::String) : Bool
      function_body.includes?("WebSocketResponse")
    end

    private def find_class_def(lines : Array(::String), class_name : ::String) : Int32?
      lines.each_with_index do |line, idx|
        if line.match(/^\s*class\s+#{Regex.escape(class_name)}\s*[\(:]/)
          return idx
        end
      end
      nil
    end

    private def find_class_http_method_defs(lines : Array(::String), class_index : Int32) : Array(Tuple(::String, Int32))
      class_line = lines[class_index]
      class_indent = class_line.size - class_line.lstrip.size
      methods = [] of Tuple(::String, Int32)
      methods_re = HTTP_METHOD_NAMES.join("|")

      i = class_index + 1
      while i < lines.size
        line = lines[i]
        unless line.strip.empty?
          indent = line.size - line.lstrip.size
          break if indent <= class_indent

          if method_match = line.match(/^\s*(?:async\s+)?def\s+(#{methods_re})\s*\(/)
            methods << {method_match[1].upcase, i}
          end
        end
        i += 1
      end

      methods
    end

    private def find_handler_def(lines : Array(::String), handler_name : ::String) : Int32?
      handler_name = handler_name.split(".").last
      lines.each_with_index do |line, idx|
        if line.match(/^\s*(async\s+)?def\s+#{handler_name}\s*\(/)
          return idx
        end
      end
      nil
    end

    private def extract_function_body(lines : Array(::String), def_index : Int32) : ::String
      return "" if def_index >= lines.size
      def_line = lines[def_index]
      base_indent = def_line.size - def_line.lstrip.size

      body = [] of ::String
      i = def_index + 1
      while i < lines.size
        line = lines[i]
        if line.strip.empty?
          body << line
          i += 1
          next
        end
        current_indent = line.size - line.lstrip.size
        break if current_indent <= base_indent
        body << line
        i += 1
      end
      body.join("\n")
    end

    private def extract_methods(extra_params : ::String) : Array(::String)
      methods = [] of ::String
      if m = extra_params.match(/methods?\s*=\s*[\[\(]([^\]\)]+)[\]\)]/)
        m[1].scan(/['"]([A-Za-z]+)['"]/) do |method_match|
          methods << method_match[1].upcase
        end
      end
      methods.uniq
    end

    private def collect_app_prefixes(lines : Array(::String)) : Hash(::String, Array(::String))
      prefixes = Hash(::String, Array(::String)).new
      mounts = [] of Tuple(::String, ::String, ::String)

      lines.each_with_index do |line, index|
        stripped = line.gsub(" ", "")
        if app_match = stripped.match(/^(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:web\.)?Application\(/)
          prefixes[app_match[1]] ||= [""]
        end

        next unless line.includes?(".add_subapp(")

        effective_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
        effective_line.scan(/(#{DOT_NATION})\.add_subapp\s*\(\s*[rf]?['"]([^'"]*)['"]\s*,\s*(#{DOT_NATION})/) do |mount_match|
          next if mount_match.size < 4
          parent = normalize_receiver(mount_match[1])
          prefix = mount_match[2]
          child = normalize_receiver(mount_match[3])
          mounts << {parent, prefix, child}
          prefixes[child] ||= [] of ::String
        end
      end

      mounted_children = Set(::String).new
      mounts.each { |_, _, child| mounted_children << child }
      mounted_children.each do |child|
        prefixes[child].try(&.delete(""))
      end

      changed = true
      while changed
        changed = false
        mounts.each do |parent, mount_prefix, child|
          parent_prefixes = prefixes[parent]? || [""]
          prefixes[child] ||= [] of ::String
          parent_prefixes.each do |parent_prefix|
            child_prefix = join_paths(parent_prefix, mount_prefix)
            unless prefixes[child].includes?(child_prefix)
              prefixes[child] << child_prefix
              changed = true
            end
          end
        end
      end

      prefixes
    end

    private def collect_route_table_prefixes(lines : Array(::String),
                                             app_prefixes : Hash(::String, Array(::String))) : Hash(::String, Array(::String))
      prefixes = Hash(::String, Array(::String)).new

      lines.each_with_index do |line, index|
        next unless line.includes?(".add_routes(")

        effective_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
        effective_line.scan(/(#{DOT_NATION})\.add_routes\s*\(\s*(#{PYTHON_VAR_NAME_REGEX})/) do |routes_match|
          next if routes_match.size < 3
          receiver = routes_match[1]
          route_table = routes_match[2]
          prefixes[route_table] ||= [] of ::String
          prefixes_for_receiver(receiver, app_prefixes).each do |prefix|
            prefixes[route_table] << prefix unless prefixes[route_table].includes?(prefix)
          end
        end
      end

      prefixes
    end

    private def collect_route_list_prefixes(lines : Array(::String),
                                            app_prefixes : Hash(::String, Array(::String))) : Hash(Int32, Array(::String))
      route_list_ranges = collect_route_list_ranges(lines)
      prefixes = Hash(Int32, Array(::String)).new do |hash, key|
        hash[key] = [] of ::String
      end

      lines.each_with_index do |line, index|
        next unless line.includes?(".add_routes(")

        effective_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
        effective_line.scan(/(#{DOT_NATION})\.add_routes\s*\(\s*(#{PYTHON_VAR_NAME_REGEX})/) do |routes_match|
          next if routes_match.size < 3
          receiver = routes_match[1]
          route_list = routes_match[2]
          ranges = route_list_ranges[route_list]?
          next unless ranges

          prefixes_for_receiver(receiver, app_prefixes).each do |prefix|
            ranges.each do |range|
              (range[0]..range[1]).each do |line_index|
                prefixes[line_index] << prefix unless prefixes[line_index].includes?(prefix)
              end
            end
          end
        end
      end

      prefixes
    end

    private def collect_route_list_ranges(lines : Array(::String)) : Hash(::String, Array(Tuple(Int32, Int32)))
      ranges = Hash(::String, Array(Tuple(Int32, Int32))).new do |hash, key|
        hash[key] = [] of Tuple(Int32, Int32)
      end

      lines.each_with_index do |line, index|
        assignment_match = line.match(/^\s*(#{PYTHON_VAR_NAME_REGEX})\s*=\s*\[/)
        next unless assignment_match

        start_index = index
        end_index = index
        delta = python_bracket_delta(line)
        contains_web_route = line.includes?("web.")
        line_index = index + 1
        while line_index < lines.size && delta > 0
          next_line = lines[line_index]
          contains_web_route = true if next_line.includes?("web.")
          delta += python_bracket_delta(next_line)
          end_index = line_index
          line_index += 1
        end

        next unless contains_web_route
        ranges[assignment_match[1]] << {start_index, end_index}
      end

      ranges
    end

    private def python_bracket_delta(line : ::String) : Int32
      depth = 0
      in_quote : Char? = nil
      escaped = false

      line.each_char do |ch|
        if in_quote
          if escaped
            escaped = false
          elsif ch == '\\'
            escaped = true
          elsif ch == in_quote
            in_quote = nil
          end
          next
        end

        case ch
        when '\'', '"'
          in_quote = ch
        when '['
          depth += 1
        when ']'
          depth -= 1
        end
      end

      depth
    end

    private def prefixes_for_add_routes_call(line : ::String,
                                             app_prefixes : Hash(::String, Array(::String)),
                                             route_list_prefixes : Hash(Int32, Array(::String)),
                                             line_index : Int32) : Array(::String)
      if add_routes_match = line.match(/(#{DOT_NATION})\.add_routes\s*\(/)
        prefixes_for_receiver(add_routes_match[1], app_prefixes)
      elsif prefixes = route_list_prefixes[line_index]?
        prefixes
      else
        [""]
      end
    end

    private def prefixes_for_receiver(receiver : ::String,
                                      app_prefixes : Hash(::String, Array(::String))) : Array(::String)
      app_prefixes[normalize_receiver(receiver)]? || [""]
    end

    private def normalize_receiver(receiver : ::String) : ::String
      normalized = receiver.strip
      normalized = normalized[0...-7] if normalized.ends_with?(".router")
      normalized.split(".").last
    end

    private def join_paths(prefix : ::String, path : ::String) : ::String
      return normalize_path(path) if prefix.empty?
      return normalize_path(prefix) if path.empty?

      normalize_path("#{prefix}/#{path}")
    end

    private def static_route_path(path : ::String) : ::String
      normalized = normalize_path(path)
      normalized = normalized[0...-1] if normalized.ends_with?("/") && normalized != "/"
      normalized == "/" ? "/*" : "#{normalized}/*"
    end

    private def normalize_path(path : ::String) : ::String
      normalized = path.gsub(/\/+/, "/")
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized
    end

    DICT_ACCESSORS = {
      "headers" => "header",
      "cookies" => "cookie",
    }

    DICT_METHOD_NAMES = Set{"get", "getall", "getone", "items", "keys", "values", "pop"}

    private def extract_request_params(body : ::String, method : ::String, request_expr : ::String = "request") : Array(Param)
      params = [] of Param
      seen = Set(::String).new
      request_pattern = Regex.escape(request_expr)

      record = ->(name : ::String, type : ::String) do
        key = "#{type}:#{name}"
        unless seen.includes?(key)
          params << Param.new(name, "", type)
          seen << key
        end
      end

      # request.match_info["name"] / .get("name") — path parameter access
      body.scan(/#{request_pattern}\.match_info\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
        record.call(m[1], "path")
      end
      body.scan(/#{request_pattern}\.match_info\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
        record.call(m[1], "path")
      end

      # request.query["x"] / request.query.get("x") / request.rel_url.query[...]
      body.scan(/#{request_pattern}\.(?:rel_url\.)?query\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
        record.call(m[1], "query")
      end
      body.scan(/#{request_pattern}\.(?:rel_url\.)?query\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
        record.call(m[1], "query")
      end

      DICT_ACCESSORS.each do |accessor, param_type|
        body.scan(/#{request_pattern}\.#{accessor}\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
          record.call(m[1], param_type)
        end
        body.scan(/#{request_pattern}\.#{accessor}\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
          record.call(m[1], param_type)
        end
      end

      # JSON body: await request.json() and subsequent dict access on the returned var.
      json_vars = [] of ::String
      body.scan(/([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*await\s+#{request_pattern}\.json\s*\(/) do |m|
        json_vars << m[1]
      end

      # If request.json() is awaited at all, flag the body with a generic entry.
      if body.match(/await\s+#{request_pattern}\.json\s*\(/)
        record.call("body", "json") if json_vars.empty?
      end

      json_vars.each do |var|
        body.scan(/[^a-zA-Z_]#{var}\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
          record.call(m[1], "json")
        end
        body.scan(/[^a-zA-Z_]#{var}\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
          record.call(m[1], "json")
        end
      end

      # Form body: await request.post()
      form_vars = [] of ::String
      body.scan(/([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*await\s+#{request_pattern}\.post\s*\(/) do |m|
        form_vars << m[1]
      end

      if body.match(/await\s+#{request_pattern}\.post\s*\(/)
        record.call("body", "form") if form_vars.empty?
      end

      form_vars.each do |var|
        body.scan(/[^a-zA-Z_]#{var}\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
          record.call(m[1], "form")
        end
        body.scan(/[^a-zA-Z_]#{var}\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
          record.call(m[1], "form")
        end
      end

      params
    end
  end
end
