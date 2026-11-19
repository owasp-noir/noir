require "../../engines/python_engine"
require "../../../utils/top_level_split"
require "./starlette_endpoint_support"

module Analyzer::Python
  class Starlette < PythonEngine
    include StarletteEndpointSupport
    analyzer_for "python_starlette"

    # Route('/path', handler, methods=[...]) — captures path, and the tail
    # after the path literal so we can inspect methods= and the handler
    # reference. The tail stops at the closing paren on the same line to
    # keep the match cheap; multi-line Route() calls are still covered for
    # the common (path, handler, methods) shape.
    ROUTE_REGEX = /\b(WebSocketRoute|Route)\s*\(\s*[rf]?['"]([^'"]*)['"]([^)]*)/
    # Mount('/prefix', routes=[...]) — only the prefix literal is needed;
    # the routes list is scanned via the ongoing line loop while the mount
    # is on the paren stack. A Mount whose second argument is an app —
    # `app=sub`, a positional `sub` (both wired through MOUNT_APP_RE) or a
    # positional call such as `StaticFiles(...)` — holds no routes of its
    # own, so it must not prefix routes that merely share its line
    # (`routes=[Route("/h", h), Mount("/v2", app=sub)]`).
    MOUNT_REGEX = /Mount\s*\(\s*[rf]?['"]([^'"]*)['"](?!\s*,\s*(?:app\s*=|[A-Za-z_][\w.]*\s*[,)(]))/
    # `Mount('/p', app=sub)` or `Mount('/p', sub)`: the prefix and the
    # mounted app's name. A call (`app=StaticFiles(...)`) or a keyword in
    # the second slot (`routes=[...]`) is not an app name.
    MOUNT_APP_RE = /Mount\s*\(\s*[rf]?['"]([^'"]*)['"](?:[^)]*\bapp\s*=\s*|\s*,\s*)([a-zA-Z_][a-zA-Z0-9_]*)\b(?!\s*[(.=])/m
    # `Mount('/p', routes=[` up to the bracket opening its inline list.
    MOUNT_INLINE_HEAD_RE = /\bMount\s*\([^()\[\]]*?\broutes\s*=\s*\[/
    # `X = Starlette(` / `X = Router(` whose `routes=[...]` list is inline.
    INLINE_APP_RE        = /^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(?:Starlette|Router)\s*\(/
    INLINE_ROUTES_SUFFIX = ".routes"

    # Hoisted out of the analyze loops: an interpolated regex literal
    # recompiles (PCRE2 JIT) on every evaluation, and these interpolate
    # only constants. The `.to_s` expansion is byte-identical to the
    # previous inline form, so matching behaviour is unchanged.
    ADD_ROUTE_RE        = /(#{DOT_NATION})\.add_(websocket_)?route\s*\((.*)\)/m
    CLASS_METHOD_DEF_RE = /^\s*(?:async\s+)?def\s+(get|post|put|patch|delete|head|options)\s*\(([^)]*)\)/

    # `Mount('/p', routes=users.routes)` / `routes=imported_list` and
    # `Mount('/p', app=imported_app)`: the prefix and the reference.
    CROSS_ROUTES_MOUNT_RE = /Mount\s*\(\s*[rf]?['"]([^'"]*)['"][^()\[\]]*?\broutes\s*=\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\b(?![\w.]|\s*[(\[])/m
    CROSS_APP_MOUNT_RE    = /Mount\s*\(\s*[rf]?['"]([^'"]*)['"](?:[^()\[\]]*?\bapp\s*=\s*|\s*,\s*)([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\b(?![\w.]|\s*[(=])/m

    # Prefixes another module mounts a file's route lists and apps under:
    # {file => {list name => prefixes}} and {file => {app name => prefixes}}.
    @cross_list_prefixes = Hash(::String, Hash(::String, Array(::String))).new
    @cross_app_prefixes = Hash(::String, Hash(::String, Array(::String))).new

    def analyze
      collect_cross_module_mounts

      parallel_python_sources do |path, current_base_path|
        source = read_file_content(path)
        next unless source.includes?("starlette")

        analyze_file(path, source, current_base_path)
      end

      Fiber.yield
      result
    end

    private def analyze_file(path : ::String, source : ::String, definition_base_path : ::String)
      lines = source.split("\n")
      function_index = build_function_index(lines)
      class_index = build_class_index(lines)
      import_modules = find_imported_modules(definition_base_path, path, source)
      handler_cache = {} of ::String => Tuple(Array(Param), Array(Callee))
      external_handler_cache = {} of ::String => Tuple(Array(Param), Array(Callee))
      class_handler_cache = {} of ::String => Hash(::String, Tuple(Array(Param), Array(Callee)))
      websocket_class_handler_cache = {} of ::String => Tuple(Array(Param), Array(Callee))
      app_prefixes = build_app_prefixes(lines, @cross_app_prefixes[path]?)
      inline_route_lists = build_inline_route_list_ranges(lines)
      mounted_route_list_prefixes = build_mounted_route_list_prefixes(lines, app_prefixes, inline_route_lists, @cross_list_prefixes[path]?)
      mounted_route_list_ranges = build_mounted_route_list_ranges(lines, mounted_route_list_prefixes, inline_route_lists)
      # Stack of active Mount prefixes. Each entry stores the paren depth
      # at which the Mount was opened; when the running depth drops below
      # that value the mount has closed and its prefix must be popped.
      mount_stack = [] of Tuple(::String, Int32)
      paren_depth = 0
      in_docstring = Helper.docstring_line_flags(lines)

      lines.each_with_index do |line, line_index|
        next if in_docstring[line_index] || line.lstrip.starts_with?("#")
        # Route(...) and Mount(...) calls commonly span multiple
        # lines in real Starlette code. The line-level scan above
        # captures only the call header (`Route(`) on the first
        # line; the path string sits on a continuation line and
        # never matches the body regex. Coalesce continuation lines
        # into one logical string when the opening paren isn't
        # balanced on this line so the body capture sees the path.
        effective_line = if (line.includes?("Route") || line.includes?("Mount")) && python_paren_delta(line) > 0
                           join_until_python_call_closes(lines, line_index, line)
                         else
                           line
                         end
        # A Mount opening an inline `routes=[` list keeps only its head: the
        # nested Routes and Mounts are read on their own lines, under the
        # mount stack, so they must not be emitted here as well.
        if effective_line != line && (head = effective_line.match(MOUNT_INLINE_HEAD_RE)) && head.begin(0) == effective_line.index("Mount")
          effective_line = line.matches?(MOUNT_INLINE_HEAD_RE) ? line : head[0]
        end
        # Lift `path=` keyword to the first positional slot so the
        # existing ROUTE_REGEX (which expects a string right after
        # `Route(`) matches `Route(path="/x", endpoint=h)`.
        effective_line = effective_line.gsub(/((?:WebSocketRoute|Route)\s*\()\s*path\s*=\s*([rf]?['"][^'"]*['"])/, "\\1\\2,")

        if effective_line.includes?(".add_route(") || effective_line.includes?(".add_websocket_route(")
          effective_line.scan(ADD_ROUTE_RE) do |programmatic_match|
            next if programmatic_match.size < 4
            receiver = normalize_receiver(programmatic_match[1])
            websocket_route = !(programmatic_match[2]?).to_s.empty?
            args = split_python_arguments(programmatic_match[3])
            route_path = extract_python_keyword_string(args, "path") || args[0]?.try { |arg| Helper.extract_python_string(arg) }
            next unless route_path

            handler_expr = extract_python_keyword_expression(args, "endpoint") || args[1]?.try(&.strip)
            next unless handler_expr
            handler_ref = clean_reference(handler_expr)
            next if handler_ref.empty?
            handler_name = handler_ref.split(".").last

            methods = websocket_route ? ["GET"] : extract_programmatic_methods(args)
            methods << "GET" if methods.empty?
            route_prefixes = app_prefixes[receiver]? || [""]

            route_prefixes.each do |prefix|
              full_url = normalize_route_url(prefix, route_path)
              if websocket_route
                handler_params = [] of Param
                handler_callees = [] of Callee
                if class_index.has_key?(handler_name)
                  handler_params, handler_callees = websocket_class_handler_context_for(lines, class_index, handler_name, path, websocket_class_handler_cache,
                    definition_base_path: definition_base_path, source: source)
                else
                  handler_params, handler_callees = handler_context_for_reference(handler_ref, lines, function_index, path, import_modules, handler_cache, external_handler_cache,
                    definition_base_path: definition_base_path, source: source)
                end

                params = extract_path_params(route_path)
                handler_params.each do |p|
                  next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
                  params << p
                end
                endpoint = Endpoint.new(full_url, "GET", params, Details.new(PathInfo.new(path, line_index + 1)))
                endpoint.protocol = "ws"
                handler_callees.each { |c| endpoint.push_callee(c) }
                result << endpoint
                next
              end

              if class_index.has_key?(handler_name)
                class_contexts = class_handler_contexts(lines, class_index, handler_name, path, class_handler_cache,
                  definition_base_path: definition_base_path, source: source)
                emit_methods = methods.empty? ? class_contexts.keys : methods
                emit_methods = ["GET"] if emit_methods.empty?

                emit_methods.uniq.each do |method|
                  params = extract_path_params(route_path)
                  handler_callees = [] of Callee
                  if class_context = class_contexts[method]?
                    handler_params, handler_callees = class_context
                    handler_params.each do |p|
                      next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
                      params << p
                    end
                  end

                  endpoint = Endpoint.new(full_url, method, params, Details.new(PathInfo.new(path, line_index + 1)))
                  handler_callees.each { |c| endpoint.push_callee(c) }
                  result << endpoint
                end
              else
                handler_params, handler_callees = handler_context_for_reference(handler_ref, lines, function_index, path, import_modules, handler_cache, external_handler_cache,
                  definition_base_path: definition_base_path, source: source)
                methods.uniq.each do |method|
                  params = extract_path_params(route_path)
                  handler_params.each do |p|
                    next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
                    params << p
                  end

                  endpoint = Endpoint.new(full_url, method, params, Details.new(PathInfo.new(path, line_index + 1)))
                  handler_callees.each { |c| endpoint.push_callee(c) }
                  result << endpoint
                end
              end
            end
          end
        end

        if static_path = parse_staticfiles_mount_path(effective_line)
          route_prefixes = compose_route_prefixes(line_index, mounted_route_list_ranges, mount_stack)
          route_prefixes.each do |prefix|
            result << Endpoint.new(static_route_path(normalize_route_url(prefix, static_path)), "GET", Details.new(PathInfo.new(path, line_index + 1)))
          end
        end

        effective_line.scan(MOUNT_REGEX) do |match|
          next if match.size < 2
          mount_stack << {match[1], paren_depth + 1}
        end

        effective_line.scan(ROUTE_REGEX) do |match|
          next if match.size < 3
          route_kind = match[1]
          route_path = match[2]
          tail = match[3]
          websocket_route = route_kind == "WebSocketRoute"

          methods = [] of ::String
          methods_match = tail.match(/methods\s*=\s*\[([^\]]*)\]/)
          if methods_match
            methods_match[1].scan(/['"]([A-Za-z]+)['"]/) do |m|
              methods << m[1].upcase
            end
          end
          explicit_methods = !methods.empty?

          path_params = extract_path_params(route_path)
          route_prefixes = compose_route_prefixes(line_index, mounted_route_list_ranges, mount_stack)

          handler_params = [] of Param
          handler_callees = [] of Callee
          handler_name = nil
          handler_ref = nil
          if endpoint_keyword_match = tail.match(/endpoint\s*=\s*([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)*)/)
            handler_ref = endpoint_keyword_match[1]
            handler_name = handler_ref.split(".").last
          elsif positional_match = tail.match(/,\s*([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)*)/)
            handler_ref = positional_match[1]
            handler_name = handler_ref.split(".").last
          end

          if websocket_route
            if handler_name
              if class_index.has_key?(handler_name)
                handler_params, handler_callees = websocket_class_handler_context_for(lines, class_index, handler_name, path, websocket_class_handler_cache,
                  definition_base_path: definition_base_path, source: source)
              else
                handler_params, handler_callees = handler_context_for_reference(handler_ref || handler_name, lines, function_index, path, import_modules, handler_cache, external_handler_cache,
                  definition_base_path: definition_base_path, source: source)
              end
            end

            route_prefixes.each do |prefix|
              full_url = normalize_route_url(prefix, route_path)
              params = [] of Param
              path_params.each { |p| params << p }
              handler_params.each do |p|
                next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
                params << p
              end

              endpoint = Endpoint.new(full_url, "GET", params, Details.new(PathInfo.new(path, line_index + 1)))
              endpoint.protocol = "ws"
              handler_callees.each { |c| endpoint.push_callee(c) }
              result << endpoint
            end
            next
          end

          if handler_name && class_index.has_key?(handler_name)
            class_contexts = class_handler_contexts(lines, class_index, handler_name, path, class_handler_cache,
              definition_base_path: definition_base_path, source: source)
            class_methods = explicit_methods ? methods : class_contexts.keys
            class_methods = ["GET"] if class_methods.empty?

            route_prefixes.each do |prefix|
              full_url = normalize_route_url(prefix, route_path)
              class_methods.uniq.each do |method|
                params = [] of Param
                path_params.each { |p| params << p }

                handler_params = [] of Param
                handler_callees = [] of Callee
                if class_context = class_contexts[method]?
                  handler_params, handler_callees = class_context
                end
                handler_params.each do |p|
                  next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
                  params << p
                end

                details = Details.new(PathInfo.new(path, line_index + 1))
                endpoint = Endpoint.new(full_url, method, params, details)
                handler_callees.each { |c| endpoint.push_callee(c) }
                result << endpoint
              end
            end
            next
          end

          methods << "GET" if methods.empty?
          if handler_ref || handler_name
            handler_params, handler_callees = handler_context_for_reference(handler_ref || handler_name.to_s, lines, function_index, path, import_modules, handler_cache, external_handler_cache,
              definition_base_path: definition_base_path, source: source)
          end

          route_prefixes.each do |prefix|
            full_url = normalize_route_url(prefix, route_path)
            methods.uniq.each do |method|
              params = [] of Param
              path_params.each { |p| params << p }
              handler_params.each do |p|
                next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
                params << p
              end

              details = Details.new(PathInfo.new(path, line_index + 1))
              endpoint = Endpoint.new(full_url, method, params, details)
              handler_callees.each { |c| endpoint.push_callee(c) }
              result << endpoint
            end
          end
        end

        paren_depth += line.count('(') - line.count(')')
        paren_depth = 0 if paren_depth < 0
        while !mount_stack.empty? && mount_stack.last[1] > paren_depth
          mount_stack.pop
        end
      end
    end

    private def parse_staticfiles_mount_path(line : ::String) : ::String?
      return unless line.includes?("Mount") && line.includes?("StaticFiles")

      if match = line.match(/Mount\s*\(\s*[rf]?['"]([^'"]*)['"][^)]*?\bStaticFiles\b/m)
        return match[1]
      end

      nil
    end

    private def build_mounted_route_list_prefixes(lines : Array(::String),
                                                  app_prefixes : Hash(::String, Array(::String)),
                                                  inline_route_lists : Hash(::String, Tuple(Int32, Int32)),
                                                  seeds : Hash(::String, Array(::String))? = nil) : Hash(::String, Array(::String))
      prefixes = Hash(::String, Array(::String)).new do |hash, key|
        hash[key] = [] of ::String
      end
      seeds.try &.each { |list, list_prefixes| prefixes[list] = list_prefixes.dup }
      app_route_lists = build_app_route_lists(lines)
      inline_route_lists.each_key { |list| app_route_lists[list.rchop(INLINE_ROUTES_SUFFIX)] << list }
      route_list_ranges = build_route_list_ranges(lines).merge(inline_route_lists)
      mount_edges = [] of Tuple(::String?, ::String, ::String)

      app_route_lists.each do |app_name, route_lists|
        route_prefixes = app_prefixes[app_name]? || [""]
        route_lists.each do |route_list|
          route_prefixes.each do |prefix|
            add_route_list_prefix(prefixes, route_list, prefix)
          end
        end
      end

      lines.each_with_index do |line, line_index|
        next unless line.includes?("Mount")

        effective_line = if line.includes?("Mount") && python_paren_delta(line) > 0
                           join_until_python_call_closes(lines, line_index, line)
                         else
                           line
                         end
        parent_route_list = route_list_parent_for_line(line_index, route_list_ranges)

        effective_line.scan(/Mount\s*\(\s*[rf]?['"]([^'"]*)['"][^)]*\broutes\s*=\s*([a-zA-Z_][a-zA-Z0-9_]*)/m) do |match|
          next if match.size < 3
          mount_edges << {parent_route_list, match[2], match[1]}
        end

        effective_line.scan(MOUNT_APP_RE) do |match|
          next if match.size < 3
          mount_prefix = match[1]
          app_name = match[2]
          route_lists = app_route_lists[app_name]?
          next unless route_lists

          route_lists.each do |route_list|
            mount_edges << {parent_route_list, route_list, mount_prefix}
          end
        end
      end

      nested_edges = [] of Tuple(::String, ::String, ::String)
      mount_edges.each do |parent_route_list, route_list, mount_prefix|
        if parent_route_list
          nested_edges << {parent_route_list, mount_prefix, route_list}
        else
          add_route_list_prefix(prefixes, route_list, mount_prefix)
        end
      end

      # A list mounted into itself (`routes = [Mount('/v1', routes=routes)]`
      # rebinding the name) or an `a -> b -> a` cycle is walked once, not
      # composed forever.
      propagate_mount_prefixes(prefixes, nested_edges) { |parent_prefix, mount_prefix| normalize_route_prefix(parent_prefix, mount_prefix) }

      prefixes
    end

    # Resolve every `Mount(...)` whose `routes=` / `app=` names a list or an
    # app imported from another module into `@cross_list_prefixes` and
    # `@cross_app_prefixes`. Nodes are `"file\0list"` and `"file\0@app"`;
    # an app node mounts its own route lists with no prefix of its own.
    # ponytail: a mount nested in an inline `Mount('/a', routes=[...])`
    # does not take `/a`, and a module list mounted only through another
    # local list of a mounted module is seeded at the root.
    private def collect_cross_module_mounts : Nil
      edges = [] of Tuple(::String, ::String, ::String)
      seeds = Hash(::String, Array(::String)).new { |hash, key| hash[key] = [] of ::String }
      parents = Set(Tuple(::String, ::String)).new
      children = Set(::String).new
      app_lists = Hash(::String, Hash(::String, Array(::String))).new

      each_python_source do |path, base_path|
        source = read_file_content(path)
        next unless source.includes?("Mount") && source.includes?("starlette")
        lines = source.split("\n")
        ranges = build_route_list_ranges(lines).merge(build_inline_route_list_ranges(lines))
        local_apps = build_app_route_lists(lines)
        symbols = nil

        lines.each_with_index do |line, line_index|
          next unless line.includes?("Mount")
          call = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, line_index, line) : line
          parent = route_list_parent_for_line(line_index, ranges)
          { {CROSS_ROUTES_MOUNT_RE, false}, {CROSS_APP_MOUNT_RE, true} }.each do |regex, app_mount|
            call.scan(regex) do |match|
              # A joined call also holds the Mounts nested in it; those are
              # read on their own lines.
              next if call != line && match.begin(0) != call.index("Mount")
              prefix, reference = match[1], match[2]
              next if !reference.includes?('.') && (ranges.has_key?(reference) || local_apps.has_key?(reference))
              symbols ||= Noir::ImportGraph::Python.find_imported_symbols(base_path, path, source)
              target = imported_symbol(symbols, reference) || next
              child = if app_mount
                        app_node = "#{target[0]}\0@#{target[1]}"
                        lists = app_lists[target[0]] ||= starlette_app_route_lists(target[0])
                        lists[target[1]]?.try &.each { |list| edges << {app_node, "", "#{target[0]}\0#{list}"} }
                        app_node
                      else
                        "#{target[0]}\0#{target[1]}"
                      end
              children << child
              if parent
                edges << {"#{path}\0#{parent}", prefix, child}
                parents << {path, parent}
              else
                add_route_list_prefix(seeds, child, prefix)
              end
            end
          end
        end
      end
      return if children.empty?

      cross_apps = Hash(::String, Hash(::String, Array(::String))).new
      children.each do |node|
        file, _, name = node.partition('\0')
        (cross_apps[file] ||= Hash(::String, Array(::String)).new)[name.lchop('@')] = [] of ::String if name.starts_with?('@')
      end
      parents.each do |file, list|
        node = "#{file}\0#{list}"
        lines = read_file_content(file).split("\n")
        local = build_mounted_route_list_prefixes(lines, build_app_prefixes(lines, cross_apps[file]?), build_inline_route_list_ranges(lines))[list]?
        if local && !local.empty?
          local.each { |prefix| add_route_list_prefix(seeds, node, prefix) }
        elsif !children.includes?(node)
          add_route_list_prefix(seeds, node, "")
        end
      end

      propagate_mount_prefixes(seeds, edges) { |parent_prefix, mount_prefix| normalize_route_prefix(parent_prefix, mount_prefix) }

      children.each do |node|
        node_prefixes = seeds[node]?
        next if node_prefixes.nil? || node_prefixes.empty?
        file, _, name = node.partition('\0')
        target = name.starts_with?('@') ? @cross_app_prefixes : @cross_list_prefixes
        (target[file] ||= Hash(::String, Array(::String)).new)[name.lchop('@')] = node_prefixes
      end
    end

    # `{declaring file, declared name}` of `reference` (`name` imported by
    # name, or `module.name` through an imported module).
    private def imported_symbol(symbols : Hash(::String, Tuple(::String, ::String)), reference : ::String) : Tuple(::String, ::String)?
      if dot = reference.rindex('.')
        target = symbols[reference[0, dot]]? || return
        target[1].empty? ? {target[0], reference[(dot + 1)..]} : nil
      else
        target = symbols[reference]? || return
        target[1].empty? ? nil : target
      end
    end

    # App name -> its route lists (named, or the inline `X.routes`) in `file`.
    private def starlette_app_route_lists(file : ::String) : Hash(::String, Array(::String))
      lines = read_file_content(file).split("\n")
      lists = Hash(::String, Array(::String)).new
      build_app_route_lists(lines).each { |app, app_route_lists| lists[app] = app_route_lists.dup }
      build_inline_route_list_ranges(lines).each_key do |list|
        (lists[list.rchop(INLINE_ROUTES_SUFFIX)] ||= [] of ::String) << list
      end
      lists
    end

    private def add_route_list_prefix(prefixes : Hash(::String, Array(::String)), route_list : ::String, prefix : ::String)
      normalized = prefix.empty? ? "" : normalize_route_prefix("", prefix)
      prefixes[route_list] << normalized unless prefixes[route_list].includes?(normalized)
    end

    private def normalize_route_prefix(parent_prefix : ::String, child_prefix : ::String) : ::String
      full_prefix = "#{parent_prefix}#{child_prefix}"
      full_prefix = "/#{full_prefix}".gsub(/\/+/, "/")
      full_prefix == "/" ? "" : full_prefix
    end

    private def route_list_parent_for_line(line_index : Int32, route_list_ranges : Hash(::String, Tuple(Int32, Int32))) : ::String?
      route_list_ranges.each do |route_list, range|
        start_line, end_line = range
        return route_list if line_index >= start_line && line_index <= end_line
      end

      nil
    end

    private def build_route_list_ranges(lines : Array(::String)) : Hash(::String, Tuple(Int32, Int32))
      ranges = Hash(::String, Tuple(Int32, Int32)).new

      lines.each_with_index do |line, line_index|
        assign_match = line.match(/^\s*([a-zA-Z_][a-zA-Z0-9_]*)(?:\s*:[^=]+)?\s*=\s*\[/)
        next unless assign_match

        end_line = line_index
        bracket_depth = 0
        index = line_index
        while index < lines.size
          bracket_depth += python_bracket_delta(strip_python_comment(lines[index]))
          end_line = index
          break if bracket_depth <= 0
          index += 1
        end

        ranges[assign_match[1]] = {line_index, end_line}
      end

      ranges
    end

    private def build_app_prefixes(lines : Array(::String), cross_prefixes : Hash(::String, Array(::String))? = nil) : Hash(::String, Array(::String))
      prefixes = Hash(::String, Array(::String)).new do |hash, key|
        hash[key] = [] of ::String
      end
      mounts = [] of Tuple(::String, ::String)

      lines.each_with_index do |line, line_index|
        if app_match = line.match(/^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(?:Starlette|Router)\s*\(/)
          prefixes[app_match[1]] << "" unless prefixes[app_match[1]].includes?("")
        end

        next unless line.includes?("Mount")

        effective_line = if line.includes?("Mount") && python_paren_delta(line) > 0
                           join_until_python_call_closes(lines, line_index, line)
                         else
                           line
                         end

        effective_line.scan(MOUNT_APP_RE) do |match|
          next if match.size < 3
          mount_prefix = match[1]
          app_name = match[2]
          mounts << {mount_prefix, app_name}
          prefixes[app_name] ||= [] of ::String
        end
      end

      mounted_apps = Set(::String).new
      mounts.each { |_, app_name| mounted_apps << app_name }
      cross_prefixes.try &.each_key { |app_name| mounted_apps << app_name }
      mounted_apps.each do |app_name|
        prefixes[app_name].try(&.delete(""))
      end

      mounts.each do |mount_prefix, app_name|
        prefixes[app_name] << mount_prefix unless prefixes[app_name].includes?(mount_prefix)
      end
      cross_prefixes.try &.each do |app_name, app_mount_prefixes|
        app_mount_prefixes.each { |prefix| prefixes[app_name] << prefix unless prefixes[app_name].includes?(prefix) }
      end

      prefixes
    end

    private def build_app_route_lists(lines : Array(::String)) : Hash(::String, Array(::String))
      app_route_lists = Hash(::String, Array(::String)).new do |hash, key|
        hash[key] = [] of ::String
      end

      lines.each_with_index do |line, line_index|
        next unless line.includes?("Starlette") || line.includes?("Router")

        effective_line = if python_paren_delta(line) > 0
                           join_until_python_call_closes(lines, line_index, line)
                         else
                           line
                         end

        effective_line.scan(/^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(?:Starlette|Router)\s*\([^)]*\broutes\s*=\s*([a-zA-Z_][a-zA-Z0-9_]*)/m) do |match|
          next if match.size < 3
          app_route_lists[match[1]] << match[2]
        end
      end

      app_route_lists
    end

    # `X = Starlette(routes=[...])` / `X = Router(routes=[...])`: the inline
    # list gets the synthetic name `X.routes` (never a Python identifier,
    # so it cannot collide with a named list) and the constructor call's
    # line span, so `Mount('/v2', app=X)` prefixes it like a named list.
    private def build_inline_route_list_ranges(lines : Array(::String)) : Hash(::String, Tuple(Int32, Int32))
      ranges = Hash(::String, Tuple(Int32, Int32)).new

      lines.each_with_index do |line, line_index|
        next unless line.includes?("Starlette") || line.includes?("Router")
        next unless app_match = line.match(INLINE_APP_RE)

        end_line = line_index
        depth = python_paren_delta(line)
        # The next `X = Starlette(` statement ends an unclosed call, so a
        # run of them is walked once rather than each to the end of file.
        while depth > 0 && end_line + 1 < lines.size && !lines[end_line + 1].matches?(INLINE_APP_RE)
          end_line += 1
          depth += python_paren_delta(lines[end_line])
        end
        call = end_line == line_index ? line : lines[line_index..end_line].join(' ')
        next unless call.matches?(/\broutes\s*=\s*\[/)

        ranges["#{app_match[1]}#{INLINE_ROUTES_SUFFIX}"] = {line_index, end_line}
      end

      ranges
    end

    private def build_mounted_route_list_ranges(lines : Array(::String),
                                                mounted_route_list_prefixes : Hash(::String, Array(::String)),
                                                inline_route_lists : Hash(::String, Tuple(Int32, Int32))) : Array(Tuple(Int32, Int32, Array(::String)))
      ranges = [] of Tuple(Int32, Int32, Array(::String))
      return ranges if mounted_route_list_prefixes.empty?

      lines.each_with_index do |line, line_index|
        assign_match = line.match(/^\s*([a-zA-Z_][a-zA-Z0-9_]*)(?:\s*:[^=]+)?\s*=\s*\[/)
        next unless assign_match

        route_list_name = assign_match[1]
        prefixes = mounted_route_list_prefixes[route_list_name]?
        next unless prefixes

        end_line = line_index
        bracket_depth = 0
        index = line_index
        while index < lines.size
          bracket_depth += python_bracket_delta(strip_python_comment(lines[index]))
          end_line = index
          break if bracket_depth <= 0
          index += 1
        end

        ranges << {line_index, end_line, prefixes}
      end

      inline_route_lists.each do |route_list_name, range|
        if prefixes = mounted_route_list_prefixes[route_list_name]?
          ranges << {range[0], range[1], prefixes}
        end
      end

      ranges
    end

    private def mounted_route_prefixes_for_line(line_index : Int32,
                                                mounted_route_list_ranges : Array(Tuple(Int32, Int32, Array(::String)))) : Array(::String)?
      mounted_route_list_ranges.each do |range|
        start_line, end_line, prefixes = range
        return prefixes if line_index >= start_line && line_index <= end_line
      end

      nil
    end

    # Compose the variable-assigned route-list prefix (outer mount,
    # resolved by name) with any active inline `Mount('/x', routes=[...])`
    # on the paren stack (inner mount). A route nested in an inline Mount
    # that itself lives inside a variable-assigned list (`routes = [...,
    # Mount('/admin', routes=[Route('/x')])]; app = Starlette(routes=routes)`)
    # matches the list range, which previously short-circuited and dropped
    # the inline mount's `/admin` prefix entirely.
    private def compose_route_prefixes(line_index : Int32,
                                       mounted_route_list_ranges : Array(Tuple(Int32, Int32, Array(::String))),
                                       mount_stack : Array(Tuple(::String, Int32))) : Array(::String)
      mount_prefix = mount_stack.map(&.[0]).join
      if range_prefixes = mounted_route_prefixes_for_line(line_index, mounted_route_list_ranges)
        range_prefixes.map { |prefix| "#{prefix}#{mount_prefix}" }
      else
        [mount_prefix]
      end
    end

    private def extract_programmatic_methods(args : Array(::String)) : Array(::String)
      methods = [] of ::String
      expression = extract_python_keyword_expression(args, "methods")
      return methods unless expression

      expression.scan(/['"]([A-Za-z]+)['"]/) do |method_match|
        methods << method_match[1].upcase
      end
      methods.uniq
    end

    private def clean_reference(expression : ::String) : ::String
      reference = expression.strip
      reference = reference.split("#", 2)[0].strip
      reference = reference.split(",", 2)[0].strip
      reference.matches?(/^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*$/) ? reference : ""
    end

    private def normalize_receiver(receiver : ::String) : ::String
      receiver.strip.split(".").last
    end

    private def build_function_index(lines : Array(::String)) : Hash(::String, Tuple(Int32, ::String))
      index = {} of ::String => Tuple(Int32, ::String)
      lines.each_with_index do |line, idx|
        def_match = line.match(/def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\s*([a-zA-Z_][a-zA-Z0-9_]*)/)
        next unless def_match
        name = def_match[1]
        next if index.has_key?(name)
        index[name] = {idx, def_match[2]}
      end
      index
    end

    private def build_class_index(lines : Array(::String)) : Hash(::String, Int32)
      index = {} of ::String => Int32
      lines.each_with_index do |line, idx|
        class_match = line.match(/^\s*class\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*[\(:]/)
        next unless class_match
        index[class_match[1]] ||= idx
      end
      index
    end

    private def class_handler_contexts(lines : Array(::String),
                                       class_index : Hash(::String, Int32),
                                       handler_name : ::String,
                                       path : ::String,
                                       cache : Hash(::String, Hash(::String, Tuple(Array(Param), Array(Callee)))),
                                       *,
                                       definition_base_path : ::String,
                                       source : ::String) : Hash(::String, Tuple(Array(Param), Array(Callee)))
      cached = cache[handler_name]?
      return cached if cached

      contexts = {} of ::String => Tuple(Array(Param), Array(Callee))
      class_line = class_index[handler_name]?
      unless class_line
        cache[handler_name] = contexts
        return contexts
      end

      class_indent = lines[class_line].size - lines[class_line].lstrip.size
      i = class_line + 1
      while i < lines.size
        line = lines[i]
        unless line.strip.empty?
          indent = line.size - line.lstrip.size
          break if indent <= class_indent

          if method_match = line.match(CLASS_METHOD_DEF_RE)
            method = method_match[1].upcase
            request_name = extract_request_arg_name(method_match[2])
            request_body_res = request_name ? await_body_regexes(request_name) : nil
            codeblock = parse_code_block(lines[i..])
            if codeblock
              params = [] of Param
              fold_python_continuations(codeblock.split("\n")).each do |cl|
                if request_name && request_body_res
                  collect_request_attr_params(cl, request_name, "path_params", "path", params)
                  collect_request_attr_params(cl, request_name, "query_params", "query", params)
                  collect_request_attr_params(cl, request_name, "headers", "header", params)
                  collect_request_attr_params(cl, request_name, "cookies", "cookie", params)

                  if cl.matches?(request_body_res.json_await)
                    add_unique(params, Param.new("body", "", "json"))
                  end
                  if cl.matches?(request_body_res.form_await)
                    add_unique(params, Param.new("body", "", "form"))
                  end
                end

                collect_request_attr_params(cl, "self.request", "path_params", "path", params)
                collect_request_attr_params(cl, "self.request", "query_params", "query", params)
                collect_request_attr_params(cl, "self.request", "headers", "header", params)
                collect_request_attr_params(cl, "self.request", "cookies", "cookie", params)

                if cl.matches?(/await\s+self\.request\.json\s*\(/)
                  add_unique(params, Param.new("body", "", "json"))
                end
                if cl.matches?(/await\s+self\.request\.form\s*\(/)
                  add_unique(params, Param.new("body", "", "form"))
                end
              end
              collect_request_body_params(codeblock, request_name, params) if request_name
              collect_request_body_params(codeblock, "self.request", params)

              callees = build_callees_from(codeblock, i, path,
                definition_base_path: definition_base_path, source: source)
              contexts[method] = {params, callees}
            end
          end
        end
        i += 1
      end

      cache[handler_name] = contexts
      contexts
    end

    private def websocket_class_handler_context_for(lines : Array(::String),
                                                    class_index : Hash(::String, Int32),
                                                    handler_name : ::String,
                                                    path : ::String,
                                                    cache : Hash(::String, Tuple(Array(Param), Array(Callee))),
                                                    *,
                                                    definition_base_path : ::String,
                                                    source : ::String) : Tuple(Array(Param), Array(Callee))
      cached = cache[handler_name]?
      return cached if cached

      params = [] of Param
      callees = [] of Callee
      class_line = class_index[handler_name]?
      unless class_line
        cache[handler_name] = {params, callees}
        return cache[handler_name]
      end

      class_codeblock = parse_code_block(lines[class_line..])
      unless class_codeblock
        cache[handler_name] = {params, callees}
        return cache[handler_name]
      end

      class_codeblock.split("\n").each do |cl|
        if method_match = cl.match(/^\s*(?:async\s+)?def\s+(?:on_connect|on_receive|on_disconnect)\s*\(([^)]*)\)/)
          if request_name = extract_request_arg_name(method_match[1])
            collect_websocket_params(class_codeblock, request_name, params)
          end
        end
      end

      callees = build_callees_from(class_codeblock, class_line, path,
        definition_base_path: definition_base_path, source: source)
      cache[handler_name] = {params, callees}
      cache[handler_name]
    end

    private def handler_context_for(lines : Array(::String),
                                    function_index : Hash(::String, Tuple(Int32, ::String)),
                                    handler_name : ::String,
                                    path : ::String,
                                    cache : Hash(::String, Tuple(Array(Param), Array(Callee))),
                                    *,
                                    definition_base_path : ::String,
                                    source : ::String) : Tuple(Array(Param), Array(Callee))
      cached = cache[handler_name]?
      return cached if cached

      entry = function_index[handler_name]?
      unless entry
        cache[handler_name] = {[] of Param, [] of Callee}
        return cache[handler_name]
      end
      idx, request_name = entry

      cache[handler_name] = starlette_handler_context(lines, idx, request_name, path,
        definition_base_path: definition_base_path, source: source)
    end

    private def handler_context_for_reference(handler_ref : ::String,
                                              lines : Array(::String),
                                              function_index : Hash(::String, Tuple(Int32, ::String)),
                                              path : ::String,
                                              import_modules : Hash(::String, Tuple(::String, Int32)),
                                              cache : Hash(::String, Tuple(Array(Param), Array(Callee))),
                                              external_cache : Hash(::String, Tuple(Array(Param), Array(Callee))),
                                              *,
                                              definition_base_path : ::String,
                                              source : ::String) : Tuple(Array(Param), Array(Callee))
      clean_ref = clean_reference(handler_ref)
      return {[] of Param, [] of Callee} if clean_ref.empty?

      unless clean_ref.includes?(".")
        return handler_context_for(lines, function_index, clean_ref, path, cache,
          definition_base_path: definition_base_path, source: source)
      end

      receiver, handler_name = clean_ref.split(".", 2)
      handler_path = ""
      if import_info = import_modules[receiver]?
        handler_path = import_info.first
      end
      handler_path = File.join(File.dirname(path), "#{receiver}.py") if handler_path.empty?
      return {[] of Param, [] of Callee} unless File.exists?(handler_path)

      cache_key = "#{handler_path}:#{handler_name}"
      cached = external_cache[cache_key]?
      return cached if cached

      handler_source = read_file_content(handler_path)
      handler_lines = handler_source.split("\n")
      handler_function_index = build_function_index(handler_lines)
      context = handler_context_for(handler_lines, handler_function_index, handler_name, handler_path, {} of ::String => Tuple(Array(Param), Array(Callee)),
        definition_base_path: definition_base_path, source: handler_source)
      external_cache[cache_key] = context
      context
    end
  end
end
