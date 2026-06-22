require "../../../miniparsers/python"
require "../../../miniparsers/python_route_extractor"
require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"

module Analyzer::Python
  class Flask < PythonEngine
    alias ScopedNameKey = Tuple(::String, ::String)

    # Reference: https://stackoverflow.com/a/16664376
    # Reference: https://tedboy.github.io/flask/generated/generated/flask.Request.html
    REQUEST_PARAM_FIELDS = {
      "data"    => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "args"    => {["GET"], "query"},
      "form"    => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "files"   => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "values"  => {["GET", "POST", "PUT", "PATCH", "DELETE"], "query"},
      "json"    => {["POST", "PUT", "PATCH", "DELETE"], "json"},
      "cookies" => {nil, "cookie"},
      "headers" => {nil, "header"},
    }

    # `extract_request_params` runs once per route and used to rebuild
    # two PCRE2 patterns per request field on every call (8 fields × 2 =
    # 16 regex compilations per endpoint). PCRE2 JIT-compilation of an
    # interpolated regex literal is ~3µs and dominated Flask scan time
    # (profiling: ~50% of the analyzer). The field names are a fixed set,
    # so precompile the access patterns once here and reuse them.
    # Tuple shape: {noir_param_type, bracket_access_regex, get_access_regex}
    REQUEST_PARAM_FIELD_PATTERNS = REQUEST_PARAM_FIELDS.map do |field_name, tuple|
      {
        tuple[1],
        Regex.new("request\\.#{field_name}\\[[rf]?['\"]([^'\"]*)['\"]\\]"),
        Regex.new("request\\.#{field_name}\\.get\\([rf]?['\"]([^'\"]*)['\"]"),
      }
    end

    REQUEST_PARAM_TYPES = {
      "query"  => nil,
      "form"   => ["POST", "PUT", "PATCH", "DELETE"],
      "json"   => ["POST", "PUT", "PATCH", "DELETE"],
      "cookie" => nil,
      "header" => nil,
    }

    # Per-line route-discovery patterns. These interpolate only the
    # PYTHON_VAR_NAME_REGEX/DOT_NATION constants, so the inline literals
    # were recompiling identical PCRE2 patterns on every source line of
    # every file (`analyze` runs them per line). Compile once here; the
    # `.to_s` expansion of the interpolated constants is byte-identical
    # to the previous inline form, so matching behaviour is unchanged.
    FLASK_INSTANCE_RE     = /(#{PYTHON_VAR_NAME_REGEX})(?::#{DOT_NATION})?=(?:flask\.)?Flask\(/
    INIT_APP_RE           = /(#{PYTHON_VAR_NAME_REGEX})\.init_app\((#{PYTHON_VAR_NAME_REGEX})/
    REGISTER_BLUEPRINT_RE = /(#{PYTHON_VAR_NAME_REGEX})\.register_blueprint\((#{DOT_NATION})/

    # Source-ownership and add_url_rule helpers — same constant-only
    # interpolation (DOT_NATION), hoisted so the per-file/per-call sites
    # don't recompile them. VIEW_FUNC_KWARG_RE has no whitespace tolerance
    # (unlike Quart's) because Flask's add_url_rule args are matched on
    # space-stripped lines.
    ROUTE_DECORATOR_RE  = /^\s*@\s*#{DOT_NATION}\s*\.\s*(?:route|get|post|put|patch|delete|head|options|trace)\s*\(/m
    ROUTE_REGISTRAR_RE  = /\b#{DOT_NATION}\s*\.\s*(?:add_url_rule|register_blueprint)\s*\(/
    VIEW_FUNC_KWARG_RE  = /view_func=(#{DOT_NATION})(?:,|\)|$)/
    DOTTED_REFERENCE_RE = /^#{DOT_NATION}$/
    VIEW_ASSIGN_RE      = /(#{PYTHON_VAR_NAME_REGEX})(?::#{DOT_NATION})?=(#{PYTHON_VAR_NAME_REGEX})\.as_view\(/
    ADD_URL_RULE_RE     = /(#{PYTHON_VAR_NAME_REGEX})\.add_url_rule\((.+)\)/m

    # flask_restful / flask-restx register class-based `Resource`s with
    # `api.add_resource(ResourceClass, "/url"[, "/url2"], endpoint=...)`.
    # Each Resource exposes one endpoint per HTTP-verb method it defines.
    # Hoisted for the common (alias-free) case so the per-file regex isn't
    # recompiled; `ADD_RESOURCE_SUBSTRING` is the cheap per-line guard.
    ADD_RESOURCE_RE         = /(#{PYTHON_VAR_NAME_REGEX})\s*\.\s*add_resource\s*\((.+)\)/m
    ADD_RESOURCE_SUBSTRINGS = [".add_resource("]
    # `def add_x(self, resource, ...)` head of an Api-subclass method that
    # may wrap `add_resource` (e.g. redash's `add_org_resource`).
    RESOURCE_REGISTRAR_DEF_RE = /^(\s*)(?:async\s+)?def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\s*self\s*,\s*resource\b/

    @file_content_cache = Hash(::String, ::String).new
    @parsers = Hash(::String, PythonParser).new
    @routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String))).new
    @class_views = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String, ::String, Array(::String)))).new

    def analyze
      flask_instances = Hash(ScopedNameKey, ::String).new
      blueprint_prefixes = Hash(ScopedNameKey, ::String).new
      path_api_instances = Hash(::String, Hash(::String, ::String)).new
      register_blueprint = Hash(::String, Hash(::String, ::String)).new
      blueprint_mounts = Hash(::String, Array(Tuple(::String, ::String, ::String))).new
      # flask-restx namespaces are module-level singletons: the Api host
      # file (`api/__init__.py`) wires `api.add_namespace(ns, "/x")` with
      # the blueprint's `url_prefix` (`/api/v1`), but each namespace's
      # ROUTES live in a different file (`api/v1/x.py`). `path_api_instances`
      # is per-file, so the route file never saw the host-computed prefix
      # and every `@ns.route` surfaced without `/api/v1`. This GLOBAL map
      # (namespace var name -> fully-resolved prefix) bridges the two files.
      namespace_prefixes = Hash(ScopedNameKey, ::String).new

      # Iterate through all Python files in all base paths. Pulls from
      # the detector-built file_map so subtree pruning and --exclude-path
      # apply; current_base_path is still needed further down for import
      # resolution, so keep the outer loop and filter by prefix.
      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        flask_instances[{current_base_path, "app"}] ||= "" # Common flask instance name
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          next if path.includes?("/site-packages/")
          next if python_test_path?(path)
          @logger.debug "Analyzing #{path}"

          file_content = fetch_file_content(path)
          lines = file_content.lines
          if flask_relevant_source?(file_content)
            extract_flask_appbuilder_exposed_endpoints(path, file_content).each do |endpoint|
              result << endpoint
            end
            next if flask_appbuilder_only_source?(file_content)

            api_instances = Hash(::String, ::String).new
            path_api_instances[path] = api_instances
            view_assignments = Hash(::String, ::String).new # Maps view_var -> ClassName (per-file scope)
            import_map_cache : Hash(::String, Tuple(::String, Int32))? = nil

            # add_resource registrars: the standard `add_resource` plus any
            # Api-subclass wrapper methods defined in this file. Alias-free
            # files (the overwhelming majority) reuse the hoisted constants
            # so nothing is recompiled or allocated per file.
            registrar_aliases = collect_resource_registrar_aliases(file_content)
            if registrar_aliases.nil?
              add_resource_re = ADD_RESOURCE_RE
              registrar_substrings = ADD_RESOURCE_SUBSTRINGS
            else
              alt = (["add_resource"] + registrar_aliases).map { |r| Regex.escape(r) }.join("|")
              add_resource_re = /(#{PYTHON_VAR_NAME_REGEX})\s*\.\s*(?:#{alt})\s*\((.+)\)/m
              registrar_substrings = (["add_resource"] + registrar_aliases).map { |r| ".#{r}(" }
            end

            # Tree-sitter pre-pass: parse the file once and pull out every
            # `@<router>.route(...)`/`@<router>.<method>(...)` decorator and
            # every `<name> = (flask.)?Blueprint(url_prefix=...)` declaration.
            # Both pieces used to be rediscovered with a fresh regex on every
            # single line; the parse is linear in file size instead of
            # (lines × patterns) and also handles multi-line decorators that
            # the regex can't see.
            ts_decorations = Noir::TreeSitterPythonRouteExtractor.extract_decorations(file_content)
            decorations_by_line = Hash(Int32, Array(Noir::TreeSitterPythonRouteExtractor::Decoration)).new
            ts_decorations.each do |d|
              decorations_by_line[d.decorator_line] ||= [] of Noir::TreeSitterPythonRouteExtractor::Decoration
              decorations_by_line[d.decorator_line] << d
            end
            Noir::TreeSitterPythonRouteExtractor.extract_blueprints(file_content, ["flask"]).each do |bp|
              blueprint_prefixes[{current_base_path, bp.name}] ||= bp.prefix
              api_instances[bp.name] ||= bp.prefix
            end

            lines.each_with_index do |original_line, line_index|
              next if original_line.lstrip.starts_with?("#")

              line = original_line.gsub(" ", "") # remove spaces for easier regex matching

              # Identify Flask instance assignments
              flask_match = line.includes?("Flask(") ? line.match(FLASK_INSTANCE_RE) : nil
              if flask_match
                flask_instance_name = flask_match[1]
                api_instances[flask_instance_name] ||= ""
                flask_instances[{current_base_path, flask_instance_name}] ||= ""

                effective_constructor = if python_paren_delta(original_line) > 0
                                          join_until_python_call_closes(lines, line_index, original_line)
                                        else
                                          original_line
                                        end
                if static_url_path = extract_flask_static_url_path(effective_constructor)
                  result << Endpoint.new(static_route_path(static_url_path), "GET", Details.new(PathInfo.new(path, line_index + 1)))
                end
              end
              # (Blueprint discovery moved to the tree-sitter pre-pass above.)

              # Identify Api instance assignments
              init_app_match = line.includes?(".init_app(") ? line.match(INIT_APP_RE) : nil
              if init_app_match
                api_instance_name = init_app_match[1]
                parser = get_parser(path)
                if parser.@global_variables.has_key?(api_instance_name)
                  gv = parser.@global_variables[api_instance_name]
                  api_instances[api_instance_name] ||= ""
                end
              end

              # `Api(...)` and `add_namespace(...)` calls routinely wrap
              # across lines (`X = Api(\n  blueprint,\n  ...\n)`), which
              # hid the blueprint/app argument from the single-line regex
              # and broke the whole `blueprint url_prefix -> Api -> namespace`
              # chain. Coalesce continuation lines when the call is
              # unbalanced so the argument is visible.
              api_line = if line.includes?("Api(") && python_paren_delta(original_line) > 0
                           join_until_python_call_closes(lines, line_index, original_line).gsub(" ", "")
                         else
                           line
                         end

              # `Api(...)` registration matchers interpolate the discovered
              # instance name, so they can't be hoisted to a constant.
              # Most lines never mention `Api(`; skip the per-instance
              # regex builds entirely unless the call is present (the
              # match itself requires the literal `Api(`).
              if api_line.includes?("Api(")
                # flask_restful / flask-restx `Api(app, prefix="/api/v1")`
                # prepends the prefix to every resource. The kwarg sits on
                # the same (coalesced) Api(...) call; anchor on `(`/`,` so
                # Blueprint's `url_prefix=` can't be mistaken for it.
                api_kwarg_prefix = api_line.match(/[,(]prefix=[rf]?['"]([^'"]*)['"]/).try(&.[1]) || ""

                # Api from flask instance
                flask_instances.each do |key, _prefix|
                  next unless key[0] == current_base_path
                  _flask_instance_name = key[1]
                  api_match = api_line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{DOT_NATION})?=(?:flask_restx\.)?Api\((app=)?#{_flask_instance_name}[,)]/
                  if api_match
                    api_instance_name = api_match[1]
                    api_instances[api_instance_name] ||= join_flask_paths(_prefix, api_kwarg_prefix)
                  end
                end

                # Api from blueprint instance
                blueprint_prefixes.each do |key, _prefix|
                  next unless key[0] == current_base_path
                  _blueprint_instance_name = key[1]
                  api_match = api_line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{DOT_NATION})?=(?:flask_restx\.)?Api\((app=)?#{_blueprint_instance_name}[,)]/
                  if api_match
                    api_instance_name = api_match[1]
                    api_instances[api_instance_name] ||= join_flask_paths(_prefix, api_kwarg_prefix)
                  end
                end
              end

              # Api Namespace
              ns_line = if line.includes?(".add_namespace(") && python_paren_delta(original_line) > 0
                          join_until_python_call_closes(lines, line_index, original_line).gsub(" ", "")
                        else
                          line
                        end
              # `add_namespace` matchers interpolate the instance name and
              # can't be hoisted; skip the per-instance regex builds unless
              # the call is present on this line (the match requires it).
              if ns_line.includes?(".add_namespace(")
                api_instances.each do |_api_instance_name, _prefix|
                  add_namespace_match = ns_line.match /(#{_api_instance_name})\.add_namespace\((#{PYTHON_VAR_NAME_REGEX})/
                  if add_namespace_match
                    parser = get_parser(path)
                    if parser.@global_variables.has_key?(add_namespace_match[2])
                      gv = parser.@global_variables[add_namespace_match[2]]
                      if gv.type == "Namespace"
                        # Prefer the explicit mount path on
                        # `add_namespace(ns, "/x")` (authoritative); fall
                        # back to the Namespace(...) definition's own
                        # path=/name when no positional path is given.
                        resolved = if mount_path = extract_add_namespace_path(ns_line, _api_instance_name, add_namespace_match[2])
                                     joined = File.join(_prefix, mount_path)
                                     joined.starts_with?("/") ? joined : "/#{joined}"
                                   else
                                     extract_namespace_prefix(parser, add_namespace_match[2], _prefix)
                                   end
                        api_instances[gv.name] = resolved
                        # Bridge to the namespace's route-definition file,
                        # which has no view onto this host file's prefixes.
                        namespace_prefixes[{current_base_path, gv.name}] = resolved
                      end
                    end
                  end
                end
              end

              # Temporary Addition: register_view
              # The `blueprint,routes=[...]` matcher interpolates the
              # blueprint name; skip the per-blueprint regex builds unless
              # this line actually carries a `routes=` registration.
              if line.includes?("routes=")
                blueprint_prefixes.each do |key, blueprint_prefix|
                  next unless key[0] == current_base_path
                  blueprint_name = key[1]
                  view_registration_match = line.match /#{blueprint_name},routes=(.*)\)/
                  if view_registration_match
                    # Re-extract route paths from original line to preserve spaces in paths
                    original_registration_match = original_line.match /#{blueprint_name}\s*,\s*routes\s*=\s*(.*)\)/
                    route_paths = original_registration_match ? original_registration_match[1] : view_registration_match[1]
                    route_paths.scan /['"]([^'"]*)['"]/ do |path_str_match|
                      if !path_str_match.nil? && path_str_match.size == 2
                        route_path = path_str_match[1]
                        # Parse methods from reference views (TODO)
                        route_url = "#{blueprint_prefix}#{route_path}"
                        route_url = "/#{route_url}" unless route_url.starts_with?("/")
                        details = Details.new(PathInfo.new(path, line_index + 1))
                        result << Endpoint.new(route_url, "GET", details)
                      end
                    end
                  end
                end
              end

              # Identify Blueprint registration
              register_blueprint_match = line.includes?(".register_blueprint(") ? line.match(REGISTER_BLUEPRINT_RE) : nil
              if register_blueprint_match
                parent_name = register_blueprint_match[1]
                blueprint_name = register_blueprint_match[2]
                url_prefix_match = original_line.match /url_prefix\s*=\s*[rf]?['"]([^'"]*)['"]/
                blueprint_mount_prefix = url_prefix_match ? url_prefix_match[1] : ""
                blueprint_mounts[path] ||= [] of Tuple(::String, ::String, ::String)
                blueprint_mounts[path] << {parent_name, blueprint_name, blueprint_mount_prefix}

                if url_prefix_match
                  resolved = false
                  parser = get_parser(path)
                  if parser.@global_variables.has_key?(blueprint_name)
                    gv = parser.@global_variables[blueprint_name]
                    if gv.type == "Blueprint"
                      register_blueprint[gv.path] ||= Hash(::String, ::String).new
                      register_blueprint[gv.path][blueprint_name] = url_prefix_match[1]
                      resolved = true
                    end
                  end

                  # Cross-file resolution: resolve imported blueprint via import map
                  unless resolved
                    import_map_cache ||= find_imported_modules(current_base_path, path)
                    if import_map_cache.has_key?(blueprint_name)
                      source_file, _package_type = import_map_cache[blueprint_name]
                      if !source_file.empty? && File.exists?(source_file)
                        register_blueprint[source_file] ||= Hash(::String, ::String).new
                        register_blueprint[source_file][blueprint_name] = url_prefix_match[1]
                      end
                    end
                  end
                end
              end

              # Flask route decorators (`@<router>.route(...)`,
              # `@<router>.<method>(...)`) are discovered in the tree-sitter
              # pre-pass above. Look up this line in the resulting map;
              # the downstream consumer still expects an `extra_params`
              # string of the shape `methods=['GET','POST']`, so we
              # synthesise it from the structured method list here.
              if ts_hits = decorations_by_line[line_index]?
                ts_hits.each do |decoration|
                  methods_literal = decoration.methods.map { |m| "'#{m}'" }.join(",")
                  extra_params = "methods=[#{methods_literal}]"
                  router_info = Tuple(Int32, ::String, ::String, ::String).new(line_index, path, decoration.path, extra_params)
                  @routes[decoration.router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String)
                  @routes[decoration.router_name] << router_info
                end
              end

              # Identify view assignments: view_var = ClassName.as_view('name')
              # Note: spaces are already removed from line at this point
              view_assign_match = line.includes?(".as_view(") ? line.match(VIEW_ASSIGN_RE) : nil
              if view_assign_match
                view_var = view_assign_match[1]
                class_name = view_assign_match[2]
                view_assignments[view_var] = class_name
              end

              # Identify add_url_rule() registrations for class-based views
              # Match the call generically, then extract rule/view_func from any argument position
              has_add_url_rule = line.includes?(".add_url_rule(")
              effective_add_url_rule = if has_add_url_rule && python_paren_delta(original_line) > 0
                                         join_until_python_call_closes(lines, line_index, original_line)
                                       else
                                         original_line
                                       end
              # `line` is already original_line space-stripped, so only
              # re-strip when we coalesced continuation lines; otherwise
              # reuse it instead of allocating a new gsub copy per line.
              effective_add_url_rule_stripped = has_add_url_rule ? effective_add_url_rule.gsub(" ", "") : line
              effective_add_url_rule_stripped.scan(ADD_URL_RULE_RE) do |_match|
                next if _match.size == 0
                router_name = _match[1]
                args_str = _match[2]

                # Extract route path from original line to preserve spaces in paths
                # Try rule= keyword first, then first positional string arg
                route_path = ""
                original_args_match = effective_add_url_rule.match /\.add_url_rule\((.+)\)/m
                original_args = original_args_match ? original_args_match[1] : args_str
                rule_match = original_args.match /rule\s*=\s*[rf]?['"]([^'"]*)['"]/
                if rule_match
                  route_path = rule_match[1]
                else
                  first_str_match = original_args.match /^\s*[rf]?['"]([^'"]*)['"]/
                  route_path = first_str_match[1] if first_str_match
                end
                next if route_path.empty?

                class_name = ""
                view_name = ""

                # Extract view_func: try keyword form, then positional form
                # Keyword: view_func=ClassName.as_view('name') or view_func=view_var
                view_func_match = args_str.match /view_func=(#{PYTHON_VAR_NAME_REGEX})\.as_view\([rf]?['"]([^'"]*)['"]\)/
                if view_func_match
                  class_name = view_func_match[1]
                  view_name = view_func_match[2]
                else
                  view_var_match = args_str.match /view_func=(#{PYTHON_VAR_NAME_REGEX})[,\)]/
                  if view_var_match
                    view_var = view_var_match[1]
                    if view_assignments.has_key?(view_var)
                      class_name = view_assignments[view_var]
                      view_name = view_var
                    end
                  end
                end

                # Positional: add_url_rule('/path', 'endpoint', view_var) or
                #             add_url_rule('/path', 'endpoint', Class.as_view('name'))
                # After space-stripping: '/path','endpoint',view_var
                if class_name.empty?
                  # Split positional args respecting nested parentheses
                  positional_parts = [] of ::String
                  remaining = args_str
                  while !remaining.empty?
                    # Match a quoted string argument
                    str_match = remaining.match /^[rf]?['"][^'"]*['"]/
                    if str_match
                      positional_parts << str_match[0]
                      remaining = remaining[str_match[0].size..]
                      remaining = remaining.lstrip(',')
                      next
                    end
                    # Stop at keyword arguments
                    break if remaining.match /^#{PYTHON_VAR_NAME_REGEX}=/
                    # Match an expression, tracking paren depth to handle nested calls like .as_view('name')
                    paren_depth = 0
                    end_idx = 0
                    while end_idx < remaining.size
                      ch = remaining[end_idx]
                      if ch == '('
                        paren_depth += 1
                      elsif ch == ')'
                        break if paren_depth == 0
                        paren_depth -= 1
                      elsif ch == ',' && paren_depth == 0
                        break
                      end
                      end_idx += 1
                    end
                    if end_idx > 0
                      positional_parts << remaining[0...end_idx]
                      remaining = remaining[end_idx..]
                      remaining = remaining.lstrip(',')
                      next
                    end
                    break
                  end

                  # Flask signature: add_url_rule(rule, endpoint=None, view_func=None, ...)
                  # 2nd or 3rd positional arg can be view_func
                  view_arg = if positional_parts.size >= 3
                               positional_parts[2]
                             elsif positional_parts.size == 2
                               positional_parts[1]
                             else
                               ""
                             end

                  unless view_arg.empty?
                    as_view_match = view_arg.match /(#{PYTHON_VAR_NAME_REGEX})\.as_view\([rf]?['"]([^'"]*)['"]\)/
                    if as_view_match
                      class_name = as_view_match[1]
                      view_name = as_view_match[2]
                    elsif view_assignments.has_key?(view_arg)
                      class_name = view_assignments[view_arg]
                      view_name = view_arg
                    end
                  end
                end

                if class_name.empty?
                  # Function-view registration:
                  #   app.add_url_rule("/x", "name", view_func=fn)
                  #   app.add_url_rule("/x", "name", view_func=fn, methods=["GET", "POST"])
                  # The class-view branch above only fires for
                  # `.as_view(...)` shapes; bare function refs fell
                  # through. Resolve the function body when it is in
                  # this file so params/callees match decorator routes.
                  fn_name = extract_add_url_rule_function_name(args_str)
                  fn_path = path
                  fn_source = file_content
                  fn_lines = lines
                  fn_def_index = fn_name.empty? || fn_name.includes?(".") ? nil : find_function_def(lines, fn_name)
                  if fn_def_index.nil? && !fn_name.empty?
                    import_map_cache ||= find_imported_modules(current_base_path, path, file_content)
                    if resolved = resolve_external_function_view(fn_name, path, import_map_cache)
                      fn_path, resolved_name = resolved
                      if File.exists?(fn_path)
                        fn_source = fetch_file_content(fn_path)
                        fn_lines = fn_source.lines
                        fn_def_index = find_function_def(fn_lines, resolved_name)
                      end
                    end
                  end

                  fn_codeblock = fn_def_index.nil? ? nil : parse_code_block(fn_lines[fn_def_index..])
                  fn_codeblock_lines = fn_codeblock.nil? ? [] of ::String : fn_codeblock.split("\n")

                  fn_methods = [] of ::String
                  fn_methods_match = args_str.match /methods=[\[\(](.*?)[\]\)]/m
                  if fn_methods_match
                    fn_methods_match[1].scan(/['"]([A-Za-z]+)['"]/) do |method_match|
                      method = method_match[1].upcase
                      fn_methods << method if HTTP_METHODS.any? { |hm| hm.upcase == method }
                    end
                  end
                  fn_methods << "GET" if fn_methods.empty?

                  api_instances_for_fn = path_api_instances[path]?
                  fn_prefix = (api_instances_for_fn && api_instances_for_fn.has_key?(router_name)) ? api_instances_for_fn[router_name] : ""
                  fn_full_path = "#{fn_prefix}#{route_path}"
                  fn_full_path = "/#{fn_full_path}" unless fn_full_path.starts_with?("/")

                  fn_methods.each do |m|
                    fn_details = Details.new(PathInfo.new(path, line_index + 1))
                    fn_params = fn_codeblock_lines.empty? ? [] of Param : get_filtered_params(m, extract_request_params(fn_codeblock_lines))
                    endpoint = Endpoint.new(fn_full_path, m, fn_params)
                    endpoint.details = fn_details

                    unless fn_codeblock.nil? || fn_def_index.nil?
                      push_callees_from(
                        endpoint,
                        fn_codeblock,
                        fn_def_index,
                        fn_path,
                        definition_base_path: base_path_for(fn_path),
                        source: fn_source,
                      )
                    end

                    result << endpoint
                  end
                else
                  # Extract methods list
                  methods = [] of ::String
                  methods_match = args_str.match /methods=[\[\(](.*?)[\]\)]/m
                  if methods_match
                    methods_str = methods_match[1]
                    methods_str.scan(/['"]([A-Za-z]+)['"]/) do |method_match|
                      method = method_match[1].upcase
                      methods << method if HTTP_METHODS.any? { |hm| hm.upcase == method }
                    end
                  end

                  # Store class view registration
                  class_view_info = Tuple(Int32, ::String, ::String, ::String, ::String, Array(::String)).new(
                    line_index, path, route_path, class_name, view_name, methods
                  )
                  @class_views[router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String, ::String, Array(::String))
                  @class_views[router_name] << class_view_info
                end
              end

              # flask_restful / flask-restx `api.add_resource(Resource,
              # "/url"[, "/url2"], endpoint=...)` (and Api-subclass wrapper
              # methods collected above). Register each URL as a class-view
              # against the api instance; the @class_views consumer below
              # then resolves the Resource class (cross-file aware) and
              # infers one endpoint per HTTP-verb method it defines.
              if registrar_substrings.any? { |s| line.includes?(s) }
                effective_add_resource = python_paren_delta(original_line) > 0 ? join_until_python_call_closes(lines, line_index, original_line) : original_line
                if ar_match = effective_add_resource.match(add_resource_re)
                  router_name = ar_match[1]
                  arg_parts = split_python_call_args(ar_match[2])
                  unless arg_parts.empty?
                    resource_class = arg_parts[0].strip
                    resource_class = resource_class.split(".").last if resource_class.includes?(".")
                    if resource_class.matches?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
                      arg_parts[1..].each do |raw_part|
                        part = raw_part.strip
                        break if part.matches?(/\A#{PYTHON_VAR_NAME_REGEX}\s*=/) # keyword args terminate the URL list
                        url_match = part.match(/\A[rf]?['"]([^'"]*)['"]\z/)
                        next unless url_match
                        @class_views[router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String, ::String, Array(::String))
                        @class_views[router_name] << Tuple(Int32, ::String, ::String, ::String, ::String, Array(::String)).new(
                          line_index, path, url_match[1], resource_class, "", [] of ::String
                        )
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      # Update the API instances with the blueprint prefixes
      own_api_instances = clone_path_api_instances(path_api_instances)
      register_blueprint.each do |path, blueprint_info|
        blueprint_info.each do |blueprint_name, blueprint_prefix|
          if path_api_instances.has_key?(path)
            api_instances = path_api_instances[path]
            own_prefix = api_instances[blueprint_name]? || ""
            api_instances[blueprint_name] = File.join(blueprint_prefix, own_prefix)
          end
        end
      end
      apply_nested_blueprint_prefixes(path_api_instances, own_api_instances, blueprint_mounts)

      # Iterate through the routes and extract endpoints
      @routes.each do |router_name, router_info_list|
        router_info_list.each do |router_info|
          line_index, path, route_path, extra_params = router_info
          lines = fetch_file_content(path).lines
          expect_params, class_def_index = extract_params_from_decorator(path, lines, line_index)
          api_instances = path_api_instances[path]
          route_base_path = base_path_for(path)
          namespace_prefix = namespace_prefixes[{route_base_path, router_name}]?
          if api_instances.has_key?(router_name)
            prefix = api_instances[router_name]
          elsif namespace_prefix
            # flask-restx namespace whose `add_namespace(...)` (with the
            # blueprint url_prefix) was resolved in a different file.
            prefix = namespace_prefix
          else
            parser = get_parser(path)
            prefix = extract_namespace_prefix(parser, router_name, "")
          end

          is_class_router = false
          indent = lines[class_def_index].size - lines[class_def_index].lstrip.size
          unless lines[class_def_index].lstrip.starts_with?("def ") || lines[class_def_index].lstrip.starts_with?("async def ")
            if lines[class_def_index].lstrip.starts_with?("class ")
              indent = lines[class_def_index].size - lines[class_def_index].lstrip.size
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
            http_verb = HTTP_METHODS.find { |http_method| _function_name.downcase == http_method.downcase }

            if is_class_router
              # A class router is a flask-restx `Resource` / Flask
              # `MethodView`: each HTTP-verb-named method IS a distinct
              # endpoint verb (def get -> GET, def delete -> DELETE).
              # Non-verb methods are helpers — skip them so they don't
              # emit a phantom GET. Previously the decorator's default
              # `methods=['GET']` (`.route` has no explicit verb)
              # overrode the per-method verb in `get_endpoints`, so a
              # Resource with get+post+delete collapsed to a single GET.
              next unless http_verb

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
            method = http_verb ? http_verb.upcase : "GET"
            # For class routers the per-method verb is authoritative; the
            # decorator's synthesized `methods=['GET']` default must not
            # override it (function routers still honour `methods=`).
            method_extra_params = is_class_router ? "" : extra_params
            get_endpoints(method, route_path, method_extra_params, codeblock_lines, prefix).each do |endpoint|
              details = Details.new(PathInfo.new(path, line_index + 1))
              endpoint.details = details

              push_callees_from(
                endpoint,
                codeblock,
                _class_def_index,
                path,
                definition_base_path: base_path_for(path),
                source: fetch_file_content(path),
              )

              # Add expect params as endpoint params
              if expect_params.size > 0
                expect_params.each do |param|
                  # Change the param type to form if the endpoint method is POST
                  if endpoint.method == "GET"
                    endpoint.push_param(Param.new(param.name, param.value, "query"))
                  else
                    endpoint.push_param(Param.new(param.name, param.value, "form"))
                  end
                end
              end
              result << endpoint
            end
          end
        end
      end

      # Process class-based views from add_url_rule() / add_resource()
      # registrations. The import-map fallback below resolves the same
      # file repeatedly (e.g. redash registers 60+ resources from one
      # module), so memoise the per-file import map.
      import_map_by_path = Hash(::String, Hash(::String, Tuple(::String, Int32))).new
      @class_views.each do |router_name, class_view_list|
        class_view_list.each do |class_view_info|
          _, path, route_path, class_name, _, methods = class_view_info

          api_instances = path_api_instances[path]
          prefix = api_instances.has_key?(router_name) ? api_instances[router_name] : ""

          # Try to use parser to find class definition, otherwise assume same file
          class_file = path
          parser = get_parser(path)
          if parser.@global_variables.has_key?(class_name)
            gv = parser.@global_variables[class_name]
            class_file = gv.path
          end

          class_lines = fetch_file_content(class_file).lines
          class_def_index = find_python_class_def(class_lines, class_name)

          # Parser globals only track assignments (not `class`/`def`
          # definitions), so an imported Resource/view class
          # (`from app.resources import Foo`) is invisible to
          # @global_variables and the assumed file is wrong. Resolve the
          # defining module through the import map and re-scan there.
          if class_def_index == -1
            import_map = import_map_by_path[path] ||= find_imported_modules(base_path_for(path), path)
            if (import_info = import_map[class_name]?) && !import_info[0].empty? && File.exists?(import_info[0])
              class_file = import_info[0]
              class_lines = fetch_file_content(class_file).lines
              class_def_index = find_python_class_def(class_lines, class_name)
            end
          end

          next if class_def_index == -1

          indent = class_lines[class_def_index].size - class_lines[class_def_index].lstrip.size

          # If no explicit methods, infer from class method definitions
          if methods.empty?
            methods.concat(extract_class_declared_methods(class_lines, class_def_index, indent))

            i = class_def_index + 1
            while i < class_lines.size
              infer_match = class_lines[i].match /(\s*)(async\s+)?def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/
              if infer_match && infer_match[1].size > indent
                method_name = infer_match[3]
                inferred_method = HTTP_METHODS.find { |m| m.downcase == method_name.downcase }
                methods << inferred_method.upcase if inferred_method
              end
              # Stop if we hit another class at same or higher level
              class_match = class_lines[i].match /(\s*)class\s+/
              break if class_match && class_match[1].size <= indent && i != class_def_index
              i += 1
            end
            # Default to GET if no HTTP methods inferred (matches Flask behavior)
            methods << "GET" if methods.empty?
          end

          # Process each declared method
          methods.uniq.each do |http_method|
            method_name = http_method.downcase

            # Find method definition in class
            method_def_index = find_class_method_def(class_lines, class_def_index, indent, method_name)
            method_def_index = find_class_method_def(class_lines, class_def_index, indent, "dispatch_request") if method_def_index == -1
            next if method_def_index == -1

            # Parse method code block
            codeblock = parse_code_block(class_lines[method_def_index..])
            next if codeblock.nil?
            codeblock_lines = codeblock.split("\n")

            # Generate endpoint with parameters
            route_url = "#{prefix}#{route_path}"
            route_url = "/#{route_url}" unless route_url.starts_with?("/")
            route_url = route_url.gsub("//", "/")

            # Extract parameters from method body
            suspicious_params = extract_request_params(codeblock_lines)
            params = get_filtered_params(http_method, suspicious_params)
            details = Details.new(PathInfo.new(class_file, method_def_index + 1))
            endpoint = Endpoint.new(route_url, http_method, params)
            endpoint.details = details

            push_callees_from(
              endpoint,
              codeblock,
              method_def_index,
              class_file,
              definition_base_path: base_path_for(class_file),
              source: fetch_file_content(class_file),
            )

            result << endpoint
          end
        end
      end

      Fiber.yield
      result
    end

    # Apps routinely wrap `add_resource` in an `Api` subclass method so the
    # registration also applies an app-specific prefix transform — redash's
    # `add_org_resource` is the canonical example. Collect those wrapper
    # method names (defined in this file) so `<api>.add_org_resource(...)`
    # is treated like `add_resource`. Returns nil for the common case (no
    # such wrapper) so callers can reuse the hoisted alias-free constants.
    private def collect_resource_registrar_aliases(source : ::String) : Array(::String)?
      return unless source.includes?(".add_resource(")
      aliases = nil
      lines = source.lines
      lines.each_with_index do |line, idx|
        def_match = line.match(RESOURCE_REGISTRAR_DEF_RE)
        next unless def_match
        name = def_match[2]
        next if name == "add_resource"
        def_indent = def_match[1].size
        # Scan the bounded method body for a delegating `.add_resource(`.
        j = idx + 1
        while j < lines.size && j < idx + 40
          body_line = lines[j]
          stripped = body_line.strip
          unless stripped.empty?
            indent = body_line.size - body_line.lstrip.size
            break if indent <= def_indent # left the method body
            if stripped.includes?(".add_resource(")
              (aliases ||= [] of ::String) << name
              break
            end
          end
          j += 1
        end
      end
      aliases
    end

    private def extract_class_declared_methods(class_lines : Array(::String), class_def_index : Int32, class_indent : Int32) : Array(::String)
      methods = [] of ::String
      i = class_def_index + 1
      while i < class_lines.size
        line = class_lines[i]
        stripped = line.strip
        unless stripped.empty?
          indent = line.size - line.lstrip.size
          break if indent <= class_indent

          if stripped.match(/^methods\s*=/)
            declaration = collect_python_collection_assignment(class_lines, i, line)
            declaration.scan(/['"]([A-Za-z]+)['"]/) do |m|
              method = m[1].upcase
              methods << method if HTTP_METHODS.any? { |known| known.upcase == method }
            end
            break
          end
        end
        i += 1
      end

      methods.uniq
    end

    private def collect_python_collection_assignment(lines : Array(::String), start_index : Int32, line : ::String) : ::String
      return line unless line.includes?("[") || line.includes?("(")

      pieces = [line]
      depth = python_paren_delta(line) + python_bracket_delta(line)
      i = start_index + 1
      while i < lines.size && depth > 0
        pieces << lines[i]
        depth += python_paren_delta(lines[i]) + python_bracket_delta(lines[i])
        i += 1
      end

      pieces.join(" ")
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

    # Locate `class <name>(...):` in a file's lines (-1 when absent).
    private def find_python_class_def(class_lines : Array(::String), class_name : ::String) : Int32
      class_prefix = "class #{class_name}"
      class_lines.each_with_index do |line, idx|
        stripped = line.lstrip
        if stripped.starts_with?(class_prefix) &&
           (stripped.size == class_prefix.size || stripped[class_prefix.size].in?('(', ':', ' ', '\t'))
          return idx
        end
      end
      -1
    end

    private def find_class_method_def(class_lines : Array(::String), class_def_index : Int32, class_indent : Int32, method_name : ::String) : Int32
      i = class_def_index + 1
      while i < class_lines.size
        method_match = class_lines[i].match /(\s*)(async\s+)?def\s+#{Regex.escape(method_name)}\s*\(/
        if method_match
          method_indent = method_match[1].size
          return i if method_indent > class_indent
        end

        class_match = class_lines[i].match /(\s*)class\s+/
        break if class_match && class_match[1].size <= class_indent

        i += 1
      end

      -1
    end

    # Fetch file content, preferring the detector-populated global
    # cache. The per-analyzer `@file_content_cache` is kept on top to
    # keep Flask's internal lookups (called 2–3× per file across the
    # class/blueprint passes) cheap even when the global cache is
    # disabled — otherwise the fallback would do that many fresh
    # `File.read` calls per file.
    private def fetch_file_content(path : ::String) : ::String
      @file_content_cache[path] ||= read_file_content(path)
    end

    # Pick the base path that owns this file so the engine's definition
    # resolver can locate imported modules relative to the right root.
    private def base_path_for(file_path : ::String) : ::String
      python_base_path_for(file_path)
    end

    private def flask_relevant_source?(source : ::String) : Bool
      # Strip # comments (to EOL) before relevance heuristics. This prevents
      # explanatory comments (in fixtures, docs, or real code) that mention
      # framework names from causing mis-attribution. E.g. a FastAPI file
      # whose comment says "flask" would otherwise bypass the competing-import
      # guard and emit duplicate routes under python_flask tech (which then
      # wins dedup non-deterministically depending on fiber completion order).
      clean = source.gsub(/#.*?(?:\n|\z)/m, "\n")

      return true if clean.matches?(/^\s*(?:from|import)\s+flask(?:\b|[._])/m)
      return true if clean.includes?("@expose(")
      # A file that imports a competing decorator-based framework (and
      # never mentions flask) is NOT Flask — its `@app.get`/`@router.post`
      # decorators belong to that framework's analyzer. Without this
      # guard, in any repo where the Flask detector fires (e.g. a sibling
      # Flask example), the Flask analyzer ALSO claimed FastAPI / Sanic /
      # Litestar / Starlette / Quart / Robyn handler files and mislabeled
      # their routes `python_flask` with Flask-style (usually empty)
      # params. The route's real owner still emits it correctly, so this
      # only drops the duplicate mislabel (jupyterhub examples/service-
      # fastapi was reported as python_flask).
      return false if clean.matches?(/^\s*(?:from|import)\s+(?:fastapi|sanic|litestar|starlette|quart|robyn)\b/m)
      return true if clean.matches?(ROUTE_DECORATOR_RE)
      return true if clean.matches?(ROUTE_REGISTRAR_RE)

      false
    end

    private def flask_appbuilder_only_source?(source : ::String) : Bool
      return false unless source.includes?("@expose(")

      clean = source.gsub(/#.*?(?:\n|\z)/m, "\n")
      return false if clean.matches?(/\b(?:Flask|Blueprint|Api|Namespace)\s*\(/)
      return false if clean.matches?(ROUTE_DECORATOR_RE)
      return false if clean.matches?(ROUTE_REGISTRAR_RE)

      true
    end

    private def extract_flask_static_url_path(constructor_line : ::String) : ::String?
      match = constructor_line.match(/(?:flask\.)?Flask\s*\((.*)\)\s*$/m)
      return unless match

      args = match[1]
      return if args.match(/\bstatic_folder\s*=\s*None\b/)
      return unless args.includes?("static_url_path")

      static_url_match = args.match(/\bstatic_url_path\s*=\s*[rf]?['"]([^'"]+)['"]/)
      static_url_match ? static_url_match[1] : nil
    end

    private def static_route_path(path : ::String) : ::String
      normalized = path.gsub(/\/+/, "/")
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized = normalized[0...-1] if normalized.ends_with?("/") && normalized != "/"
      normalized == "/" ? "/*" : "#{normalized}/*"
    end

    private def extract_flask_appbuilder_exposed_endpoints(path : ::String, source : ::String) : Array(Endpoint)
      return [] of Endpoint unless source.includes?("@expose(")

      endpoints = [] of Endpoint
      lines = source.split("\n")
      class_indent : Int32? = nil
      route_base = ""

      lines.each_with_index do |line, index|
        stripped = line.lstrip
        next if stripped.starts_with?("#")
        indent = line.size - stripped.size

        if stripped.matches?(/^class\s+([A-Za-z_][A-Za-z0-9_]*)\b/)
          class_indent = indent
          route_base = ""
          next
        end

        if current_indent = class_indent
          if !stripped.empty? && indent <= current_indent && !stripped.starts_with?("@")
            class_indent = nil
            route_base = ""
          end
        end

        next unless class_indent

        if route_base_match = stripped.match(/^route_base\s*=\s*[rf]?['"]([^'"]*)['"]/)
          route_base = route_base_match[1]
          next
        end

        if resource_name_match = stripped.match(/^resource_name\s*=\s*[rf]?['"]([^'"]*)['"]/)
          route_base = "/api/v1/#{resource_name_match[1]}"
          next
        end

        next unless stripped.starts_with?("@expose")

        expose_call = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
        expose = parse_flask_appbuilder_expose_call(expose_call)
        next unless expose

        expose_path, methods = expose
        full_path = join_flask_paths(route_base, expose_path)
        normalized_path, path_params = normalize_flask_path_params(full_path)
        methods.each do |method|
          params = path_params.dup
          if def_line = find_def_line(lines, index)
            if codeblock = parse_code_block(lines[def_line..])
              params.concat(get_filtered_params(method, extract_request_params(codeblock.split("\n"))))
            end
          end

          endpoints << Endpoint.new(normalized_path, method, params, Details.new(PathInfo.new(path, index + 1)))
        end
      end

      endpoints
    end

    private def parse_flask_appbuilder_expose_call(line : ::String) : Tuple(::String, Array(::String))?
      match = line.match(/@expose\s*\((.*)\)\s*$/m)
      return unless match

      args = split_python_call_args(match[1])
      route_path = ""
      args.each do |arg|
        stripped = arg.strip
        next if stripped.empty?
        break if stripped.matches?(/^[A-Za-z_][A-Za-z0-9_]*\s*=/)
        if string_match = stripped.match(/^[rf]?['"]([^'"]*)['"]/)
          route_path = string_match[1]
          break
        end
      end

      args.each do |arg|
        if url_match = arg.match(/^\s*(?:url|rule)\s*=\s*[rf]?['"]([^'"]*)['"]/)
          route_path = url_match[1]
          break
        end
      end

      route_path = "/" if route_path.empty?
      methods = [] of ::String
      args.each do |arg|
        next unless arg.matches?(/^\s*methods\s*=/)
        arg.scan(/['"]([A-Za-z]+)['"]/) do |method_match|
          method = method_match[1].upcase
          methods << method if HTTP_METHODS.any? { |known| known.upcase == method }
        end
      end
      methods << "GET" if methods.empty?

      {route_path, methods.uniq}
    end

    private def join_flask_paths(prefix : ::String, path : ::String) : ::String
      return normalize_joined_flask_path(path) if prefix.empty?
      return normalize_joined_flask_path(prefix) if path.empty? || path == "/"

      normalized_prefix = prefix.ends_with?("/") ? prefix[0...-1] : prefix
      normalized_path = path.starts_with?("/") ? path : "/#{path}"
      normalize_joined_flask_path("#{normalized_prefix}#{normalized_path}")
    end

    private def normalize_joined_flask_path(path : ::String) : ::String
      normalized = path.gsub(/\/+/, "/")
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized
    end

    private def normalize_flask_path_params(path : ::String) : Tuple(::String, Array(Param))
      params = [] of Param
      normalized = path.gsub(/<(?:(?:[^:<>]+):)?([A-Za-z_][A-Za-z0-9_]*)>/) do
        name = $~[1]
        params << Param.new(name, "", "path") unless params.any? { |param| param.name == name && param.param_type == "path" }
        "{#{name}}"
      end

      {normalized, params}
    end

    private def clone_path_api_instances(path_api_instances : Hash(::String, Hash(::String, ::String))) : Hash(::String, Hash(::String, ::String))
      cloned = Hash(::String, Hash(::String, ::String)).new
      path_api_instances.each do |path, api_instances|
        cloned[path] = api_instances.dup
      end

      cloned
    end

    private def apply_nested_blueprint_prefixes(path_api_instances : Hash(::String, Hash(::String, ::String)),
                                                own_api_instances : Hash(::String, Hash(::String, ::String)),
                                                blueprint_mounts : Hash(::String, Array(Tuple(::String, ::String, ::String))))
      blueprint_mounts.each do |path, mounts|
        api_instances = path_api_instances[path]?
        next unless api_instances

        own_prefixes = own_api_instances[path]? || api_instances
        changed = true
        # Bound the fixpoint loop: an acyclic mount graph converges in at most
        # `mounts.size` propagation passes. A circular mount (A registers B and
        # B registers A) would otherwise grow the prefix every pass and never
        # converge -> infinite loop + unbounded memory on cyclic input.
        iterations = 0
        max_iterations = mounts.size + 1
        while changed && iterations < max_iterations
          iterations += 1
          changed = false
          mounts.each do |mount|
            parent_name, child_name, mount_prefix = mount
            next unless api_instances.has_key?(child_name)

            parent_prefix = api_instances[parent_name]? || ""
            child_own_prefix = own_prefixes[child_name]? || ""
            resolved_prefix = File.join(parent_prefix, mount_prefix, child_own_prefix)
            next if api_instances[child_name] == resolved_prefix

            api_instances[child_name] = resolved_prefix
            changed = true
          end
        end
      end
    end

    # Create a Python parser for a given path and content. The
    # parser walks the file with tree-sitter and recursively
    # absorbs globals from imported modules — no lexer step.
    def create_parser(path : ::String, content : ::String = "") : PythonParser
      content = fetch_file_content(path) if content.empty?
      @logger.debug "Parsing #{path}"
      parser = PythonParser.new(path, content, @parsers, depth: 0)
      @logger.debug "Parsed #{path}"
      parser
    end

    # Get a parser for a given path
    def get_parser(path : ::String, content : ::String = "") : PythonParser
      @parsers[path] ||= create_parser(path, content)
      @parsers[path]
    end

    # Extracts endpoint information from the given route and code block
    def get_endpoints(method : ::String, route_path : ::String, extra_params : ::String, codeblock_lines : Array(::String), prefix : ::String)
      endpoints = [] of Endpoint
      methods = [] of ::String

      if !prefix.ends_with?("/") && !route_path.starts_with?("/")
        prefix = "#{prefix}/"
      end

      # Parse declared methods from route decorator
      methods_match = extra_params.match /methods\s*=\s*(.*)/
      if !methods_match.nil? && methods_match.size == 2
        methods_match[1].scan(/['"]([^'"]*)['"']/) do |m|
          method_name = m[1].upcase
          methods << method_name if HTTP_METHODS.any? { |hm| hm.upcase == method_name }
        end
      end
      if methods.empty?
        methods << method.upcase
      end

      suspicious_params = extract_request_params(codeblock_lines)

      methods.uniq.each do |http_method_name|
        route_url = "#{prefix}#{route_path}"
        route_url = "/#{route_url}" unless route_url.starts_with?("/")

        params = get_filtered_params(http_method_name, suspicious_params)
        endpoints << Endpoint.new(route_url.gsub("//", "/"), http_method_name, params)
      end

      endpoints
    end

    private def extract_add_url_rule_function_name(args_str : ::String) : ::String
      if view_func_match = args_str.match(VIEW_FUNC_KWARG_RE)
        return view_func_match[1]
      end

      positional_parts = split_python_call_args(args_str)
      view_arg = if positional_parts.size >= 3
                   positional_parts[2]
                 elsif positional_parts.size == 2
                   positional_parts[1]
                 else
                   ""
                 end
      view_arg.matches?(DOTTED_REFERENCE_RE) ? view_arg : ""
    end

    private def resolve_external_function_view(function_ref : ::String,
                                               current_path : ::String,
                                               import_modules : Hash(::String, Tuple(::String, Int32))) : Tuple(::String, ::String)?
      reference = function_ref.strip
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

    private def split_python_call_args(args_str : ::String) : Array(::String)
      parts = [] of ::String
      current = String::Builder.new
      paren_depth = 0
      bracket_depth = 0
      single_quote = false
      double_quote = false
      escaped = false

      args_str.each_char do |ch|
        if escaped
          current << ch
          escaped = false
          next
        end

        if ch == '\\'
          current << ch
          escaped = true
          next
        end

        if single_quote
          single_quote = false if ch == '\''
          current << ch
          next
        end

        if double_quote
          double_quote = false if ch == '"'
          current << ch
          next
        end

        case ch
        when '\''
          single_quote = true
        when '"'
          double_quote = true
        when '('
          paren_depth += 1
        when ')'
          paren_depth -= 1 if paren_depth > 0
        when '[', '{'
          bracket_depth += 1
        when ']', '}'
          bracket_depth -= 1 if bracket_depth > 0
        when ','
          if paren_depth == 0 && bracket_depth == 0
            part = current.to_s.strip
            parts << part unless part.empty?
            current = String::Builder.new
            next
          end
        end

        current << ch
      end

      part = current.to_s.strip
      parts << part unless part.empty?
      parts
    end

    private def find_function_def(lines : Array(::String), function_name : ::String) : Int32?
      # Compile once per call; an interpolated literal inside the loop
      # would be recompiled on every line.
      def_re = /^\s*(?:async\s+)?def\s+#{Regex.escape(function_name)}\s*\(/
      lines.each_with_index do |line, index|
        if line.match(def_re)
          return index
        end
      end

      nil
    end

    # JSON-variable access patterns interpolate a discovered (dynamic but
    # low-cardinality) identifier, so they can't be hoisted to constants —
    # memoize them per variable name instead.
    @json_param_regex_cache = Hash(::String, Tuple(Regex, Regex)).new

    private def json_param_regexes(json_variable_name : ::String) : Tuple(Regex, Regex)
      @json_param_regex_cache[json_variable_name] ||= {
        /[^a-zA-Z_]#{Regex.escape(json_variable_name)}\[[rf]?['"]([^'"]*)['"]\]/,
        /[^a-zA-Z_]#{Regex.escape(json_variable_name)}\.get\([rf]?['"]([^'"]*)['"]/,
      }
    end

    # Extracts request parameters from a code block by detecting JSON variable
    # assignments and scanning for request.field access patterns.
    private def extract_request_params(codeblock_lines : Array(::String)) : Array(Param)
      params = [] of Param
      json_variable_names = [] of ::String

      # Parse JSON variable names (e.g. data = json.loads(request.data), data = request.json)
      #
      # The `(ident).*=` shape backtracks catastrophically over a long run of word
      # characters (the trailing literal's required code unit is a plain letter, so
      # PCRE2 can't pre-reject). Gate each regex on a cheap substring check so a
      # multi-kilobyte line that lacks the marker never reaches the matcher.
      codeblock_lines.each do |codeblock_line|
        if codeblock_line.includes?("json.loads")
          match = codeblock_line.match /([a-zA-Z_][a-zA-Z0-9_]*).*=\s*json\.loads\(request\.data/
          if !match.nil? && match.size == 2 && !json_variable_names.includes?(match[1])
            json_variable_names << match[1]
          end
        end
        if codeblock_line.includes?("request.json") || codeblock_line.includes?("request.get_json")
          match = codeblock_line.match /([a-zA-Z_][a-zA-Z0-9_]*).*=\s*request\.(?:get_json\([^)]*\)|json)/
          if !match.nil? && match.size == 2 && !json_variable_names.includes?(match[1])
            json_variable_names << match[1]
          end
        end
      end

      # Parse declared parameters from request field access patterns.
      # Patterns are precompiled in REQUEST_PARAM_FIELD_PATTERNS so this
      # per-route loop never recompiles a PCRE2 regex.
      codeblock_lines.each do |codeblock_line|
        REQUEST_PARAM_FIELD_PATTERNS.each do |field_pattern|
          noir_param_type, bracket_re, get_re = field_pattern
          matches = codeblock_line.scan(bracket_re)
          if matches.size == 0
            matches = codeblock_line.scan(get_re)
          end

          matches.each do |parameter_match|
            next if parameter_match.size != 2
            param_name = parameter_match[1]
            params << Param.new(param_name, "", noir_param_type)
          end
        end

        # JSON dict access on the variables found above. This used to run
        # inside the field-pattern loop (once per missed field — i.e.
        # effectively per field per line), recompiling two interpolated
        # regexes each time and appending the same matches repeatedly;
        # `get_filtered_params` deduplicates by (name, param_type), so
        # scanning once per line is output-identical.
        json_variable_names.each do |json_variable_name|
          bracket_json_re, get_json_re = json_param_regexes(json_variable_name)
          matches = codeblock_line.scan(bracket_json_re)
          if matches.size == 0
            matches = codeblock_line.scan(get_json_re)
          end
          next if matches.size == 0

          matches.each do |parameter_match|
            next if parameter_match.size != 2
            params << Param.new(parameter_match[1], "", "json")
          end
          break
        end
      end

      params
    end

    # Filters the parameters based on the HTTP method
    def get_filtered_params(method : ::String, params : Array(Param)) : Array(Param)
      # Split to other module (duplicated method with analyzer_django)
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

    # Extracts parameters from the decorator
    def extract_params_from_decorator(path : ::String, lines : Array(::String), line_index : Int32, direction : Symbol = :down) : Tuple(Array(Param), Int32)
      params = [] of Param
      codeline_index = (direction == :down) ? line_index + 1 : line_index - 1
      # Carry the decorator line's paren delta forward when walking
      # downward so multi-line decorator headers
      # (`@app.route(\n  "/x",\n  methods=[...],\n)`) don't cause
      # the loop to bail on the first continuation line — without
      # this, `@app.route(` ate everything up to the matching `)`
      # was treated as "not a decorator and not a def", skipping
      # the whole route. `find_def_line` got the same fix earlier.
      paren_depth = direction == :down && (deco_line = lines[line_index]?) ? flask_line_paren_delta(deco_line) : 0

      # Iterate through the lines until the decorator ends
      while (direction == :down && codeline_index < lines.size) || (direction == :up && codeline_index >= 0)
        current_line = lines[codeline_index]
        # Skip empty/blank lines
        if current_line.strip.empty?
          codeline_index += (direction == :down ? 1 : -1)
          next
        end
        # Still inside the decorator's continuation parens — accept
        # the line as decorator content and keep walking without
        # checking the `\s*@` prefix.
        if direction == :down && paren_depth > 0
          paren_depth += flask_line_paren_delta(current_line)
          codeline_index += 1
          next
        end
        decorator_match = current_line.match /\s*@/
        break if decorator_match.nil?
        if direction == :down
          paren_depth += flask_line_paren_delta(current_line)
        end

        # Extract parameters from the expect decorator
        # https://flask-restx.readthedocs.io/en/latest/swagger.html#the-api-expect-decorator
        expect_match = lines[codeline_index].match /\s*@.+\.expect\(\s*(#{DOT_NATION})/
        unless expect_match.nil?
          parser = get_parser(path)
          if parser.@global_variables.has_key?(expect_match[1])
            gv = parser.@global_variables[expect_match[1]]
            if gv.type == "Namespace.model"
              model = gv.value.split("model(", 2)[1]
              parameter_dict_literal = model.split("{", 1)[-1]

              field_pos_list = [] of Tuple(Int32, Int32)
              parameter_dict_literal.scan(/['"]([^'"]*)['"]:\s*fields\./) do |match|
                match_begin = match.begin(0)
                match_end = match.end(0)
                field_pos_list << Tuple.new(match_begin, match_end)
              end

              field_pos_list.each_with_index do |field_pos, index|
                field_begin_pos = field_pos[0]
                # End the slice exactly before the next field begins. The old
                # `-1 + next_start + field_pos[1]` over-extended well past the
                # next field, leaking its default value into this one.
                field_end_pos = (index == field_pos_list.size - 1) ? -1 : field_pos_list[index + 1][0] - 1

                field_literal = parameter_dict_literal[field_begin_pos..field_end_pos]
                field_key_literal, field_value_literal = field_literal.split(":", 2)
                field_key = field_key_literal.strip[1..-2]
                default_value = ""
                default_assign_match = /default=(.+)/.match(field_value_literal)
                if default_assign_match
                  rindex = default_assign_match[1].rindex(",")
                  rindex = default_assign_match[1].rindex(")") if rindex.nil?
                  unless rindex.nil?
                    default_value = default_assign_match[1][..rindex - 1].strip
                    if default_value[0] == "'" || default_value[0] == '"'
                      default_value = default_value[1..-2]
                    end
                  end
                end

                params << Param.new(field_key, default_value, "query")
              end
            end
          end
        end

        codeline_index += (direction == :down ? 1 : -1)
      end

      return params, [lines.size - 1, codeline_index].min
    end

    # Pull the explicit mount path off an `<api>.add_namespace(ns, "/x")`
    # call (or `path="/x"` kwarg). `ns_line` is the space-stripped,
    # paren-balanced call text. Returns nil when no positional path /
    # `path=` is given, so the caller falls back to the Namespace's own
    # `path=`/name. This is the authoritative mount point in flask-restx
    # and overrides the namespace definition's default.
    private def extract_add_namespace_path(ns_line : ::String, api_instance_name : ::String, ns_var : ::String) : ::String?
      call_match = ns_line.match /#{Regex.escape(api_instance_name)}\.add_namespace\(#{Regex.escape(ns_var)},(.*)\)/
      return unless call_match
      args = call_match[1]
      if kw = args.match /path=[rf]?['"]([^'"]*)['"]/
        return kw[1]
      end
      if pos = args.match /^[rf]?['"]([^'"]*)['"]/
        return pos[1]
      end
      nil
    end

    # Function to extract namespace from the parser and update the prefix
    private def extract_namespace_prefix(parser : PythonParser, key : ::String, _prefix : ::String) : ::String
      # Check if the parser's global variables contain the given key
      if parser.@global_variables.has_key?(key)
        gv = parser.@global_variables[key]

        # If the global variable is of type "Namespace"
        if gv.type == "Namespace"
          # Extract namespace value from the global variable
          namespace = gv.value.split("Namespace(", 2)[1]
          if namespace.includes?("path=")
            namespace = namespace.split("path=")[1].split(")")[0].split(",")[0]
          else
            namespace = namespace.split(",")[0].split(")")[0].strip
          end

          # Clean up the namespace string by removing surrounding quotes
          if namespace.starts_with?("'") || namespace.starts_with?("\"")
            namespace = namespace[1..]
          end
          if namespace.ends_with?("'") || namespace.ends_with?("\"")
            namespace = namespace[..-2]
          end

          _prefix = File.join(_prefix, namespace)
        end
      end
      _prefix
    end

    # Net `(` − `)` count for a single line, ignoring parens that
    # fall inside single- or double-quoted strings. Used by
    # `extract_params_from_decorator` to walk through multi-line
    # decorator headers without breaking the loop on continuation
    # tokens.
    private def flask_line_paren_delta(line : ::String) : Int32
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
  end
end
