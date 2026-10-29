require "../../engines/python_engine"
require "../../../utils/top_level_split"
require "./python_helper"

module Analyzer::Python
  class FastAPI < PythonEngine
    analyzer_for "python_fastapi"

    PATH_PARAM_REGEX       = /\{(#{PYTHON_VAR_NAME_REGEX})(?::[a-zA-Z_][a-zA-Z0-9_]*)?\}/
    TYPED_PATH_PARAM_REGEX = /\{(#{PYTHON_VAR_NAME_REGEX}):[a-zA-Z_][a-zA-Z0-9_]*\}/

    # Constant-only matchers hoisted out of the per-line analyze loops so
    # they aren't recompiled (Crystal rebuilds an interpolated regex
    # literal on every evaluation). The `.to_s` expansion of the
    # interpolated constants is byte-identical to the previous inline form.
    FASTAPI_INSTANCE_RE = /(#{PYTHON_VAR_NAME_REGEX})(?::#{DOT_NATION})?=(?:fastapi\.)?FastAPI\(/
    # `def init_views(app: FastAPI)` (space-stripped): the app built
    # elsewhere and handed in; its `include_router` / `@app.get` calls in
    # this file register on it too.
    FASTAPI_PARAM_RE = /(?:^|[(,])(#{PYTHON_VAR_NAME_REGEX}):(?:fastapi\.)?FastAPI(?:[,)=]|$)/
    # Library subclasses of `fastapi.APIRouter`, constructed like it.
    LIBRARY_ROUTER_CLASSES = %w[APIRouter VersionedAPIRouter InferringRouter]
    # `class UserRouter(APIRouter):` — a project router class, constructed
    # like APIRouter itself.
    ROUTER_SUBCLASS_RE = /^class\s+(#{PYTHON_VAR_NAME_REGEX})\s*\(([^)]*)\)\s*:/m
    VAR_NAME_FULL_RE   = /^#{PYTHON_VAR_NAME_REGEX}$/
    HANDLER_CALL_RE    = /^(#{PYTHON_VAR_NAME_REGEX}(?:\.#{PYTHON_VAR_NAME_REGEX})?)\s*\(/
    HANDLER_REF_RE     = /^#{PYTHON_VAR_NAME_REGEX}(?:\.#{PYTHON_VAR_NAME_REGEX})?$/

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

    REQUEST_ATTR_TYPES = {"query_params" => "query", "headers" => "header", "cookies" => "cookie"}
    @request_attr_regex_cache = Hash(::String, Regex).new

    def analyze
      include_router_map = Hash(::String, Hash(::String, Router)).new
      fastapi_app_instances = [] of Tuple(::String, ::String)
      parameter_app_instances = [] of Tuple(::String, ::String)

      begin
        # Iterate through all Python files in all base paths. Pulls from
        # the detector-built file_map so subtree pruning and
        # --exclude-path apply to this pass too.
        python_files = python_source_files
        router_classes = router_class_names(python_files).map { |name| Regex.escape(name) }.join("|")
        router_ctor_re = /\b(?:fastapi\.)?(?:#{router_classes})\s*\(/
        router_instance_re = /(#{PYTHON_VAR_NAME_REGEX})(?::#{DOT_NATION})?=(?:fastapi\.)?(#{router_classes})\(/
        base_paths.each do |current_base_path|
          python_files.each do |path|
            next unless path_under_root?(path, current_base_path)
            source = read_file_content(path)

            import_modules = find_fastapi_imported_modules(current_base_path, path, source)
            codelines = source.split("\n")
            codelines.each_with_index do |original_line, index|
              next if original_line.lstrip.starts_with?("#")

              effective_line = original_line.includes?("Router") && original_line.matches?(router_ctor_re) ? join_until_python_call_closes(codelines, index, original_line) : original_line
              line = effective_line.gsub(" ", "")
              match = line.includes?("FastAPI(") ? line.match(FASTAPI_INSTANCE_RE) : nil
              parameter_app = false
              if match.nil? && (line.includes?(":FastAPI") || line.includes?(":fastapi.FastAPI"))
                match = line.match(FASTAPI_PARAM_RE)
                parameter_app = !match.nil?
              end
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
                # A parameter app (`lifespan(app: FastAPI)` in a top-level
                # helper) is no project root: it must not anchor imports.
                instances = parameter_app ? parameter_app_instances : fastapi_app_instances
                instances << app_key unless instances.includes?(app_key)
              end

              # https://fastapi.tiangolo.com/tutorial/bigger-applications/
              match = line.includes?("Router(") ? line.match(router_instance_re) : nil
              unless match.nil?
                prefix = ""
                router_instance_name = match[1]
                if param_codes = effective_line.split(match[2], 2)[1]?
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
        # Seed prefix configuration from every FastAPI app instance. A
        # router included more than once (two prefixes, or two parents)
        # collects one mounted prefix per inclusion path.
        prefix_visited = Set(::String).new
        # An app another app mounts is served only under the mount path,
        # so it is reached through that mount instead of seeded as a root —
        # unless the mount is a route-less wrapper in another file
        # (`wrapper = FastAPI(); wrapper.mount("/x", app)` in a dev script):
        # the real app is then likely served on its own too, so keep both.
        mounted_apps = Set(Tuple(::String, ::String)).new
        fastapi_app_instances.each do |app_file, app_instance|
          source = read_file_content(app_file)
          import_modules = find_fastapi_imported_modules(fastapi_base_path_for(app_file, fastapi_base_paths), app_file, source)
          extract_app_mount_calls(source, app_instance).each do |args|
            next unless mount = parse_app_mount(args, source, import_modules)
            target = resolve_router_reference(app_file, source, import_modules, include_router_map, mount[1])
            next unless target && target != {app_file, app_instance}
            next if target[0] != app_file && !declares_own_routes?(source, app_instance)
            mounted_apps << target
          end
        end
        (fastapi_app_instances + (parameter_app_instances - fastapi_app_instances)).each do |app_file, app_instance|
          next if mounted_apps.includes?({app_file, app_instance})
          app_base_path = fastapi_base_path_for(app_file, fastapi_base_paths)
          configure_router_prefix(app_file, include_router_map, app_base_path, "", app_instance, prefix_visited)
        end

        include_router_map.each do |path, router_map|
          source = read_file_content(path)
          import_base_path = fastapi_base_path_for(path, fastapi_base_paths)
          definition_base_path = python_base_path_for(path)
          import_modules = find_fastapi_imported_modules(import_base_path, path, source)
          codelines = source.split("\n")
          # A worked `@app.get(...)` example in a docstring is prose.
          in_docstring = Helper.docstring_line_flags(codelines)
          router_map.flat_map { |name, registered| registered.mounts.map { |router| {name, router} } }.each do |instance_name, router_class|
            codelines.each_with_index do |line, index|
              next if in_docstring[index] || line.lstrip.starts_with?("#")

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

                # Resolve the actual `def` line, skipping stacked
                # decorators / comments / blank lines between the
                # route decorator and the handler. Both param
                # extraction and callee extraction below need this
                # to be accurate; the previous `index + 1` shortcut
                # silently misfired on `@app.post(...)` + `@auth_required`
                # style stacks.
                def_line = find_def_line(codelines, index) || (index + 1)

                # Path parameters come from the whole served path: a router
                # prefix's `{group_slug}` binds a handler or dependency
                # parameter of that name just like the route's own.
                full_path = normalize_fastapi_path_params(router_class.join(http_route_path))
                params = extract_fastapi_handler_params(codelines, def_line, full_path, source, import_modules, path, import_base_path)
                class_view_params(codelines, index, full_path, source, path, import_base_path).each do |param|
                  params << param unless params.any? { |known| known.name == param.name && known.param_type == param.param_type }
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
                base_endpoint = Endpoint.new(full_path, emit_methods.first, params, details)
                base_endpoint.protocol = "ws" if websocket_route
                base_endpoint.handler = handler_at(codelines, def_line, path)

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
                                        dup_ep.handler = base_endpoint.handler
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
                prog_handler = nil.as(Handler?)
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
                    prog_handler = handler_at(handler_lines, handler_def_line, handler_path)
                    prog_params = extract_fastapi_handler_params(handler_lines, handler_def_line, prog_full, handler_source, handler_imports, handler_path, import_base_path)
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
                  endpoint.handler = prog_handler
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

    # `APIRouter` and every project class deriving from it, directly or
    # through another project router class (`class UserAPIRouter(APIRouter)`
    # that only pins `dependencies=`). Their instances take `prefix=` and
    # serve routes exactly like an APIRouter.
    private def router_class_names(files : Array(::String)) : Array(::String)
      bases = Hash(::String, Array(::String)).new
      files.each do |path|
        source = read_file_content(path)
        next unless source.includes?("Router")
        source.scan(ROUTER_SUBCLASS_RE) do |m|
          bases[m[1]] = m[2].split(",").map(&.strip.split(".").last)
        end
      end
      names = LIBRARY_ROUTER_CLASSES.dup
      loop do
        added = bases.keys.select { |name| !names.includes?(name) && bases[name].any? { |b| names.includes?(b) } }
        break if added.empty?
        names.concat(added)
      end
      names
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
      unless local_base_path == app_base_path
        local_import_modules = find_imported_modules(local_base_path, file_path, source)
        local_import_modules.each do |name, import_info|
          import_modules[name] = import_info unless import_modules.has_key?(name)
        end
      end

      # The module resolver leaves a name bound to a package — `from .
      # import auth` (auth/), or `from app.routes import router` defined in
      # routes/__init__.py — with an empty path, which cut every prefix
      # chain that runs through a package `__init__.py`. Fill those from
      # the symbol resolver, which names the package's `__init__.py`.
      if import_modules.any? { |_, info| info[0].empty? }
        Noir::ImportGraph::Python.find_imported_symbols(app_base_path, file_path, source).each do |name, symbol|
          existing = import_modules[name]?
          next unless existing && existing[0].empty?
          import_modules[name] = {symbol[0], existing[1]}
        end
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

        # `visited` holds two kinds of key. The bare router key marks the
        # routers on the current include path, so a cyclic include graph
        # stops instead of recursing forever. The router + inherited
        # prefix key memoises each configuration, so a router included
        # under two prefixes is configured once per prefix while a
        # diamond-shaped include graph is not re-walked once per path.
        visit_key = "#{file}::#{instance_name}"
        next if visited.includes?(visit_key)
        next unless visited.add?("#{visit_key}\0#{router_prefix}")
        visited.add(visit_key)

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
        mounted = Router.new(combine_router_prefixes(router_prefix, router_class.prefix))
        router_class.mounted_prefixes << mounted.prefix unless router_class.mounted_prefixes.includes?(mounted.prefix)

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

          # Register router's prefix recursively, so the included router's
          # OWN `include_router` calls are processed under the inherited
          # prefix too.
          if target = resolve_router_reference(file, source, import_modules, include_router_map, router_instance_name)
            configure_router_prefix(target[0], include_router_map, app_base_path, mounted.join(prefix), target[1], visited)
          end
        end

        # `app.mount("/sub", subapi)` serves the sub-application's routes
        # under the mount path, like an include_router prefix.
        extract_app_mount_calls(source, instance_name).each do |args|
          next unless mount = parse_app_mount(args, source, import_modules)
          if target = resolve_router_reference(file, source, import_modules, include_router_map, mount[1])
            configure_router_prefix(target[0], include_router_map, app_base_path, mounted.join(mount[0]), target[1], visited)
          end
        end
        visited.delete(visit_key)
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
      res = instance_regexes(instance_name)
      extract_instance_calls(source, "include_router", res.include_router_guard, res.include_router_call)
    end

    # Argument text of every `<instance>.mount(...)` that mounts an app
    # rather than `StaticFiles` (those are emitted as static routes).
    private def extract_app_mount_calls(source : ::String, instance_name : ::String) : Array(::String)
      res = instance_regexes(instance_name)
      extract_instance_calls(source, ".mount", res.mount_guard, res.static_mount).reject(&.includes?("StaticFiles"))
    end

    # Whether `instance` serves anything itself: a route decorator, an
    # `include_router` or an `add_api_route` in `source` (middleware and
    # event hooks do not count).
    private def declares_own_routes?(source : ::String, instance_name : ::String) : Bool
      res = instance_regexes(instance_name)
      e = Regex.escape(instance_name)
      source.matches?(/^\s*@\s*#{e}\s*\.\s*(?:get|post|put|patch|delete|head|options|trace|query|api_route|websocket)\s*\(/m) ||
        source.matches?(res.include_router_guard) || source.matches?(res.programmatic_guard)
    end

    private def extract_instance_calls(source : ::String, needle : ::String, guard : Regex, call : Regex) : Array(::String)
      calls = [] of ::String
      # One scan of the source before splitting it: most instances make
      # no such call, and this runs once per instance per file.
      return calls unless source.matches?(guard)
      lines = source.split("\n")
      lines.each_with_index do |line, index|
        stripped = line.lstrip
        next if stripped.starts_with?("#")
        next unless line.includes?(needle) && line.matches?(guard)

        logical_line = join_until_python_call_closes(lines, index, line)
        match = logical_line.match(call)
        calls << match[1] if match
      end
      calls
    end

    # `{prefix, target}` of an app mount: `mount("/sub", sub)` or
    # `mount(path="/sub", app=sub)`.
    private def parse_app_mount(args : ::String, source : ::String,
                                import_modules : Hash(::String, Tuple(::String, Int32))) : Tuple(::String, ::String)?
      positional = split_python_arguments(args).map(&.strip).reject(&.empty?).take_while { |arg| !top_level_keyword_argument?(arg) }
      target = extract_python_keyword_expression(args, "app").try(&.strip) || positional[1]?
      path_expr = positional[0]? || extract_python_keyword_expression(args, "path")
      return unless target && path_expr
      return unless path = resolve_string_expression(path_expr, source, import_modules)

      {path, target}
    end

    # `{file, instance}` a router or app reference used in `file` is
    # registered under: a same-file name, an imported name (aliases
    # translated back) or `module.attr`. Nil when it names nothing known.
    private def resolve_router_reference(file : ::String,
                                         source : ::String,
                                         import_modules : Hash(::String, Tuple(::String, Int32)),
                                         include_router_map : Hash(::String, Hash(::String, Router)),
                                         name : ::String) : Tuple(::String, ::String)?
      case name.count(".")
      when 0
        # A router included from the SAME file (e.g. dispatch's
        # `api_router.include_router(authenticated_organization_api_router)`).
        return {file, name} if include_router_map[file].has_key?(name)
        return unless imported = import_modules[name]?
        import_module_path = imported.first
        return unless target_map = include_router_map[import_module_path]?
        # The local name is frequently an alias
        # (`from .api import router as api_router`). The target
        # file registers the router under its ORIGINAL symbol
        # (`router`), so translate the alias back before recursing.
        # Passing the alias straight through made the
        # `target_instance_name` filter never match, silently
        # dropping the ENTIRE sub-router prefix tree — the dominant
        # FastAPI accuracy bug on real apps (fastapi-realworld,
        # Netflix/dispatch) that lean on `import router as X`.
        {import_module_path, resolve_original_import_name(source, name, target_map)}
      when 1
        module_name, attr = name.split(".")
        return unless imported = import_modules[module_name]?
        import_module_path = imported.first
        return unless include_router_map.has_key?(import_module_path)
        {import_module_path, attr}
      end
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

      aliased = false
      importing_source.each_line do |raw|
        stripped = raw.lstrip
        # Any line: a parenthesised import puts `router as users_router,`
        # on a line of its own.
        next unless stripped.includes?(" as ") && stripped.includes?(local_name)
        if match = stripped.match(/\b(#{PYTHON_VAR_NAME_REGEX})\s+as\s+#{Regex.escape(local_name)}\b/)
          original = match[1]
          return original if target_map.has_key?(original)
          aliased = true
        end
      end

      # An import under its own name that the file does not register names
      # something else (a router of a class noir does not know); handing it
      # the file's one router moved that router's prefix onto it.
      return target_map.first_key if aliased && target_map.size == 1

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
      # `String#[]` walks from the start on every call for non-ASCII
      # content, so indexing `value` directly inside this while loop was
      # O(n^2); `chars` (Array(Char)) gives O(1) random access instead.
      # `value.index`/range-slice stay on `value` — they only run once
      # per `{...}` placeholder found, not once per character.
      chars = value.chars
      result = String.build do |io|
        index = 0
        while index < chars.size
          if chars[index] == '{'
            if index + 1 < chars.size && chars[index + 1] == '{'
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
          elsif chars[index] == '}' && index + 1 < chars.size && chars[index + 1] == '}'
            io << '}'
            index += 2
          else
            io << chars[index]
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
      # `String#[]` walks from the start on every call for non-ASCII
      # content, so indexing `call_tail` directly inside this while loop
      # was O(n^2); `chars` gives O(1) random access instead.
      chars = call_tail.chars
      expression = String.build do |io|
        depth = 0
        in_quote = nil
        escaped = false
        while index < chars.size
          ch = chars[index]
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
                                               import_modules : Hash(::String, Tuple(::String, Int32)),
                                               path : ::String,
                                               base_path : ::String,
                                               depth : Int32 = 0) : Array(Param)
      params = [] of Param
      function_definition = parse_function_def(codelines, def_line)
      return params unless function_definition

      path_param_names = fastapi_path_param_names(route_path)

      function_definition.params.each do |param|
        next if param.name == "*" || path_param_names.includes?(param.name)
        next if param.name.in?(%w[self cls])
        next if param.type == "WebSocket"
        # `common: CommonParameters`, a module-level `Annotated[...]` alias:
        # read as the expression it names, in the file that assigns it.
        if depth < 3 && VAR_NAME_FULL_RE.matches?(param.type) &&
           (import_modules.has_key?(param.type) || source.includes?("Annotated") || source.includes?("import *")) &&
           (alias_site = annotated_alias(param.type, source, path, base_path))
          expression, alias_source, alias_path = alias_site
          default = param.default.empty? ? "" : " = #{param.default}"
          params.concat(extract_fastapi_handler_params(["def _(#{param.name}: #{expression}#{default}):"], 0, route_path, alias_source,
            find_fastapi_imported_modules(base_path, alias_path, alias_source), alias_path, base_path, depth + 1))
          next
        end
        # `Depends()` on a password-flow form model reads the two
        # `application/x-www-form-urlencoded` fields the client must send.
        if param.type.includes?("OAuth2PasswordRequestForm")
          params << Param.new("username", "", "form") << Param.new("password", "", "form")
          next
        end
        # `x: Model = Depends()` / `Depends(Model)`: FastAPI calls the
        # class, so its `__init__` parameters (or, for a Pydantic model, its
        # fields as query parameters) are what the request carries.
        if (dep_class = fastapi_class_dependency(param)) && depth < 3 &&
           (site = model_site(dep_class, source, path, base_path))
          params.concat(class_dependency_params(dep_class, site, base_path, depth))
          next
        end
        if fastapi_dependency_param?(param)
          # A dependency function's own parameters are request parameters
          # too: FastAPI resolves them for the route.
          params.concat(dependency_function_params(param, route_path, source, path, base_path, depth)) if depth < 3
          next
        end

        default_value = return_literal_value(param.default)
        param_type = infer_parameter_type(param.default) unless param.default.empty?
        if param_type.nil? && !param.type.empty?
          # `payload: dict[str, Any]` / `tags: list[str]` with no `Query()`
          # is a body field: only the outer type decides, not its `str`.
          if fastapi_peeled_type(param.type).try(&.matches?(BODY_CONTAINER_TYPE_RE)) && !param.type.matches?(LOCATION_MARKER_RE)
            param_type = "json"
          else
            param_type = param.type
            param_type = param_type.split("Annotated[", 2)[-1].split(",", 2)[-1] if param_type.includes?("Annotated[")
            param_type = param_type.split("Union[", 2)[-1] if param_type.includes?("Union[")
            param_type = infer_parameter_type(param_type, true)
          end
        else
          param_type = "query" if param_type.nil?
        end

        model = fastapi_model_name(param.type)

        # A lone `Body()` model is the request body itself; `embed=True`
        # nests it under the parameter name instead.
        if param_type == "json" && model && !fastapi_param_declaration(param).matches?(BODY_EMBED_RE)
          fields = model_params_for(model, param.name, source, path, base_path)
          unless fields.empty?
            params.concat(fields)
            next
          end
        end

        # `q: Annotated[FilterModel, Query()]` (likewise `Header()` /
        # `Cookie()`): a parameter model, whose fields each arrive there.
        if model && (location = param_type) && location.in?(%w[query header cookie]) && !fastapi_param_declaration(param).empty?
          fields = model_params_for(model, param.name, source, path, base_path, location)
          unless fields.empty?
            params.concat(fields)
            next
          end
        end

        if param_type.nil?
          next unless model
          if model.in?(%w[Request dict])
            function_codeblock = parse_code_block(codelines[def_line..])
            next if function_codeblock.nil?
            params.concat(find_dictionary_params(function_codeblock, FunctionParameter.new(param.name, model, param.default)))
          else
            params.concat(model_params_for(model, param.name, source, path, base_path))
          end
        else
          params << Param.new(fastapi_wire_name(param, param_type), default_value, param_type)
        end
      end

      params
    end

    private def fastapi_path_param_names(route_path : ::String) : Array(::String)
      names = [] of ::String
      route_path.scan(PATH_PARAM_REGEX) do |match|
        names << match[1] unless names.includes?(match[1])
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

    # Delegates to the shared splitter. `Rules::SHARED_DEPTH_RAW`, not
    # `Rules::PYTHON`: this loop counted `(`, `[` and `{` on ONE depth
    # counter, which is observable on the unbalanced fragments the route
    # regexes actually hand it. The two wrappers above stay local — the
    # `nil`-on-single-part contract of `split_python_expression` is a FastAPI
    # call-site convention, not a splitting rule.
    private def split_python_top_level(input : ::String, delimiter : Char) : Array(::String)
      Noir::TopLevelSplit.split(input, delimiter, Noir::TopLevelSplit::Rules::SHARED_DEPTH_RAW)
    end

    private def static_route_path(path : ::String) : ::String
      normalized = path.gsub(/\/+/, "/")
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized = normalized[0...-1] if normalized.ends_with?("/") && normalized != "/"
      normalized == "/" ? "/*" : "#{normalized}/*"
    end

    # The Python identifier a FastAPI handler declares is not always the name
    # the client sends. Two rules rewrite it, and Noir honored neither:
    #
    #   * `alias=` overrides the name outright, for every parameter class
    #     (`Header`, `Query`, `Cookie`, `Form`, `File`, `Body`, `Path`).
    #   * `Header` — and only `Header` — additionally maps `_` to `-`, because
    #     an HTTP header name can't carry an underscore in most stacks. That
    #     is `convert_underscores`, and it defaults to **True**; passing
    #     `convert_underscores=False` is what opts back out.
    #
    # Reporting the identifier verbatim is not a cosmetic mismatch: it is the
    # name Noir hands to the next stage. `-f curl` emitted `-H 'x_token: '`
    # for `x_token: str = Header(None)`, a header the app reads as nothing,
    # and a DAST tool importing the OpenAPI doc probed `?q_name=` for a
    # parameter the app only accepts as `q-name`.
    FASTAPI_PARAM_CLASS_RE    = /\b(?:Header|Query|Cookie|Path|Body|Form|File)\s*\(/
    NO_CONVERT_UNDERSCORES_RE = /\bconvert_underscores\s*=\s*False\b/

    # The same rename, one layer down. A request body is described by a
    # Pydantic model, and `Field(alias=...)` renames the key there too —
    # with `populate_by_name` off (the default) the alias is the *only* key
    # the model accepts, so the attribute name is a body field the app
    # rejects outright.
    MODEL_FIELD_CALL_RE = /\bField\s*\(/

    # `param_type` is Noir's resolved slot ("header", "query", ...), which is
    # what decides whether the underscore rule applies; the declaration text
    # is whichever of the default value or the annotation actually carries the
    # `Header(...)` / `Query(...)` call, since `Annotated[str, Header()]` puts
    # it in the annotation and `= Header()` puts it in the default.
    private def fastapi_wire_name(param : FunctionParameter, param_type : ::String) : ::String
      declaration = fastapi_param_declaration(param)
      return param.name if declaration.empty?

      if explicit = Helper.declared_alias(declaration)
        return explicit
      end

      return param.name unless param_type == "header"
      return param.name if declaration.matches?(NO_CONVERT_UNDERSCORES_RE)
      param.name.tr("_", "-")
    end

    # Gated on an actual parameter-class call so a plain default that merely
    # contains the text `alias=` (`mode: str = "alias=1"`) is left alone.
    private def fastapi_param_declaration(param : FunctionParameter) : ::String
      return param.default if param.default.matches?(FASTAPI_PARAM_CLASS_RE)
      return param.type if param.type.matches?(FASTAPI_PARAM_CLASS_RE)
      ""
    end

    # Same gate as `fastapi_param_declaration`: only a real `Field(...)`
    # call renames anything, so `note: str = "alias=x"` keeps its name.
    private def model_field_wire_name(attribute : ::String, default : ::String) : ::String
      return attribute unless default.matches?(MODEL_FIELD_CALL_RE)
      Helper.declared_alias(default) || attribute
    end

    # Infers the type of the parameter based on its default value or type annotation
    def infer_parameter_type(data : ::String, is_param_type = false) : ::String?
      # Whole names only: a `SigninForm` / `SearchQuery` model is a body,
      # not `Form()` / `Query()`.
      if data.matches?(/\bCookie\b/)
        "cookie"
      elsif data.matches?(/\bHeader\b/)
        "header"
      elsif data.matches?(/\bBody\b/)
        "json"
      elsif data.matches?(/\b(?:Form|File|UploadFile)\b/)
        "form"
      elsif data.matches?(/\bQuery\b/)
        "query"
      elsif data.matches?(/\bWebSocket\b/)
        "websocket"
      elsif data.matches?(/\bPath\s*\(/)
        "path"
      elsif is_param_type
        # default variable type
        # Whole names only: `CreateUserRegistration` is not a `str`.
        "query" if data.matches?(SCALAR_TYPE_RE)
      end
    end

    BODY_EMBED_RE         = /\bembed\s*=\s*True\b/
    MODEL_TYPE_WRAPPER_RE = /^(?:typing\.)?(Optional|Annotated|Union)\[(.*)\]$/m
    MODEL_FIELD_LINE_RE   = /^[A-Za-z]\w*\s*:/

    # The class a parameter annotation names once `Optional[...]`,
    # `Union[X, None]`, `X | None` and `Annotated[X, ...]` are peeled off;
    # nil when what is left is not a bare identifier.
    private def fastapi_model_name(type : ::String) : ::String?
      fastapi_peeled_type(type).try { |peeled| peeled if VAR_NAME_FULL_RE.matches?(peeled) }
    end

    # The annotation with `Optional[...]`, `Union[X, None]`, `X | None` and
    # `Annotated[X, ...]` peeled off; nil for a union of several types.
    private def fastapi_peeled_type(type : ::String) : ::String?
      type = type.strip
      loop do
        if match = type.match(MODEL_TYPE_WRAPPER_RE)
          args = split_python_top_level(match[2], ',').map(&.strip).reject(&.empty?)
          args = args.first(1) if match[1] == "Annotated"
          args = args.reject { |arg| arg == "None" }
          return unless args.size == 1
          type = args.first
        elsif type.includes?('|')
          args = split_python_top_level(type, '|').map(&.strip).reject { |arg| arg == "None" }
          # `list[A | B]` has its `|` inside brackets: the split hands the
          # same text back, which is not a bare name and would loop forever.
          return unless args.size == 1 && args.first != type
          type = args.first
        else
          break
        end
      end
      type
    end

    private def model_params_for(model : ::String, param_name : ::String, source : ::String,
                                 path : ::String, base_path : ::String, location : ::String = "json") : Array(Param)
      return [] of Param unless site = model_site(model, source, path, base_path)
      find_base_model_params(site[0], model, param_name, path: site[1], base_path: base_path, location: location)
    end

    SCALAR_TYPE_RE = /\b(?:str|int|float|bool|EmailStr)\b/
    # A bare `dict` keeps reading the keys the handler takes from it.
    BODY_CONTAINER_TYPE_RE = /\A(?:typing\.)?(?:dict\[|(?:Dict|list|List|set|Set|frozenset|FrozenSet|tuple|Tuple|Sequence)(?:\[|\z))/
    LOCATION_MARKER_RE     = /\b(?:Query|Header|Cookie|Body|Form|File|UploadFile|Path|WebSocket|Depends|Security)\b/
    STAR_IMPORT_RE         = /^from\s+([\w.]+)\s+import\s+\*/m
    ALIAS_GENERATOR_RE     = /\balias_generator\s*=\s*([\w.]+)/
    DEPENDS_EMPTY_RE       = /\bDepends\s*\(\s*\)/
    DEPENDS_CLASS_RE       = /\bDepends\s*\(\s*([A-Z]\w*)\s*\)/
    INIT_DEF_RE            = /^\s+(?:async\s+)?def\s+__init__\s*\(/

    # `{source, file}` declaring `class model`, as named from `path`: the
    # same file, else the module it is imported from, following package
    # re-exports (`from .auth import Model`, `from .auth import *` in an
    # `__init__.py`).
    #
    # With `function`, the same for a top-level `def model`.
    private def model_site(model : ::String, source : ::String, path : ::String, base_path : ::String,
                           depth : Int32 = 0, function : Bool = false, defined : Regex? = nil) : Tuple(::String, ::String)?
      escaped = Regex.escape(model)
      defined ||= function ? /^(?:async\s+)?def\s+#{escaped}\s*\(/m : /^\s*class\s+#{escaped}\s*[(:]/m
      return {source, path} if source.matches?(defined)
      return if depth > 5
      imports = find_fastapi_imported_modules(base_path, path, source)
      if (info = imports[model]?) && !info[0].empty? && info[0] != path
        return model_site(model, read_file_content(info[0]), info[0], base_path, depth + 1, function, defined)
      end
      source.scan(STAR_IMPORT_RE) do |m|
        target = Noir::ImportGraph::Python.find_imported_symbols(base_path, path, "from #{m[1]} import #{model}")[model]?
        next if target.nil? || target[0].empty? || target[0] == path
        if found = model_site(model, read_file_content(target[0]), target[0], base_path, depth + 1, function, defined)
          return found
        end
      end
      nil
    end

    @annotated_aliases = Hash(Tuple(::String, ::String), Tuple(::String, ::String, ::String)?).new

    # The `Annotated[...]` expression a module-level alias names
    # (`CommonParameters = Annotated[dict, Depends(f)]`, possibly over
    # several lines), with the source and path of the file assigning it,
    # followed through imports.
    private def annotated_alias(name : ::String, source : ::String, path : ::String,
                                base_path : ::String) : Tuple(::String, ::String, ::String)?
      @annotated_aliases.fetch({path, name}) do
        defined = /^#{Regex.escape(name)}\s*(?::[^=\n]+)?=\s*(?:[A-Za-z_]\w*\.)?Annotated\s*\[/m
        @annotated_aliases[{path, name}] = if site = model_site(name, source, path, base_path, defined: defined)
                                             fold_python_continuations(site[0].split("\n")).find(&.matches?(defined)).try do |line|
                                               {line.split('=', 2)[1].strip, site[0], site[1]}
                                             end
                                           end
      end
    end

    DEPENDS_CALLEE_RE = /\b(?:Depends|Security)\s*\(\s*(?:dependency\s*=\s*)?(#{PYTHON_VAR_NAME_REGEX}(?:\.#{PYTHON_VAR_NAME_REGEX})?)\s*[,)]/

    # The request parameters of the function a `Depends(func)` /
    # `Depends(module.func)` parameter calls, read from its definition.
    private def dependency_function_params(param : FunctionParameter, route_path : ::String, source : ::String,
                                           path : ::String, base_path : ::String, depth : Int32) : Array(Param)
      callee = param.default.match(DEPENDS_CALLEE_RE).try(&.[1]) || param.type.match(DEPENDS_CALLEE_RE).try(&.[1])
      return [] of Param unless callee
      module_name, _, name = callee.rpartition('.')
      site = if module_name.empty?
               model_site(name, source, path, base_path, function: true)
             elsif (info = find_fastapi_imported_modules(base_path, path, source)[module_name]?) && !info[0].empty?
               model_site(name, read_file_content(info[0]), info[0], base_path, function: true)
             end
      return [] of Param unless site
      lines = site[0].split("\n")
      def_re = /^(?:async\s+)?def\s+#{Regex.escape(name)}\s*\(/
      return [] of Param unless def_idx = lines.index(&.matches?(def_re))
      imports = find_fastapi_imported_modules(base_path, site[1], site[0])
      extract_fastapi_handler_params(lines, def_idx, route_path, site[0], imports, site[1], base_path, depth + 1)
    end

    CLASS_HEADER_RE          = /^(\s*)class\s+(#{PYTHON_VAR_NAME_REGEX})\s*(?:\(([^)]*)\))?\s*:/
    CLASS_DEPENDENCY_ATTR_RE = /^\s*#{PYTHON_VAR_NAME_REGEX}\s*(?::[^=]+)?=\s*(?:Depends|Security)\s*\(/

    # Request parameters a class-based view (`@cbv(router)`, a project
    # `@controller(router)`) injects into its route method at `index`:
    # the dependencies its class and in-project bases declare as
    # `name: T = Depends(...)` attributes, a subclass attribute shadowing a
    # base one of the same name.
    private def class_view_params(codelines : Array(::String), index : Int32, route_path : ::String,
                                  source : ::String, path : ::String, base_path : ::String) : Array(Param)
      params = [] of Param
      indent = codelines[index].size - codelines[index].lstrip.size
      return params if indent == 0
      class_idx = nil
      (index - 1).downto(0) do |idx|
        stripped = codelines[idx].lstrip
        next if stripped.empty? || stripped.starts_with?('#')
        next if codelines[idx].size - stripped.size >= indent
        class_idx = idx if codelines[idx].matches?(CLASS_HEADER_RE)
        break
      end
      return params unless class_idx
      attrs = [] of Tuple(::String, ::String, ::String)
      collect_class_view_attrs(codelines, class_idx, source, path, base_path, attrs, Set(::String).new)
      attrs.each do |_, statement, file|
        file_source = file == path ? source : read_file_content(file)
        imports = find_fastapi_imported_modules(base_path, file, file_source)
        extract_fastapi_handler_params(["def _(#{statement}):"], 0, route_path, file_source, imports, file, base_path, 1).each do |param|
          params << param unless params.any? { |known| known.name == param.name && known.param_type == param.param_type }
        end
      end
      params
    end

    private def collect_class_view_attrs(lines : Array(::String), class_idx : Int32, source : ::String, path : ::String,
                                         base_path : ::String, attrs : Array(Tuple(::String, ::String, ::String)),
                                         seen : Set(::String))
      header = lines[class_idx].match(CLASS_HEADER_RE) || return
      return if seen.size > 12 || !seen.add?("#{path}\0#{header[2]}")
      class_indent = header[1].size
      body_indent = nil
      ((class_idx + 1)...lines.size).each do |idx|
        stripped = lines[idx].lstrip
        next if stripped.empty? || stripped.starts_with?('#')
        line_indent = lines[idx].size - stripped.size
        break if line_indent <= class_indent
        body_indent ||= line_indent
        next unless line_indent == body_indent && stripped.matches?(CLASS_DEPENDENCY_ATTR_RE)
        statement = strip_python_comment(stripped).strip
        name = statement.split(/[\s:=]/, 2)[0]
        attrs << {name, statement, path} unless attrs.any? { |attr| attr[0] == name }
      end
      (header[3]? || "").split(',').each do |base|
        base = base.strip.sub(/\[.*\z/m, "")
        next unless VAR_NAME_FULL_RE.matches?(base)
        next unless site = model_site(base, source, path, base_path)
        base_lines = site[0].split("\n")
        next unless base_idx = base_lines.index(&.matches?(/^\s*class\s+#{Regex.escape(base)}\s*[(:]/))
        collect_class_view_attrs(base_lines, base_idx, site[0], site[1], base_path, attrs, seen)
      end
    end

    # The class a `Depends()` / `Depends(Class)` parameter instantiates.
    private def fastapi_class_dependency(param : FunctionParameter) : ::String?
      [param.default, param.type].each do |expression|
        next unless expression.includes?("Depends")
        if expression.matches?(DEPENDS_EMPTY_RE)
          annotated = param.type.includes?("Depends") ? param.type.sub(/,\s*Depends\s*\(\s*\)\s*\]\s*\z/, "]") : param.type
          return fastapi_model_name(annotated)
        elsif m = expression.match(DEPENDS_CLASS_RE)
          return m[1]
        end
      end
      nil
    end

    # What a class dependency reads from the request: its `__init__`
    # parameters, resolved like a handler's, or — without one — a Pydantic
    # model's fields as query parameters.
    private def class_dependency_params(class_name : ::String, site : Tuple(::String, ::String),
                                        base_path : ::String, depth : Int32) : Array(Param)
      source, file = site
      lines = source.split("\n")
      class_idx = lines.index(&.matches?(/^\s*class\s+#{Regex.escape(class_name)}\s*[(:]/)) || return [] of Param
      class_indent = lines[class_idx].size - lines[class_idx].lstrip.size
      ((class_idx + 1)...lines.size).each do |idx|
        line = lines[idx]
        stripped = line.lstrip
        next if stripped.empty? || stripped.starts_with?('#')
        break if line.size - stripped.size <= class_indent
        if line.matches?(INIT_DEF_RE)
          imports = find_fastapi_imported_modules(base_path, file, source)
          return extract_fastapi_handler_params(lines, idx, "", source, imports, file, base_path, depth + 1)
        end
      end
      find_base_model_params(source, class_name, class_name, path: file, base_path: base_path, location: "query")
    end

    # Finds the parameters for a base model class, base classes first
    # (Pydantic orders inherited fields that way): those declared in the
    # same source, else, given `path`, where the source imports them from.
    # Field names follow an inherited `alias_generator` named for camelCase
    # unless a `Field(alias=...)` names the field itself.
    def find_base_model_params(source : ::String, class_name : ::String, param_name : ::String,
                               visited : Set(::String) = Set(::String).new,
                               path : ::String? = nil, base_path : ::String? = nil,
                               location : ::String = "json") : Array(Param)
      fields = [] of Tuple(::String, Bool, ::String)
      result = collect_model_fields(source, class_name, param_name, visited, path, base_path, fields)
      return result if result.is_a?(Array(Param))
      camel = result
      fields.map do |name, explicit, default|
        Param.new(camel && !explicit ? name.split('_').map_with_index { |part, i| i == 0 ? part : part.capitalize }.join : name, default, location)
      end
    end

    # Fills `fields` with `{wire name, explicit alias?, default}` for
    # `class_name` and its bases, returning whether an alias generator
    # camelizes them (nil when none is set), or the enum shortcut params.
    private def collect_model_fields(source : ::String, class_name : ::String, param_name : ::String,
                                     visited : Set(::String), path : ::String?, base_path : ::String?,
                                     fields : Array(Tuple(::String, Bool, ::String))) : Bool? | Array(Param)
      return unless visited.add?(class_name)
      class_codeblock = parse_code_block(source, /\s*class\s*#{class_name}\s*\(/)
      return if class_codeblock.nil?

      lines = class_codeblock.split("\n")
      bases = lines[0].split("(", 2)[-1].split(")")[0]
      if bases.match(/(\b)*str,\s*(enum\.){0,1}Enum(\b)*/)
        return [Param.new(param_name.strip, "", "query")]
      end
      camel = nil.as(Bool?)
      split_python_top_level(bases, ',').each do |base|
        base = base.strip
        next if base == "BaseModel" || !VAR_NAME_FULL_RE.matches?(base)
        base_source = source
        base_file = path
        unless source.matches?(/^\s*class\s+#{Regex.escape(base)}\s*\(/m)
          next unless path && base_path && (site = model_site(base, source, path, base_path))
          base_source, base_file = site
        end
        inherited = collect_model_fields(base_source, base, param_name, visited, base_file, base_path, fields)
        camel = inherited if inherited.is_a?(Bool)
      end

      in_docstring = Helper.docstring_line_flags(lines)
      folded = fold_python_continuations(lines)
      body_indent = nil
      folded.each_with_index do |line, index|
        next if index == 0 || in_docstring[index]
        stripped = line.lstrip
        next if stripped.empty? || stripped.starts_with?('#')
        body_indent ||= line.size - stripped.size
        next unless line.size - stripped.size == body_indent
        if generator = stripped.match(ALIAS_GENERATOR_RE)
          camel = generator[1].downcase.includes?("camel")
        end
        next unless stripped.matches?(MODEL_FIELD_LINE_RE)

        field = parse_function_def(["def _(#{strip_python_comment(stripped)}):"], 0).try(&.params.first?)
        next if field.nil? || field.type.empty? || field.type.starts_with?("ClassVar")

        name = model_field_wire_name(field.name, field.default)
        fields.reject! { |existing| existing[0] == name }
        fields << {name, name != field.name, return_literal_value(field.default)}
      end

      camel
    end

    # Finds parameters in dictionary structures
    def find_dictionary_params(source : ::String, param : FunctionParameter) : Array(Param)
      new_params = [] of Param
      json_variable_names = [] of ::String
      # Comments out: `# request.query_params.get("old")` is not a read.
      codelines = source.split("\n").map { |line| strip_python_comment(line) }
      source = codelines.join('\n')
      if param.type == "Request"
        # Parse JSON variable names
        codelines.each do |codeline|
          next unless codeline.includes?(param.name) && codeline.includes?("json")
          match = codeline.match /(#{PYTHON_VAR_NAME_REGEX})\s*(?::\s*#{PYTHON_VAR_NAME_REGEX})?\s*=\s*(await\s*){0,1}#{param.name}.json\(\)/
          json_variable_names << match[1] if !match.nil? && !json_variable_names.includes?(match[1])
        end

        new_params = find_json_params(codelines, json_variable_names)

        # Starlette `Request` accessors read in the handler body:
        # `request.query_params.get("q")`, `request.headers["x-token"]`, ...
        attr_re = @request_attr_regex_cache[param.name] ||=
          /(?<![\w.])#{Regex.escape(param.name)}\.(query_params|headers|cookies)(?:\[\s*['"]([^'"]+)['"]\s*\]|\.get(?:list)?\(\s*['"]([^'"]+)['"])/
        source.scan(attr_re) do |m|
          found = Param.new((m[2]? || m[3]).to_s, "", REQUEST_ATTR_TYPES[m[1]])
          new_params << found unless new_params.any? { |p| p.name == found.name && p.param_type == found.param_type }
        end
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
      join_until_python_call_closes(codelines, index, line)
    end

    private def coalesce_mount_call(codelines : Array(::String),
                                    index : Int32,
                                    line : ::String,
                                    instance_name : ::String) : ::String
      return line unless line.matches?(instance_regexes(instance_name).mount_guard)
      join_until_python_call_closes(codelines, index, line)
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
      join_until_python_call_closes(codelines, index, line)
    end
  end

  # Router class for handling URL prefix joining
  class Router
    property prefix : ::String
    # Effective prefixes this router is served under, one per inclusion
    # path from an app (`include_router(r, prefix="/v1")` and again under
    # "/v2" gives two). Empty when no app includes it.
    getter mounted_prefixes = [] of ::String

    def initialize(@prefix : ::String)
    end

    # One router per mounted prefix, or itself when never included.
    def mounts : Array(Router)
      return [self] if @mounted_prefixes.empty?
      @mounted_prefixes.map { |mounted_prefix| Router.new(mounted_prefix) }
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
  end
end
