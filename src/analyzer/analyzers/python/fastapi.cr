require "../../engines/python_engine"

module Analyzer::Python
  class FastAPI < PythonEngine
    PATH_PARAM_REGEX       = /\{(#{PYTHON_VAR_NAME_REGEX})(?::[a-zA-Z_][a-zA-Z0-9_]*)?\}/
    TYPED_PATH_PARAM_REGEX = /\{(#{PYTHON_VAR_NAME_REGEX}):[a-zA-Z_][a-zA-Z0-9_]*\}/

    # Constant-only matchers hoisted out of the per-line analyze loops so
    # they aren't recompiled (Crystal rebuilds an interpolated regex
    # literal on every evaluation). The `.to_s` expansion of the
    # interpolated constants is byte-identical to the previous inline form.
    FASTAPI_INSTANCE_RE   = /(#{PYTHON_VAR_NAME_REGEX})(?::#{DOT_NATION})?=(?:fastapi\.)?FastAPI\(/
    APIROUTER_INSTANCE_RE = /(#{PYTHON_VAR_NAME_REGEX})(?::#{DOT_NATION})?=(?:fastapi\.)?APIRouter\(/
    VAR_NAME_FULL_RE      = /^#{PYTHON_VAR_NAME_REGEX}$/
    HANDLER_CALL_RE       = /^(#{PYTHON_VAR_NAME_REGEX}(?:\.#{PYTHON_VAR_NAME_REGEX})?)\s*\(/
    HANDLER_REF_RE        = /^#{PYTHON_VAR_NAME_REGEX}(?:\.#{PYTHON_VAR_NAME_REGEX})?$/

    # Route-registration matchers that interpolate a discovered instance
    # name (`app`, `router`, ...) — they can't be class constants, but a
    # project only uses a handful of distinct names, so the compiled set
    # is memoized per name instead of rebuilt on every line.
    private record InstanceRegexes,
      include_router_guard : Regex,
      include_router_call : Regex,
      route_decorator : Regex,
      programmatic_route : Regex,
      programmatic_guard : Regex,
      static_mount : Regex,
      mount_guard : Regex,
      decorator_guard : Regex

    @instance_regex_cache = Hash(::String, InstanceRegexes).new

    private def instance_regexes(instance_name : ::String) : InstanceRegexes
      @instance_regex_cache[instance_name] ||= begin
        e = Regex.escape(instance_name)
        InstanceRegexes.new(
          include_router_guard: /\b#{e}\s*\.\s*include_router\s*\(/,
          include_router_call: /\b#{e}\s*\.\s*include_router\s*\((.*)\)\s*(?:#.*)?$/m,
          route_decorator: /^\s*@\s*#{e}\s*\.\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\((.*)\)\s*(?:#.*)?$/m,
          programmatic_route: /\b#{e}\s*\.\s*(add_api_route|add_api_websocket_route)\s*\((.*)\)\s*(?:#.*)?$/m,
          programmatic_guard: /\b#{e}\s*\.\s*(add_api_route|add_api_websocket_route)\s*\(/,
          static_mount: /\b#{e}\s*\.\s*mount\s*\((.*)\)\s*(?:#.*)?$/m,
          mount_guard: /\b#{e}\s*\.\s*mount\s*\(/,
          decorator_guard: /^\s*@\s*#{e}\s*\.\s*[a-zA-Z_]+\s*\(/,
        )
      end
    end

    @fastapi_import_cache = Hash(::String, Hash(::String, Tuple(::String, Int32))).new

    def analyze
      include_router_map = Hash(::String, Hash(::String, Router)).new
      fastapi_app_instances = [] of Tuple(::String, ::String)

      begin
        # Iterate through all Python files in all base paths. Pulls from
        # the detector-built file_map so subtree pruning and
        # --exclude-path apply to this pass too.
        python_files = get_files_by_extension(".py")
        base_paths.each do |current_base_path|
          python_files.each do |path|
            next unless path_under_root?(path, current_base_path)
            next if path.includes?("/site-packages/")
            next if python_test_path?(path)
            source = read_file_content(path)

            import_modules = find_fastapi_imported_modules(current_base_path, path, source)
            codelines = source.split("\n")
            codelines.each_with_index do |original_line, index|
              next if original_line.lstrip.starts_with?("#")

              effective_line = coalesce_constructor_call(codelines, index, original_line, "APIRouter")
              line = effective_line.gsub(" ", "")
              match = line.includes?("FastAPI(") ? line.match(FASTAPI_INSTANCE_RE) : nil
              unless match.nil?
                fastapi_instance_name = match[1]
                if include_router_map.has_key?(path)
                  include_router_map[path][fastapi_instance_name] ||= Router.new("")
                else
                  include_router_map[path] = {fastapi_instance_name => Router.new("")}
                end

                # Record every FastAPI app instance as a routing root.
                # A single project frequently mounts several apps
                # (`app`, `api`, `frontend` in Netflix/dispatch) and a
                # stray `app = FastAPI()` may even live in a deep helper
                # module — seeding prefix configuration from ALL of
                # them (below) keeps that helper's instance from
                # hijacking the one true base file.
                #
                # Don't `break` — a single file can declare both
                # `app = FastAPI()` and one or more
                # `router = APIRouter(prefix="/api")` instances, and the
                # APIRouter detection further down must still run on the
                # remaining lines.
                app_key = {path, fastapi_instance_name}
                fastapi_app_instances << app_key unless fastapi_app_instances.includes?(app_key)
              end

              # https://fastapi.tiangolo.com/tutorial/bigger-applications/
              match = line.includes?("APIRouter(") ? line.match(APIROUTER_INSTANCE_RE) : nil
              unless match.nil?
                prefix = ""
                router_instance_name = match[1]
                if param_codes = effective_line.split("APIRouter", 2)[1]?
                  if raw_prefix = extract_python_keyword_expression(param_codes, "prefix")
                    prefix = resolve_string_expression(raw_prefix, source, import_modules) || ""
                  end
                end

                if include_router_map.has_key?(path)
                  include_router_map[path][router_instance_name] = Router.new(prefix)
                else
                  include_router_map[path] = {router_instance_name => Router.new(prefix)}
                end
              end
            end
          end
        end
      rescue e : Exception
        logger.debug e.message
      end

      fastapi_base_paths = fastapi_project_roots(fastapi_app_instances)

      begin
        # Seed prefix configuration from every FastAPI app instance,
        # sharing one `visited` set so a router included by more than
        # one app is configured exactly once.
        prefix_visited = Set(::String).new
        fastapi_app_instances.each do |app_file, app_instance|
          app_base_path = fastapi_base_path_for(app_file, fastapi_base_paths)
          configure_router_prefix(app_file, include_router_map, app_base_path, "", app_instance, prefix_visited)
        end

        include_router_map.each do |path, router_map|
          source = read_file_content(path)
          import_base_path = fastapi_base_path_for(path, fastapi_base_paths)
          definition_base_path = python_base_path_for(path)
          import_modules = find_fastapi_imported_modules(import_base_path, path, source)
          codelines = source.split("\n")
          router_map.each do |instance_name, router_class|
            codelines.each_with_index do |line, index|
              next if line.lstrip.starts_with?("#")

              # FastAPI route decorators routinely span multiple
              # lines:
              #
              #   @app.post(
              #     "/items",
              #     response_model=Item,
              #     tags=["items"],
              #   )
              #
              # Join continuation lines onto the decorator line so the
              # single-line regex below sees the full call shape. The
              # `index` still points at the original decorator line so
              # `find_def_line` / `parse_function_def` / `code_paths`
              # stay aligned with the source.
              effective_line = coalesce_decorator_call(codelines, index, line, instance_name)

              if route_call = parse_fastapi_route_decorator(effective_line, instance_name, source, import_modules)
                route_attr, http_route_path, _extra_params = route_call
                http_method_name = route_attr.downcase
                websocket_route = http_method_name == "websocket"
                if http_method_name.in?(%w[websocket route api_route])
                  http_method_name = "GET"
                elsif !HTTP_METHODS.includes?(http_method_name)
                  next
                end

                http_method_name = http_method_name.upcase

                params = [] of Param

                # Get path params from route path
                query_params = [] of ::String
                query_params.concat(fastapi_path_param_names(http_route_path))

                # Resolve the actual `def` line, skipping stacked
                # decorators / comments / blank lines between the
                # route decorator and the handler. Both param
                # extraction and callee extraction below need this
                # to be accurate; the previous `index + 1` shortcut
                # silently misfired on `@app.post(...)` + `@auth_required`
                # style stacks.
                def_line = find_def_line(codelines, index) || (index + 1)

                # Parsing extra params
                function_definition = parse_function_def(codelines, def_line)
                unless function_definition.nil?
                  function_params = function_definition.params
                  if function_params.size > 0
                    function_params.each do |param|
                      # https://fastapi.tiangolo.com/tutorial/path-params-numeric-validations/#order-the-parameters-as-you-need-tricks
                      next if param.name == "*"
                      next if param.name.in?(%w[self cls])
                      next if param.type == "WebSocket"
                      next if fastapi_dependency_param?(param)

                      unless query_params.includes?(param.name)
                        # Default value is numeric or string only
                        default_value = return_literal_value(param.default)

                        # Get param type by default value first
                        param_type = infer_parameter_type(param.default) unless param.default.empty?

                        # Get param type by type if not found
                        if param_type.nil? && !param.type.empty?
                          param_type = param.type
                          # https://peps.python.org/pep-0593/
                          param_type = param_type.split("Annotated[", 2)[-1].split(",", 2)[-1] if param_type.includes?("Annotated[")

                          # https://peps.python.org/pep-0484/#union-types
                          param_type = param_type.split("Union[", 2)[-1] if param_type.includes?("Union[")

                          param_type = infer_parameter_type(param_type, true)
                          param_type = "query" if param_type.nil? && param.type.empty?
                        else
                          param_type = "query" if param_type.nil?
                        end

                        if param_type.nil?
                          if VAR_NAME_FULL_RE.match(param.type)
                            if param.type.in?(%w[Request dict])
                              function_codeblock = parse_code_block(codelines[def_line..])
                              next if function_codeblock.nil?
                              new_params = find_dictionary_params(function_codeblock, param)
                            elsif import_modules.has_key?(param.type)
                              # Parse model class from module path
                              import_module_path = import_modules[param.type].first

                              # Skip if import module path is not identified
                              next if import_module_path.empty?

                              import_module_source = read_file_content(import_module_path)
                              new_params = find_base_model_params(import_module_source, param.type, param.name)
                            else
                              # Parse model class from current source
                              new_params = find_base_model_params(source, param.type, param.name)
                            end

                            next if new_params.nil?

                            new_params.each do |model_param|
                              params << model_param
                            end
                          end
                        else
                          # Add endpoint param
                          params << Param.new(param.name, default_value, param_type)
                        end
                      end
                    end
                  end
                end

                # Honor `methods=[...]` on `@router.route(...)` /
                # `@router.api_route(...)` decorators by emitting
                # one endpoint per declared method. Without this
                # the decorator's method-list was discarded and a
                # single GET endpoint was produced for what may be
                # a multi-verb handler.
                declared_methods = extract_declared_methods(_extra_params)
                emit_methods = declared_methods.empty? ? [http_method_name] : declared_methods

                details = Details.new(PathInfo.new(path, index + 1))
                full_path = normalize_fastapi_path_params(router_class.join(http_route_path))
                base_endpoint = Endpoint.new(full_path, emit_methods.first, params, details)
                base_endpoint.protocol = "ws" if websocket_route

                # `parse_code_block(codelines[def_line..])` keeps the
                # def line, so body row 0 lives at file line `def_line`.
                handler_codeblock = parse_code_block(codelines[def_line..])
                if handler_codeblock
                  push_callees_from(
                    base_endpoint,
                    handler_codeblock,
                    def_line,
                    path,
                    definition_base_path: definition_base_path,
                    source: source
                  )
                end

                emit_methods.each do |method|
                  endpoint_to_add = if method == emit_methods.first
                                      base_endpoint
                                    else
                                      Endpoint.new(full_path, method, params, details).tap do |dup_ep|
                                        dup_ep.protocol = "ws" if websocket_route
                                        base_endpoint.callees.each { |c| dup_ep.push_callee(c) }
                                      end
                                    end
                  result << endpoint_to_add
                end
              end

              # Programmatic registration:
              # `app.add_api_route("/x", get_handler, methods=["GET"])`
              # / `app.add_api_websocket_route(...)`. Coalesce the
              # call's continuation lines (same way as the decorator
              # form above), parse path + methods, and emit endpoints
              # without trying to find a handler def — the handler is
              # passed by reference as the 2nd positional argument.
              prog_line = coalesce_programmatic_call(codelines, index, line, instance_name)
              if prog_call = parse_fastapi_programmatic_route(prog_line, instance_name, source, import_modules)
                prog_attr, prog_path, prog_tail = prog_call
                prog_websocket_route = prog_attr.includes?("websocket")
                prog_methods = extract_declared_methods(prog_tail)
                if prog_methods.empty?
                  prog_methods = prog_websocket_route ? ["GET"] : ["GET"]
                end
                prog_full = normalize_fastapi_path_params(router_class.join(prog_path))
                prog_details = Details.new(PathInfo.new(path, index + 1))
                prog_params = [] of Param
                prog_callees = [] of Callee
                if callees_needed?
                  if handler_callee = extract_programmatic_handler_callee(prog_tail)
                    prog_callees << Callee.new(handler_callee, path, index + 1)
                  end
                end
                if handler = resolve_programmatic_handler(prog_tail, path, source, import_modules)
                  handler_path, handler_name = handler
                  handler_source = handler_path == path ? source : read_file_content(handler_path)
                  handler_lines = handler_source.split("\n")
                  handler_imports = handler_path == path ? import_modules : find_fastapi_imported_modules(import_base_path, handler_path, handler_source)
                  if handler_def_line = find_function_def_line(handler_lines, handler_name)
                    prog_params = extract_fastapi_handler_params(handler_lines, handler_def_line, prog_full, handler_source, handler_imports)
                    if handler_codeblock = parse_code_block(handler_lines[handler_def_line..])
                      prog_callees.concat(build_callees_from(
                        handler_codeblock,
                        handler_def_line,
                        handler_path,
                        definition_base_path: definition_base_path,
                        source: handler_source
                      ))
                    end
                  end
                end
                prog_methods.each do |m|
                  endpoint = Endpoint.new(prog_full, m, prog_params, prog_details)
                  endpoint.protocol = "ws" if prog_websocket_route
                  prog_callees.each { |c| endpoint.push_callee(c) }
                  result << endpoint
                end
              end

              mount_line = coalesce_mount_call(codelines, index, line, instance_name)
              if static_mount_path = parse_fastapi_static_mount(mount_line, instance_name, source, import_modules)
                result << Endpoint.new(static_route_path(router_class.join(static_mount_path)), "GET", Details.new(PathInfo.new(path, index + 1)))
              end
            end
          end
        rescue e : Exception
          logger.debug e.message
        end
      end
      Fiber.yield

      result
    end

    # Concatenate two URL-prefix segments, normalising the
    # boundary so `combine_router_prefixes("/api/v1", "/users")`
    # gives `/api/v1/users` and `combine_router_prefixes("",
    # "/users")` gives `/users`. Trailing slashes are dropped on
    # the parent so we don't end up with `/api/v1//users`.
    private def combine_router_prefixes(parent : ::String, own : ::String) : ::String
      return own if parent.empty?
      return parent if own.empty?
      normalized_parent = parent.ends_with?("/") ? parent[0..-2] : parent
      if own.starts_with?("/")
        "#{normalized_parent}#{own}"
      else
        "#{normalized_parent}/#{own}"
      end
    end

    private def find_fastapi_imported_modules(app_base_path : ::String,
                                              file_path : ::String,
                                              source : ::String? = nil) : Hash(::String, Tuple(::String, Int32))
      cache_key = "#{app_base_path}\u{0}#{file_path}"
      if cached = @fastapi_import_cache[cache_key]?
        return cached
      end

      import_modules = find_imported_modules(app_base_path, file_path, source)
      local_base_path = File.dirname(file_path)
      if local_base_path == app_base_path
        @fastapi_import_cache[cache_key] = import_modules
        return import_modules
      end

      local_import_modules = find_imported_modules(local_base_path, file_path, source)
      local_import_modules.each do |name, import_info|
        import_modules[name] = import_info unless import_modules.has_key?(name)
      end

      @fastapi_import_cache[cache_key] = import_modules
      import_modules
    end

    # Configures the prefix for each router
    def configure_router_prefix(file : ::String,
                                include_router_map : Hash(::String, Hash(::String, Router)),
                                app_base_path : ::String,
                                router_prefix : ::String = "",
                                target_instance_name : ::String? = nil,
                                visited : Set(::String) = Set(::String).new)
      return if file.empty? || !File.exists?(file)

      # Parse the source file for router configuration
      source = read_file_content(file)
      import_modules = find_fastapi_imported_modules(app_base_path, file, source)
      include_router_map[file].each do |instance_name, router_class|
        next if target_instance_name && instance_name != target_instance_name

        # Each (file, router) is configured at most once. Without this
        # guard the new local-router recursion below (and any app that
        # includes the same router from two parents) would re-prepend
        # the inherited prefix and could recurse forever on a cyclic
        # include graph.
        next unless visited.add?("#{file}::#{instance_name}")

        # PREPEND the inherited prefix to the router's own. The
        # initial pass captures `APIRouter(prefix="/users")`, so
        # `router_class.prefix` may already be `/users`; if we
        # overwrite it here with `router_prefix`, the constructor
        # prefix is silently dropped and routes inside the router
        # collapse to the parent's prefix only. Regression on
        # full-stack-fastapi-template: `users.router` and
        # `items.router` both declare `prefix=...` at construction
        # time, but their routes were surfacing without the
        # `/users` / `/items` segment.
        router_class.prefix = combine_router_prefixes(router_prefix, router_class.prefix)

        # Parse `{app}.include_router(...)` calls. Real FastAPI apps
        # often use keyword form (`router=users.router`) and nested
        # options (`dependencies=[Depends(...)]`), so parse arguments
        # with the same top-level splitter used by route decorators
        # instead of a comma split or a regex that stops at the first
        # nested `)`.
        extract_include_router_calls(source, instance_name).each do |args|
          router_instance_name = extract_include_router_target(args)
          next if router_instance_name.empty?

          prefix = ""
          if raw_value = extract_python_keyword_expression(args, "prefix")
            # Only set prefix when the value is a quoted string
            # literal. Anything else — `prefix=settings.API_V1_STR`,
            # `prefix=f"{base}/v1"`, `prefix=API_PREFIX` — is a
            # cross-file reference we can't resolve from the call
            # site alone. Letting the raw expression flow through
            # to `router_class.join` used to surface garbage URLs
            # like `/settings.API_V1_STR/me` (regression seen on
            # full-stack-fastapi-template). Try one more rescue
            # path before falling back to empty: when the value
            # is a bare top-level constant (`API_V1_STR`) imported
            # via `from … import …`, look up its definition.
            if lit = raw_value.match(/^['"]([^'"]*)['"]/)
              prefix = lit[1]
            elsif resolved = resolve_string_expression(raw_value, source, import_modules)
              prefix = resolved
            end
          end

          # Register router's prefix recursively
          prefix = router_class.join(prefix)
          if router_instance_name.count(".") == 0
            if include_router_map[file].has_key?(router_instance_name)
              # A router included from the SAME file (e.g. dispatch's
              # `api_router.include_router(authenticated_organization_api_router)`).
              # Recurse so the included router's OWN `include_router`
              # calls are processed under the inherited prefix —
              # previously we only set its prefix and stopped, which
              # dropped every grand-child route's prefix
              # (`/{organization}/cases/...` collapsed to `/...`).
              configure_router_prefix(file, include_router_map, app_base_path, prefix, router_instance_name, visited)
              next
            end

            next unless import_modules.has_key?(router_instance_name)
            import_module_path = import_modules[router_instance_name].first

            next unless include_router_map.has_key?(import_module_path)
            # The local name is frequently an alias
            # (`from .api import router as api_router`). The target
            # file registers the router under its ORIGINAL symbol
            # (`router`), so translate the alias back before recursing.
            # Passing the alias straight through made the
            # `target_instance_name` filter never match, silently
            # dropping the ENTIRE sub-router prefix tree — the dominant
            # FastAPI accuracy bug on real apps (fastapi-realworld,
            # Netflix/dispatch) that lean on `import router as X`.
            target_name = resolve_original_import_name(source, router_instance_name, include_router_map[import_module_path])
            configure_router_prefix(import_module_path, include_router_map, app_base_path, prefix, target_name, visited)
          elsif router_instance_name.count(".") == 1
            module_name, imported_router_instance_name = router_instance_name.split(".")
            next unless import_modules.has_key?(module_name)
            import_module_path = import_modules[module_name].first

            next unless include_router_map.has_key?(import_module_path)
            configure_router_prefix(import_module_path, include_router_map, app_base_path, prefix, imported_router_instance_name, visited)
          end
        end
      end
    end

    private def fastapi_project_roots(app_instances : Array(Tuple(::String, ::String))) : Array(::String)
      roots = [] of ::String
      app_instances.each do |app_file, _|
        root = fastapi_project_root_for(app_file)
        roots << root unless roots.includes?(root)
      end
      # Prefer the shallow app root. Deep helper modules can also construct
      # FastAPI instances, but imports such as `from app...` resolve from the
      # project root, not the helper's package directory.
      roots.sort_by!(&.size)
      roots
    end

    private def fastapi_project_root_for(app_file : ::String) : ::String
      Path.new(File.dirname(app_file)).parent.to_s
    end

    private def fastapi_base_path_for(path : ::String, project_roots : Array(::String)) : ::String
      # project_roots is sorted shallowest-first, so the first containing
      # root is the package root the app's absolute imports resolve from.
      project_roots.find { |root| Noir::PathScope.under_root?(path, root) } || python_base_path_for(path)
    end

    private def extract_include_router_calls(source : ::String, instance_name : ::String) : Array(::String)
      calls = [] of ::String
      res = instance_regexes(instance_name)
      lines = source.split("\n")
      lines.each_with_index do |line, index|
        stripped = line.lstrip
        next if stripped.starts_with?("#")
        next unless line.includes?("include_router") && line.matches?(res.include_router_guard)

        logical_line = coalesce_include_router_call(lines, index, line, instance_name)
        match = logical_line.match(res.include_router_call)
        calls << match[1] if match
      end
      calls
    end

    private def coalesce_include_router_call(codelines : Array(::String),
                                             index : Int32,
                                             line : ::String,
                                             instance_name : ::String) : ::String
      return line unless line.matches?(instance_regexes(instance_name).include_router_guard)
      return line if python_call_balanced?(line)

      pieces = [line]
      depth = python_paren_delta(line)
      i = index + 1
      while i < codelines.size && depth > 0
        nxt = codelines[i]
        pieces << nxt
        depth += python_paren_delta(nxt)
        break if depth <= 0
        i += 1
      end
      pieces.join(' ')
    end

    # Translate a locally-used router name back to the symbol it is
    # registered under inside the imported file's `target_map`
    # (instance name → Router). Real FastAPI apps overwhelmingly wire
    # sub-routers with `from .pkg import router as pkg_router` and then
    # `parent.include_router(pkg_router, ...)`. The imported file
    # registers the router under its ORIGINAL name (`router`), so the
    # alias has to be resolved before recursing — otherwise
    # `configure_router_prefix`'s `target_instance_name` filter never
    # matches and every prefix below that include is lost.
    #
    # Resolution order, each guarded against `target_map`'s real keys:
    #   1. The local name already names a router in the target file.
    #   2. An `<orig> as <local>` import line maps the alias back.
    #   3. The target file declares exactly one router — the include
    #      can only mean that one.
    # Falls back to the local name (the prior behaviour) otherwise.
    private def resolve_original_import_name(importing_source : ::String,
                                             local_name : ::String,
                                             target_map : Hash(::String, Router)) : ::String
      return local_name if target_map.has_key?(local_name)

      importing_source.each_line do |raw|
        stripped = raw.lstrip
        next unless stripped.starts_with?("from ") || stripped.starts_with?("import ")
        next unless stripped.includes?(" as ") && stripped.includes?(local_name)
        if match = stripped.match(/\b(#{PYTHON_VAR_NAME_REGEX})\s+as\s+#{Regex.escape(local_name)}\b/)
          original = match[1]
          return original if target_map.has_key?(original)
        end
      end

      return target_map.first_key if target_map.size == 1

      local_name
    end

    private def extract_include_router_target(args : ::String) : ::String
      if router_keyword = extract_python_keyword_expression(args, "router")
        return router_keyword.strip
      end

      split_python_arguments(args).each do |arg|
        stripped = arg.strip
        next if stripped.empty?
        break if top_level_keyword_argument?(stripped)
        return stripped
      end

      ""
    end

    # Best-effort resolver for a non-literal `prefix=` expression in
    # `include_router(...)`. Handles two shapes the wild produces:
    #
    #   * `prefix=API_V1_STR` — a top-level constant imported via
    #     `from app.core.config import API_V1_STR`. We look up the
    #     constant's defining module via `import_modules` and search
    #     it for `NAME = "literal"`.
    #   * `prefix=settings.API_V1_STR` — class-attribute access on an
    #     imported instance. We look up `settings`'s module and search
    #     it for `API_V1_STR: str = "literal"` (the BaseSettings shape
    #     full-stack-fastapi-template uses) or `API_V1_STR = "literal"`.
    #
    # Returns nil when the expression doesn't match either shape or
    # we can't find the underlying file — the caller then falls back
    # to an empty prefix so we never surface raw Python expressions
    # in URLs.
    def resolve_constant_value(expression : ::String,
                               import_modules : Hash(::String, Tuple(::String, Int32))) : ::String?
      expr = expression.strip
      module_path = nil
      const_name = nil

      if attr_match = expr.match(/^([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)$/)
        module_alias, attr_name = attr_match[1], attr_match[2]
        return unless import_modules.has_key?(module_alias)
        module_path = import_modules[module_alias].first
        const_name = attr_name
      elsif name_match = expr.match(/^([A-Za-z_][A-Za-z0-9_]*)$/)
        bare_name = name_match[1]
        return unless import_modules.has_key?(bare_name)
        module_path = import_modules[bare_name].first
        const_name = bare_name
      end

      return unless module_path && const_name
      return unless File.exists?(module_path)

      module_source = read_file_content(module_path)
      # Match either a typed assignment (`NAME: str = "..."`) or a
      # bare assignment (`NAME = "..."`). Indented assignments are
      # accepted because BaseSettings-style configs nest the
      # constant inside a class body.
      pattern = /^\s*#{Regex.escape(const_name)}\s*(?::[^=]+)?=\s*['"]([^'"]*)['"]/m
      if match = module_source.match(pattern)
        return match[1]
      end

      nil
    end

    private def resolve_string_expression(expression : ::String,
                                          source : ::String,
                                          import_modules : Hash(::String, Tuple(::String, Int32)),
                                          depth : Int32 = 0) : ::String?
      return if depth > 3

      expr = expression.strip
      if parts = split_python_expression(expr, '+')
        resolved_parts = [] of ::String
        parts.each do |part|
          resolved = resolve_string_expression(part, source, import_modules, depth + 1)
          return unless resolved
          resolved_parts << resolved
        end
        return resolved_parts.join
      end

      if lit = expr.match(/^([rRuUbBfF]*)['"]([^'"]*)['"]$/)
        prefixes = lit[1].downcase
        value = lit[2]
        if prefixes.includes?("f") && value.includes?("{")
          return resolve_f_string(value, source, import_modules, depth + 1)
        end
        return value
      end

      if local = resolve_constant_in_source(expr, source, import_modules, depth)
        return local
      end

      if local_attr = resolve_local_factory_attribute(expr, source, import_modules, depth)
        return local_attr
      end

      resolve_constant_value(expr, import_modules)
    end

    private def resolve_local_factory_attribute(expression : ::String,
                                                source : ::String,
                                                import_modules : Hash(::String, Tuple(::String, Int32)),
                                                depth : Int32) : ::String?
      return if depth > 3
      attr_match = expression.match(/^([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)$/)
      return unless attr_match

      object_name, attr_name = attr_match[1], attr_match[2]
      call_match = source.match(/^\s*#{Regex.escape(object_name)}\s*(?::[^=]+)?=\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*\(/m)
      return unless call_match

      callee = call_match[1]
      callee_root = callee.split(".", 2)[0]
      callee_name = callee.split(".")[-1]
      if imported = import_modules[callee_root]?
        module_path = imported.first
        return resolve_attribute_from_file(module_path, attr_name, callee_name, depth + 1) unless module_path.empty?
      end

      nil
    end

    private def resolve_attribute_from_file(module_path : ::String,
                                            attr_name : ::String,
                                            factory_name : ::String?,
                                            depth : Int32) : ::String?
      return if depth > 4
      return unless File.exists?(module_path)

      module_source = read_file_content(module_path)
      if value = resolve_attribute_default_in_source(module_source, attr_name)
        return value
      end

      if factory_name
        if return_type = extract_function_return_annotation(module_source, factory_name)
          if value = resolve_class_attribute_from_file(module_path, module_source, return_type, attr_name, depth + 1)
            return value
          end
        end
      end

      nil
    end

    private def resolve_class_attribute_from_file(module_path : ::String,
                                                  module_source : ::String,
                                                  class_name : ::String,
                                                  attr_name : ::String,
                                                  depth : Int32) : ::String?
      return if depth > 4

      if value = resolve_class_attribute_default(module_source, class_name, attr_name)
        return value
      end

      import_modules = imported_modules_for_resolution(module_path, module_source)
      if imported = import_modules[class_name]?
        imported_path = imported.first
        return if imported_path.empty? || imported_path == module_path
        imported_source = read_file_content(imported_path)
        return resolve_class_attribute_from_file(imported_path, imported_source, class_name, attr_name, depth + 1)
      end

      nil
    end

    private def imported_modules_for_resolution(module_path : ::String, module_source : ::String) : Hash(::String, Tuple(::String, Int32))
      merged = Hash(::String, Tuple(::String, Int32)).new
      candidate_bases = [] of ::String
      base_paths.each do |base_path|
        candidate_bases << base_path if path_under_root?(module_path, base_path)
      end
      candidate_bases << File.dirname(module_path)

      candidate_bases.uniq.each do |base_path|
        find_fastapi_imported_modules(base_path, module_path, module_source).each do |name, import_info|
          merged[name] = import_info unless merged.has_key?(name)
        end
      end

      merged
    end

    private def extract_function_return_annotation(source : ::String, function_name : ::String) : ::String?
      match = source.match(/^\s*def\s+#{Regex.escape(function_name)}\s*\([^)]*\)\s*->\s*([A-Za-z_][A-Za-z0-9_]*)\s*:/m)
      match ? match[1] : nil
    end

    private def resolve_attribute_default_in_source(source : ::String, attr_name : ::String) : ::String?
      pattern = /^\s*#{Regex.escape(attr_name)}\s*(?::[^=]+)?=\s*['"]([^'"]*)['"]/m
      if match = source.match(pattern)
        return match[1]
      end

      nil
    end

    private def resolve_class_attribute_default(source : ::String, class_name : ::String, attr_name : ::String) : ::String?
      class_start = source.index(/class\s+#{Regex.escape(class_name)}\s*[\(:]/)
      return unless class_start

      class_codeblock = parse_code_block(source[class_start..])
      return unless class_codeblock

      resolve_attribute_default_in_source(class_codeblock, attr_name)
    end

    private def resolve_f_string(value : ::String,
                                 source : ::String,
                                 import_modules : Hash(::String, Tuple(::String, Int32)),
                                 depth : Int32) : ::String?
      result = String.build do |io|
        index = 0
        while index < value.size
          if value[index] == '{'
            if index + 1 < value.size && value[index + 1] == '{'
              io << '{'
              index += 2
              next
            end

            end_index = value.index('}', index + 1)
            return unless end_index
            expression = value[(index + 1)...end_index].strip
            return if expression.empty? || expression.includes?(":") || expression.includes?("!")
            resolved = resolve_string_expression(expression, source, import_modules, depth + 1)
            return unless resolved
            io << resolved
            index = end_index + 1
          elsif value[index] == '}' && index + 1 < value.size && value[index + 1] == '}'
            io << '}'
            index += 2
          else
            io << value[index]
            index += 1
          end
        end
      end
      result
    end

    private def resolve_constant_in_source(expression : ::String,
                                           source : ::String,
                                           import_modules : Hash(::String, Tuple(::String, Int32)),
                                           depth : Int32) : ::String?
      return unless expression.matches?(/^[A-Za-z_][A-Za-z0-9_]*$/)
      pattern = /^\s*#{Regex.escape(expression)}\s*(?::[^=]+)?=\s*([^#]+)/
      source.each_line do |line|
        next unless match = line.match(pattern)
        raw_value = match[1].strip
        next if raw_value.empty?
        return resolve_string_expression(raw_value, source, import_modules, depth + 1)
      end
      nil
    end

    private def extract_python_keyword_expression(call_tail : ::String, keyword : ::String) : ::String?
      return unless call_tail.includes?(keyword)
      match = call_tail.match(/\b#{Regex.escape(keyword)}\s*=/)
      return unless match

      index = match.end
      expression = String.build do |io|
        depth = 0
        in_quote = nil
        escaped = false
        while index < call_tail.size
          ch = call_tail[index]
          if in_quote
            io << ch
            if escaped
              escaped = false
            elsif ch == '\\'
              escaped = true
            elsif ch == in_quote
              in_quote = nil
            end
          else
            case ch
            when '\'', '"'
              in_quote = ch
              io << ch
            when '(', '[', '{'
              depth += 1
              io << ch
            when ')', ']', '}'
              break if depth <= 0 && ch == ')'
              depth -= 1 if depth > 0
              io << ch
            when ','
              break if depth == 0
              io << ch
            else
              io << ch
            end
          end
          index += 1
        end
      end.strip

      expression.empty? ? nil : expression
    end

    private def parse_fastapi_route_decorator(line : ::String,
                                              instance_name : ::String,
                                              source : ::String,
                                              import_modules : Hash(::String, Tuple(::String, Int32))) : Tuple(::String, ::String, ::String)?
      match = line.match(instance_regexes(instance_name).route_decorator)
      return unless match

      attr = match[1]
      args = match[2]
      path_expr = extract_route_path_expression(args)
      return unless path_expr

      path = resolve_string_expression(path_expr, source, import_modules)
      return unless path

      {attr, path, args}
    end

    private def parse_fastapi_programmatic_route(line : ::String,
                                                 instance_name : ::String,
                                                 source : ::String,
                                                 import_modules : Hash(::String, Tuple(::String, Int32))) : Tuple(::String, ::String, ::String)?
      match = line.match(instance_regexes(instance_name).programmatic_route)
      return unless match

      attr = match[1]
      args = match[2]
      path_expr = extract_route_path_expression(args)
      return unless path_expr

      path = resolve_string_expression(path_expr, source, import_modules)
      return unless path

      {attr, path, args}
    end

    private def parse_fastapi_static_mount(line : ::String,
                                           instance_name : ::String,
                                           source : ::String,
                                           import_modules : Hash(::String, Tuple(::String, Int32))) : ::String?
      match = line.match(instance_regexes(instance_name).static_mount)
      return unless match

      args = match[1]
      return unless args.includes?("StaticFiles")

      path_expr = extract_route_path_expression(args)
      return unless path_expr

      resolve_string_expression(path_expr, source, import_modules)
    end

    private def resolve_programmatic_handler(args : ::String,
                                             current_path : ::String,
                                             source : ::String,
                                             import_modules : Hash(::String, Tuple(::String, Int32))) : Tuple(::String, ::String)?
      handler_reference = extract_programmatic_handler_reference(args)
      return unless handler_reference

      if handler_reference.includes?(".")
        receiver, function_name = handler_reference.split(".", 2)
        if import_info = import_modules[receiver]?
          import_path = import_info.first
          return {import_path, function_name} unless import_path.empty?
        end

        sibling_module_path = File.join(File.dirname(current_path), "#{receiver}.py")
        return {sibling_module_path, function_name} if File.exists?(sibling_module_path)

        return
      end

      return {current_path, handler_reference} if find_function_def_line(source.split("\n"), handler_reference)

      if import_info = import_modules[handler_reference]?
        import_path = import_info.first
        return {import_path, handler_reference} unless import_path.empty?
      end

      nil
    end

    private def extract_programmatic_handler_callee(args : ::String) : ::String?
      if endpoint_expr = extract_python_keyword_expression(args, "endpoint")
        return clean_programmatic_handler_callee(endpoint_expr)
      end

      positional_args = [] of ::String
      split_python_arguments(args).each do |arg|
        stripped = arg.strip
        break if top_level_keyword_argument?(stripped)
        positional_args << stripped
      end

      return if positional_args.size < 2
      clean_programmatic_handler_callee(positional_args[1])
    end

    private def clean_programmatic_handler_callee(expression : ::String) : ::String?
      reference = expression.strip.split("#", 2)[0].strip
      if match = reference.match(HANDLER_CALL_RE)
        return match[1]
      end
      return reference if reference.matches?(HANDLER_REF_RE)

      nil
    end

    private def extract_programmatic_handler_reference(args : ::String) : ::String?
      if endpoint_expr = extract_python_keyword_expression(args, "endpoint")
        return clean_programmatic_handler_reference(endpoint_expr)
      end

      positional_args = [] of ::String
      split_python_arguments(args).each do |arg|
        stripped = arg.strip
        break if top_level_keyword_argument?(stripped)
        positional_args << stripped
      end

      return if positional_args.size < 2
      clean_programmatic_handler_reference(positional_args[1])
    end

    private def clean_programmatic_handler_reference(expression : ::String) : ::String?
      reference = expression.strip.split("#", 2)[0].strip
      return reference if reference.matches?(HANDLER_REF_RE)

      nil
    end

    private def find_function_def_line(lines : Array(::String), function_name : ::String) : Int32?
      # Compile the name-specific matcher once per call instead of on
      # every line, and gate it behind a substring check any real
      # `def <name>` satisfies.
      def_re = /^\s*(?:async\s+)?def\s+#{Regex.escape(function_name)}\s*\(/
      lines.each_with_index do |line, index|
        next unless line.includes?("def") && line.includes?(function_name)
        return index if line.matches?(def_re)
      end

      nil
    end

    private def extract_fastapi_handler_params(codelines : Array(::String),
                                               def_line : Int32,
                                               route_path : ::String,
                                               source : ::String,
                                               import_modules : Hash(::String, Tuple(::String, Int32))) : Array(Param)
      params = [] of Param
      function_definition = parse_function_def(codelines, def_line)
      return params unless function_definition

      path_param_names = fastapi_path_param_names(route_path)

      function_definition.params.each do |param|
        next if param.name == "*" || path_param_names.includes?(param.name)
        next if param.name.in?(%w[self cls])
        next if fastapi_dependency_param?(param)

        default_value = return_literal_value(param.default)
        param_type = infer_parameter_type(param.default) unless param.default.empty?
        if param_type.nil? && !param.type.empty?
          param_type = param.type
          param_type = param_type.split("Annotated[", 2)[-1].split(",", 2)[-1] if param_type.includes?("Annotated[")
          param_type = param_type.split("Union[", 2)[-1] if param_type.includes?("Union[")
          param_type = infer_parameter_type(param_type, true)
          param_type = "query" if param_type.nil? && param.type.empty?
        else
          param_type = "query" if param_type.nil?
        end

        if param_type.nil?
          if /^#{PYTHON_VAR_NAME_REGEX}$/.match(param.type)
            if param.type.in?(%w[Request dict])
              function_codeblock = parse_code_block(codelines[def_line..])
              next if function_codeblock.nil?
              new_params = find_dictionary_params(function_codeblock, param)
            elsif import_modules.has_key?(param.type)
              import_module_path = import_modules[param.type].first
              next if import_module_path.empty?

              import_module_source = read_file_content(import_module_path)
              new_params = find_base_model_params(import_module_source, param.type, param.name)
            else
              new_params = find_base_model_params(source, param.type, param.name)
            end

            next if new_params.nil?
            new_params.each { |model_param| params << model_param }
          end
        else
          params << Param.new(param.name, default_value, param_type)
        end
      end

      params
    end

    private def fastapi_path_param_names(route_path : ::String) : Array(::String)
      names = [] of ::String
      route_path.scan(PATH_PARAM_REGEX) do |match|
        names << match[1] if match.size > 0 && !names.includes?(match[1])
      end
      names
    end

    private def normalize_fastapi_path_params(route_path : ::String) : ::String
      route_path.gsub(TYPED_PATH_PARAM_REGEX) { |_| "{#{$~[1]}}" }
    end

    private def fastapi_dependency_param?(param : FunctionParameter) : Bool
      fastapi_dependency_expression?(param.default) ||
        fastapi_dependency_expression?(param.type)
    end

    private def fastapi_dependency_expression?(expression : ::String) : Bool
      expression.includes?("Depends(") || expression.includes?("Security(")
    end

    private def extract_route_path_expression(args : ::String) : ::String?
      split_python_arguments(args).each do |arg|
        stripped = arg.strip
        next if stripped.empty?
        break if top_level_keyword_argument?(stripped)
        return stripped
      end

      extract_python_keyword_expression(args, "path") ||
        extract_python_keyword_expression(args, "rule") ||
        extract_python_keyword_expression(args, "uri")
    end

    private def top_level_keyword_argument?(arg : ::String) : Bool
      !!arg.match(/^[A-Za-z_][A-Za-z0-9_]*\s*=/)
    end

    private def split_python_arguments(args : ::String) : Array(::String)
      split_python_top_level(args, ',')
    end

    private def split_python_expression(expression : ::String, delimiter : Char) : Array(::String)?
      parts = split_python_top_level(expression, delimiter)
      return if parts.size <= 1
      parts
    end

    private def split_python_top_level(input : ::String, delimiter : Char) : Array(::String)
      parts = [] of ::String
      start = 0
      depth = 0
      in_quote = nil
      escaped = false
      index = 0
      while index < input.size
        ch = input[index]
        if in_quote
          if escaped
            escaped = false
          elsif ch == '\\'
            escaped = true
          elsif ch == in_quote
            in_quote = nil
          end
        else
          case ch
          when '\'', '"'
            in_quote = ch
          when '(', '[', '{'
            depth += 1
          when ')', ']', '}'
            depth -= 1 if depth > 0
          else
            if ch == delimiter && depth == 0
              parts << input[start...index]
              start = index + 1
            end
          end
        end
        index += 1
      end
      parts << input[start..]
      parts
    end

    private def static_route_path(path : ::String) : ::String
      normalized = path.gsub(/\/+/, "/")
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized = normalized[0...-1] if normalized.ends_with?("/") && normalized != "/"
      normalized == "/" ? "/*" : "#{normalized}/*"
    end

    # Infers the type of the parameter based on its default value or type annotation
    def infer_parameter_type(data : ::String, is_param_type = false) : ::String?
      if data.matches?(/Cookie/)
        "cookie"
      elsif data.matches?(/Header/)
        "header"
      elsif data.matches?(/Body/) || data.matches?(/Form/) ||
            data.matches?(/File/) || data.matches?(/UploadFile/)
        "form"
      elsif data.matches?(/Query/)
        "query"
      elsif data.matches?(/WebSocket/)
        "websocket"
      elsif is_param_type
        # default variable type
        ["str", "int", "float", "bool", "EmailStr"].each do |type|
          return "query" if data.includes?(type)
        end
      end
    end

    # Finds the parameters for a base model class
    def find_base_model_params(source : ::String, class_name : ::String, param_name : ::String) : Array(Param)
      params = [] of Param
      class_codeblock = parse_code_block(source, /\s*class\s*#{class_name}\s*\(/)
      return params if class_codeblock.nil?

      # Parse the class code block to extract parameters
      class_codeblock.split("\n").each_with_index do |line, index|
        if index == 0
          param_code = line.split("(", 2)[-1].split(")")[0]
          if param_code.match(/(\b)*str,\s*(enum\.){0,1}Enum(\b)*/)
            return [Param.new(param_name.strip, "", "query")]
          end
          return params unless /^#{PYTHON_VAR_NAME_REGEX}$/.match(param_code)
        else
          break unless line.split(":").size == 2

          param_name, extra = line.split(":", 2)
          param_default = ""
          param_type_and_default = extra.split("=", 2)
          if param_type_and_default.size == 2
            param_type, param_default = param_type_and_default
          else
            param_type = param_type_and_default[0]
          end

          if !param_name.empty? && !param_type.empty?
            default_value = return_literal_value(param_default.strip)
            params << Param.new(param_name.strip, default_value, "form")
          end
        end
      end

      params
    end

    # Finds parameters in dictionary structures
    def find_dictionary_params(source : ::String, param : FunctionParameter) : Array(Param)
      new_params = [] of Param
      json_variable_names = [] of ::String
      codelines = source.split("\n")
      if param.type == "Request"
        # Parse JSON variable names
        codelines.each do |codeline|
          next unless codeline.includes?(param.name) && codeline.includes?("json")
          match = codeline.match /(#{PYTHON_VAR_NAME_REGEX})\s*(?::\s*#{PYTHON_VAR_NAME_REGEX})?\s*=\s*(await\s*){0,1}#{param.name}.json\(\)/
          json_variable_names << match[1] if !match.nil? && !json_variable_names.includes?(match[1])
        end

        new_params = find_json_params(codelines, json_variable_names)
      elsif param.type == "dict"
        json_variable_names << param.name
        new_params = find_json_params(codelines, json_variable_names)
      end

      new_params
    end

    # Like `coalesce_decorator_call`, but for the programmatic
    # `<instance>.add_api_route(...)` / `add_api_websocket_route(...)`
    # registration form. The opening shape doesn't have `@` so it
    # needs a different regex to detect the call start.
    private def coalesce_programmatic_call(codelines : Array(::String),
                                           index : Int32,
                                           line : ::String,
                                           instance_name : ::String) : ::String
      return line unless line.matches?(instance_regexes(instance_name).programmatic_guard)
      return line if python_call_balanced?(line)

      pieces = [line]
      depth = python_paren_delta(line)
      i = index + 1
      while i < codelines.size && depth > 0
        nxt = codelines[i]
        pieces << nxt
        depth += python_paren_delta(nxt)
        break if depth <= 0
        i += 1
      end
      pieces.join(' ')
    end

    private def coalesce_mount_call(codelines : Array(::String),
                                    index : Int32,
                                    line : ::String,
                                    instance_name : ::String) : ::String
      return line unless line.matches?(instance_regexes(instance_name).mount_guard)
      return line if python_call_balanced?(line)

      pieces = [line]
      depth = python_paren_delta(line)
      i = index + 1
      while i < codelines.size && depth > 0
        nxt = codelines[i]
        pieces << nxt
        depth += python_paren_delta(nxt)
        break if depth <= 0
        i += 1
      end
      pieces.join(' ')
    end

    private def coalesce_constructor_call(codelines : Array(::String),
                                          index : Int32,
                                          line : ::String,
                                          constructor_name : ::String) : ::String
      return line unless line.includes?(constructor_name) && line.matches?(/\b#{Regex.escape(constructor_name)}\s*\(/)
      return line if python_call_balanced?(line)

      pieces = [line]
      depth = python_paren_delta(line)
      i = index + 1
      while i < codelines.size && depth > 0
        nxt = codelines[i]
        pieces << nxt
        depth += python_paren_delta(nxt)
        break if depth <= 0
        i += 1
      end
      pieces.join(' ')
    end

    # Extract `methods=[...]` / `methods=("...")` from a FastAPI
    # `@router.api_route(...)` / `@router.route(...)` decorator tail.
    # Returns the upper-cased verbs in declaration order; empty list
    # means the decorator didn't declare any methods (caller falls
    # back to the verb implied by the attribute name).
    private def extract_declared_methods(extra_params : ::String) : Array(::String)
      methods = [] of ::String
      list_match = extra_params.match(/methods\s*=\s*[\[(]([^\])]*)[\])]/)
      if list_match
        list_match[1].scan(/['"]([A-Za-z]+)['"]/) do |m|
          methods << m[1].upcase
        end
      end
      methods
    end

    # If `line` is the start of an `@instance.method(...)` decorator
    # call whose opening paren isn't balanced on the same line, fold
    # the continuation lines into one logical string. Returns `line`
    # unchanged when the call is single-line or doesn't match an
    # `@instance.<method>(` shape. The decorator's `(` and `)` are
    # joined with the continuation content via single-space separators
    # so the downstream regex sees a familiar single-line shape.
    private def coalesce_decorator_call(codelines : Array(::String),
                                        index : Int32,
                                        line : ::String,
                                        instance_name : ::String) : ::String
      return line unless line.matches?(instance_regexes(instance_name).decorator_guard)
      return line if python_call_balanced?(line)

      pieces = [line]
      depth = python_paren_delta(line)
      i = index + 1
      while i < codelines.size && depth > 0
        nxt = codelines[i]
        pieces << nxt
        depth += python_paren_delta(nxt)
        break if depth <= 0
        i += 1
      end

      pieces.join(' ')
    end

    # Net `(` − `)` paren count for `line`, ignoring parens inside
    # single- or double-quoted strings. Sufficient for FastAPI
    # decorator headers, which don't carry triple-quoted strings or
    # raw f-strings on the call line itself.
    private def python_paren_delta(line : ::String) : Int32
      depth = 0
      in_quote = nil
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
        when '('
          depth += 1
        when ')'
          depth -= 1
        end
      end
      depth
    end

    # Whether `line`'s paren count is balanced (delta == 0). Used to
    # short-circuit the multi-line join when the call already closes
    # on the same line.
    private def python_call_balanced?(line : ::String) : Bool
      python_paren_delta(line) == 0
    end
  end

  # Router class for handling URL prefix joining
  class Router
    @prefix : ::String

    def initialize(prefix : ::String)
      @prefix = prefix
    end

    def prefix
      @prefix
    end

    def join(url : ::String) : ::String
      # An empty route path adds nothing beyond the prefix:
      # `APIRouter(prefix="/user")` + `@router.get("")` resolves to
      # `/user`, NOT `/user/`. (A literal `"/"` route still keeps its
      # trailing slash, e.g. `prefix="/items"` + `"/"` → `/items/`.)
      # Without this guard every `""`-path route in a prefixed router
      # surfaced with a spurious trailing slash (fastapi-realworld).
      return @prefix if url.empty? && !@prefix.empty?

      url = url[1..] if prefix.ends_with?("/") && url.starts_with?("/")
      url = "/#{url}" unless prefix.ends_with?("/") || url.starts_with?("/")

      @prefix + url
    end

    def prefix=(new_prefix : ::String)
      @prefix = new_prefix
    end
  end

  # Extend ::String class to check if a string is numeric
  class ::String
    def numeric?
      to_f != nil rescue false
    end
  end
end
