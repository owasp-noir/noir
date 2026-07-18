require "../../engines/python_engine"

module Analyzer::Python
  # Django Ninja is a FastAPI-inspired REST framework that plugs into
  # Django's URL system. Operations are declared with decorators on a
  # `NinjaAPI()` (or `Router()`) instance — `@api.get("/items")` — and
  # the whole API is mounted through Django's URLconf:
  #
  #   # api.py
  #   from ninja import NinjaAPI, Router
  #   api = NinjaAPI()
  #
  #   @api.get("/add")
  #   def add(request, a: int, b: int): ...
  #
  #   router = Router()
  #   @router.get("/{event_id}")
  #   def event(request, event_id: int): ...
  #   api.add_router("/events/", router)
  #
  #   # urls.py
  #   urlpatterns = [path("api/", api.urls)]
  #
  # The full URL is `mount_prefix + router_prefix + operation_path`, so
  # the analyzer works in phases: collect `NinjaAPI`/`Router` instances
  # and their operations, resolve each API's mount prefix from the
  # URLconf, resolve router prefixes from `add_router(...)`, then emit
  # one endpoint per (instance, prefix) reachable from an API root.
  class DjangoNinja < PythonEngine
    # django-ninja path parameters use Django's converter syntax, where
    # the converter (when present) comes BEFORE the name: `{item_id}` or
    # `{int:item_id}`. This is the reverse of FastAPI's `{item_id:int}`,
    # so the capture takes the token AFTER an optional `converter:`.
    PATH_PARAM_REGEX = /\{(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?([A-Za-z_][A-Za-z0-9_]*)\}/

    # Verbs exposed as `@api.<verb>(...)` decorators. `api_operation`
    # (an explicit method list) is handled separately.
    HTTP_DECORATOR_METHODS = %w[get post put patch delete head options]

    # Scalar annotations that, absent an explicit marker (`Query(...)`,
    # `Body(...)`, ...), map a handler parameter to a query parameter.
    SCALAR_TYPES = %w[str int float bool bytes date datetime time UUID uuid EmailStr Decimal]

    KIND_API    = 0
    KIND_ROUTER = 1

    NINJA_API_DECL_RE    = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=]+)?=\s*(?:[A-Za-z_][A-Za-z0-9_.]*\.)?NinjaAPI\s*\(/
    NINJA_ROUTER_DECL_RE = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=]+)?=\s*(?:[A-Za-z_][A-Za-z0-9_.]*\.)?Router\s*\(/
    DECORATOR_RE         = /^\s*@\s*([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\((.*)\)\s*(?:#.*)?$/m
    ADD_ROUTER_CALL_RE   = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*add_router\s*\((.*)\)\s*(?:#.*)?$/m
    # `path("api/", api.urls)` / `re_path(r"^api/", api.urls)` — a router
    # instance mounted by attribute reference.
    MOUNT_VAR_RE = /\b(?:path|re_path|url)\s*\(\s*[rf]?['"]([^'"]*)['"]\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\.urls\b/
    # `path("api/", "myproject.api.api.urls")` — the dotted-string form.
    MOUNT_STR_RE = /\b(?:path|re_path|url)\s*\(\s*[rf]?['"]([^'"]*)['"]\s*,\s*[rf]?['"]([A-Za-z_][A-Za-z0-9_.]*)\.urls['"]/

    @import_cache = Hash(::String, Hash(::String, Tuple(::String, Int32))).new

    def analyze
      instances = Hash(::String, NinjaInstance).new

      python_files = get_files_by_extension(".py")

      # Phase 1 — collect NinjaAPI/Router instances, their operations and
      # `add_router(...)` edges.
      python_files.each do |path|
        next if path.includes?("/site-packages/")
        next if python_test_path?(path)
        begin
          source = read_file_content(path)
        rescue
          next
        end
        next unless source.includes?("NinjaAPI") || source.includes?("Router")
        collect_instances(path, source, instances)
      end

      return result if instances.empty?

      # Phase 2 — resolve each API's mount prefix from the Django URLconf.
      resolve_mount_prefixes(python_files, instances)

      # Phase 3 — resolve `add_router(...)` targets to concrete instances.
      resolve_router_edges(instances)

      # Phase 4 — walk the include graph from every API root and emit.
      emit_endpoints(instances)

      Fiber.yield
      result
    end

    private def instance_key(path : ::String, var : ::String) : ::String
      "#{path}\u{0}#{var}"
    end

    private def import_modules_for(base : ::String, path : ::String, source : ::String? = nil) : Hash(::String, Tuple(::String, Int32))
      @import_cache[path] ||= find_imported_modules(base, path, source)
    end

    private def collect_instances(path : ::String, source : ::String, instances : Hash(::String, NinjaInstance)) : Nil
      lines = source.split("\n")
      base = python_base_path_for(path)

      # Sub-pass A: instance declarations.
      local_vars = Hash(::String, Int32).new
      lines.each do |line|
        next if line.lstrip.starts_with?("#")
        if m = line.match(NINJA_API_DECL_RE)
          local_vars[m[1]] = KIND_API
        elsif m = line.match(NINJA_ROUTER_DECL_RE)
          local_vars[m[1]] ||= KIND_ROUTER
        end
      end
      return if local_vars.empty?

      import_modules = import_modules_for(base, path, source)

      local_vars.each do |var, kind|
        key = instance_key(path, var)
        instances[key] ||= NinjaInstance.new(kind, path, var, base)
      end

      # Sub-pass B: `add_router(...)` edges and route decorators.
      lines.each_with_index do |line, index|
        stripped = line.lstrip
        next if stripped.starts_with?("#")

        if line.includes?(".add_router")
          logical = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
          if edge = parse_add_router(logical, local_vars, path, base)
            var, router_edge = edge
            instances[instance_key(path, var)].edges << router_edge
          end
        end

        next unless stripped.starts_with?("@")
        next unless stripped.includes?(".")
        effective = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
        parse_operation(effective, local_vars, lines, index, path, source, base, import_modules, instances)
      end
    end

    private def parse_add_router(logical : ::String,
                                 local_vars : Hash(::String, Int32),
                                 path : ::String,
                                 base : ::String) : Tuple(::String, RouterEdge)?
      match = logical.match(ADD_ROUTER_CALL_RE)
      return unless match
      var = match[1]
      return unless local_vars.has_key?(var)

      args = split_python_arguments(match[2])
      return if args.size < 2

      prefix = extract_python_string(args[0]) || extract_python_keyword_string(args, "prefix")
      return unless prefix

      target_expr = extract_python_keyword_expression(args, "router") || args[1]?.try(&.strip)
      return unless target_expr

      if literal = extract_python_string(target_expr)
        return {var, RouterEdge.new(prefix, literal, true, path, base)}
      end

      ref = clean_reference(target_expr)
      return if ref.empty?
      {var, RouterEdge.new(prefix, ref, false, path, base)}
    end

    private def parse_operation(effective : ::String,
                                local_vars : Hash(::String, Int32),
                                lines : Array(::String),
                                index : Int32,
                                path : ::String,
                                source : ::String,
                                base : ::String,
                                import_modules : Hash(::String, Tuple(::String, Int32)),
                                instances : Hash(::String, NinjaInstance)) : Nil
      match = effective.match(DECORATOR_RE)
      return unless match
      var = match[1]
      return unless local_vars.has_key?(var)
      attr = match[2]
      args = match[3]

      if attr == "api_operation"
        arg_list = split_python_arguments(args)
        return if arg_list.size < 2
        methods = extract_methods_list(arg_list[0])
        op_path = extract_python_string(arg_list[1]) || extract_route_path(args)
      elsif HTTP_DECORATOR_METHODS.includes?(attr)
        methods = [attr.upcase]
        op_path = extract_route_path(args)
      else
        return
      end

      return unless op_path
      methods = ["GET"] if methods.empty?

      def_line = find_def_line(lines, index) || (index + 1)
      params = extract_handler_params(lines, def_line, op_path, source, base, import_modules)

      callees = [] of Callee
      if codeblock = parse_code_block(lines[def_line..])
        callees = build_callees_from(
          codeblock,
          def_line,
          path,
          definition_base_path: base,
          source: source
        )
      end

      instances[instance_key(path, var)].operations << Operation.new(
        methods,
        op_path,
        index + 1,
        params,
        callees,
        path
      )
    end

    private def extract_methods_list(expr : ::String) : Array(::String)
      methods = [] of ::String
      expr.scan(/[rf]?['"]([A-Za-z]+)['"]/) do |m|
        verb = m[1].upcase
        methods << verb unless methods.includes?(verb)
      end
      methods
    end

    private def extract_route_path(args : ::String) : ::String?
      split_python_arguments(args).each do |arg|
        stripped = arg.strip
        next if stripped.empty?
        break if top_level_keyword_argument?(stripped)
        return extract_python_string(stripped)
      end

      if kw = extract_python_keyword_expression(args, "path")
        return extract_python_string(kw)
      end
      nil
    end

    private def extract_handler_params(lines : Array(::String),
                                       def_line : Int32,
                                       op_path : ::String,
                                       source : ::String,
                                       base : ::String,
                                       import_modules : Hash(::String, Tuple(::String, Int32))) : Array(Param)
      params = [] of Param
      path_param_names = ninja_path_param_names(op_path)

      function_definition = parse_function_def(lines, def_line)
      return params unless function_definition

      function_definition.params.each_with_index do |param, position|
        # The first positional argument is always the Django request.
        next if position == 0
        next if param.name.in?(%w[self cls request])
        next if param.name == "*" || param.name.empty?
        # Path params are added later from the fully-resolved URL.
        next if path_param_names.includes?(param.name)

        if param_type = infer_ninja_param_type(param)
          default_value = return_literal_value(param.default)
          params << Param.new(param.name, default_value, param_type)
          next
        end

        # No explicit marker and not a known scalar — most likely a
        # `ninja.Schema` body. Expand its fields; fall back to a query
        # param when the class can't be resolved.
        if schema_params = resolve_schema_params(param, source, base, import_modules)
          params.concat(schema_params) unless schema_params.empty?
          next unless schema_params.empty?
        end

        params << Param.new(param.name, return_literal_value(param.default), "query")
      end

      dedupe_params(params)
    end

    private def infer_ninja_param_type(param : FunctionParameter) : ::String?
      data = "#{param.default} #{param.type}"
      return "cookie" if data.includes?("Cookie(")
      return "header" if data.includes?("Header(")
      return "form" if data.includes?("Form(") || data.includes?("File(") || data.includes?("UploadedFile")
      return "form" if data.includes?("Body(")
      return "query" if data.includes?("Query(")
      return "path" if data.includes?("Path(")

      type = strip_type_wrappers(param.type)
      return "query" if type.empty?
      return "query" if SCALAR_TYPES.includes?(type)
      return "query" if type.starts_with?("List[") || type.starts_with?("list[")
      nil
    end

    private def strip_type_wrappers(type : ::String) : ::String
      core = type.strip
      if core.includes?("Annotated[")
        core = core.split("Annotated[", 2)[-1].split(",", 2)[0]
      end
      if core.includes?("Optional[")
        core = core.split("Optional[", 2)[-1]
      end
      if core.includes?("Union[")
        core = core.split("Union[", 2)[-1].split(",", 2)[0]
      end
      core.gsub(/[\[\]]/, "").strip
    end

    private def resolve_schema_params(param : FunctionParameter,
                                      source : ::String,
                                      base : ::String,
                                      import_modules : Hash(::String, Tuple(::String, Int32))) : Array(Param)?
      type = strip_type_wrappers(param.type)
      return unless type.matches?(/^[A-Za-z_][A-Za-z0-9_]*$/)

      if import_modules.has_key?(type)
        module_path = import_modules[type].first
        return if module_path.empty?
        begin
          schema_source = read_file_content(module_path)
        rescue
          return
        end
        return find_schema_params(schema_source, type)
      end

      find_schema_params(source, type)
    end

    private def find_schema_params(source : ::String, class_name : ::String) : Array(Param)?
      class_codeblock = parse_code_block(source, /\s*class\s+#{Regex.escape(class_name)}\s*[\(:]/)
      return if class_codeblock.nil?

      params = [] of Param
      class_codeblock.split("\n").each_with_index do |line, index|
        next if index == 0 # class header
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?("#")
        # Stop expanding at a method/inner-class boundary; keep scanning
        # past decorators (django-ninja schemas rarely carry them).
        next if stripped.starts_with?("@")
        break if stripped.starts_with?("def ") || stripped.starts_with?("async def ") || stripped.starts_with?("class ")

        field_match = stripped.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.+)$/)
        next unless field_match

        field_name = field_match[1]
        remainder = field_match[2]
        default = ""
        if assignment = remainder.split("=", 2)
          default = assignment[1].strip if assignment.size == 2
        end

        params << Param.new(field_name, return_literal_value(default), "json")
      end

      params.empty? ? nil : params
    end

    private def resolve_mount_prefixes(python_files : Array(::String), instances : Hash(::String, NinjaInstance)) : Nil
      python_files.each do |path|
        next if path.includes?("/site-packages/")
        next if python_test_path?(path)
        begin
          source = read_file_content(path)
        rescue
          next
        end
        next unless source.includes?(".urls")

        base = python_base_path_for(path)
        scan_source = source.lines.reject(&.lstrip.starts_with?("#")).join("\n")

        scan_source.scan(MOUNT_VAR_RE) do |match|
          prefix = match[1]
          var = match[2]
          if key = resolve_urls_target(var, path, base, source, instances)
            instances[key].mount_prefixes << normalize_mount_prefix(prefix)
          end
        end

        scan_source.scan(MOUNT_STR_RE) do |match|
          prefix = match[1]
          dotted = match[2]
          if key = resolve_dotted_target(dotted, instances)
            instances[key].mount_prefixes << normalize_mount_prefix(prefix)
          end
        end
      end
    end

    private def resolve_urls_target(var : ::String,
                                    path : ::String,
                                    base : ::String,
                                    source : ::String,
                                    instances : Hash(::String, NinjaInstance)) : ::String?
      local = instance_key(path, var)
      return local if instances.has_key?(local)

      import_modules = import_modules_for(base, path, source)
      if import_modules.has_key?(var)
        module_path = import_modules[var].first
        unless module_path.empty?
          key = instance_key(module_path, var)
          return key if instances.has_key?(key)
          # Aliased import (`from x import api as core_api`) — fall back
          # to any API instance declared in the imported module.
          if fallback = instances.find { |_, inst| inst.path == module_path && inst.kind == KIND_API }
            return fallback[0]
          end
        end
      end
      nil
    end

    private def resolve_dotted_target(dotted : ::String, instances : Hash(::String, NinjaInstance)) : ::String?
      parts = dotted.split(".")
      return if parts.size < 2
      var = parts[-1]
      module_suffix = "#{parts[0..-2].join("/")}.py"

      match = instances.find do |_, inst|
        inst.var == var && (inst.path.ends_with?("/#{module_suffix}") || inst.path == module_suffix)
      end
      match.try(&.[0])
    end

    private def resolve_router_edges(instances : Hash(::String, NinjaInstance)) : Nil
      instances.each_value do |inst|
        inst.edges.each do |edge|
          edge.child_key = resolve_router_target(edge, instances)
        end
      end
    end

    private def resolve_router_target(edge : RouterEdge, instances : Hash(::String, NinjaInstance)) : ::String?
      if edge.dotted?
        return resolve_dotted_target(edge.target, instances)
      end

      # `add_router("/e", pkg.router)` — an attribute reference on an
      # imported module (`from app import events; events.router`). Resolve
      # the module to a file and look up the attribute there.
      if edge.target.includes?(".")
        return resolve_attr_router_target(edge, instances)
      end

      local = instance_key(edge.source_file, edge.target)
      return local if instances.has_key?(local)

      import_modules = import_modules_for(edge.base, edge.source_file)
      if import_modules.has_key?(edge.target)
        module_path = import_modules[edge.target].first
        unless module_path.empty?
          key = instance_key(module_path, edge.target)
          return key if instances.has_key?(key)
          if fallback = instances.find { |_, inst| inst.path == module_path && inst.kind == KIND_ROUTER }
            return fallback[0]
          end
        end
      end
      nil
    end

    private def resolve_attr_router_target(edge : RouterEdge, instances : Hash(::String, NinjaInstance)) : ::String?
      module_name, _, attr = edge.target.partition(".")
      # Only single-level `module.attr` is resolvable here; deeper chains
      # (`a.b.router`) fall through to the dotted-string resolver's shape.
      return if module_name.empty? || attr.empty? || attr.includes?(".")

      import_modules = import_modules_for(edge.base, edge.source_file)
      return unless import_modules.has_key?(module_name)
      module_path = import_modules[module_name].first
      return if module_path.empty?

      key = instance_key(module_path, attr)
      return key if instances.has_key?(key)

      if fallback = instances.find { |_, inst| inst.path == module_path && inst.kind == KIND_ROUTER }
        return fallback[0]
      end
      nil
    end

    private def emit_endpoints(instances : Hash(::String, NinjaInstance)) : Nil
      visited = Set(::String).new
      reached = Set(::String).new
      queue = Deque(Tuple(::String, ::String)).new

      instances.each do |key, inst|
        next unless inst.kind == KIND_API
        prefixes = inst.mount_prefixes.empty? ? [""] : inst.mount_prefixes.to_a
        prefixes.each { |prefix| queue << {key, prefix} }
      end

      until queue.empty?
        key, prefix = queue.shift
        visit_id = "#{key}\u{0}#{prefix}"
        next if visited.includes?(visit_id)
        visited << visit_id

        inst = instances[key]?
        next unless inst
        reached << key

        emit_instance(inst, prefix)

        inst.edges.each do |edge|
          child = edge.child_key
          next unless child
          child_prefix = combine_paths(prefix, normalize_segment(edge.prefix))
          queue << {child, child_prefix}
        end
      end

      # Routers never mounted under any API — emit their operations at
      # their bare paths so the endpoints aren't lost entirely.
      instances.each do |orphan_key, orphan_inst|
        next unless orphan_inst.kind == KIND_ROUTER
        next if reached.includes?(orphan_key)
        next if orphan_inst.operations.empty?
        emit_instance(orphan_inst, "")
      end
    end

    private def emit_instance(inst : NinjaInstance, prefix : ::String) : Nil
      inst.operations.each do |op|
        full_path = normalize_ninja_path(combine_paths(prefix, op.path))
        path_param_names = ninja_path_param_names(full_path)
        params = reconcile_params(op.params, path_param_names)

        op.methods.each do |method|
          details = Details.new(PathInfo.new(op.def_path, op.line))
          endpoint = Endpoint.new(full_path, method, params.map { |p| Param.new(p.name, p.value, p.param_type) }, details)
          op.callees.each { |callee| endpoint.push_callee(callee) }
          result << endpoint
        end
      end
    end

    # Reclassify any parameter whose name matches a resolved path
    # parameter (a prefix may add path params the operation decorator
    # didn't declare) and add path params with no matching handler arg.
    private def reconcile_params(op_params : Array(Param), path_param_names : Array(::String)) : Array(Param)
      params = op_params.map do |param|
        if path_param_names.includes?(param.name) && param.param_type != "path"
          Param.new(param.name, param.value, "path")
        else
          param
        end
      end

      path_param_names.each do |name|
        params << Param.new(name, "", "path") unless params.any? { |p| p.name == name }
      end

      dedupe_params(params)
    end

    private def ninja_path_param_names(path : ::String) : Array(::String)
      names = [] of ::String
      path.scan(PATH_PARAM_REGEX) do |match|
        names << match[1] if match.size > 1 && !names.includes?(match[1])
      end
      names
    end

    private def normalize_ninja_path(path : ::String) : ::String
      normalized = path.gsub(PATH_PARAM_REGEX) { |_| "{#{$~[1]}}" }
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized.gsub(/\/+/, "/")
    end

    # A mount can be declared with `re_path(r"^api/$", api.urls)`, whose
    # captured prefix carries Django regex anchors. Strip a leading `^`
    # and trailing `$` (mirroring django.cr's normalize_django_route) so
    # the mount doesn't leak regex syntax into the URL.
    private def normalize_mount_prefix(prefix : ::String) : ::String
      normalize_segment(prefix.gsub(/^\^/, "").gsub(/\$$/, ""))
    end

    # Prefix a URL segment with a leading slash and trim whitespace,
    # leaving a trailing slash intact (`"events/"` → `"/events/"`).
    private def normalize_segment(segment : ::String) : ::String
      seg = segment.strip
      return "" if seg.empty?
      seg.starts_with?("/") ? seg : "/#{seg}"
    end

    # Join two URL fragments, collapsing the slash at the boundary. A
    # trailing slash on `own` is preserved (django-ninja keeps `"/"`
    # operation paths trailing-slashed).
    private def combine_paths(parent : ::String, own : ::String) : ::String
      return own if parent.empty?
      return parent if own.empty?
      normalized_parent = parent.ends_with?("/") ? parent[0..-2] : parent
      if own.starts_with?("/")
        "#{normalized_parent}#{own}"
      else
        "#{normalized_parent}/#{own}"
      end
    end

    private def dedupe_params(params : Array(Param)) : Array(Param)
      deduped = [] of Param
      params.each do |param|
        next if deduped.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
        deduped << param
      end
      deduped
    end

    private def clean_reference(expression : ::String) : ::String
      reference = expression.strip.split("#", 2)[0].strip
      return reference if reference.matches?(/^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*$/)
      ""
    end

    private def extract_python_string(expression : ::String) : ::String?
      string_match = expression.strip.match(/^[rf]?['"]([^'"]*)['"]/)
      string_match ? string_match[1] : nil
    end

    private def extract_python_keyword_string(args : Array(::String), keyword : ::String) : ::String?
      args.each do |arg|
        if match = arg.match(/^\s*#{Regex.escape(keyword)}\s*=\s*(.+)$/m)
          return extract_python_string(match[1].strip)
        end
      end
      nil
    end

    private def top_level_keyword_argument?(arg : ::String) : Bool
      !!arg.match(/^[A-Za-z_][A-Za-z0-9_]*\s*=/)
    end

    private def extract_python_keyword_expression(call_tail : ::String, keyword : ::String) : ::String?
      return unless call_tail.includes?(keyword)
      match = call_tail.match(/\b#{Regex.escape(keyword)}\s*=/)
      return unless match

      index = match.end
      chars = call_tail.chars
      expression = String.build do |io|
        depth = 0
        in_quote : Char? = nil
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

    private def extract_python_keyword_expression(args : Array(::String), keyword : ::String) : ::String?
      args.each do |arg|
        if match = arg.match(/^\s*#{Regex.escape(keyword)}\s*=\s*(.+)$/m)
          return match[1].strip
        end
      end
      nil
    end

    private def split_python_arguments(args : ::String) : Array(::String)
      parts = [] of ::String
      current = String::Builder.new
      depth = 0
      in_quote : Char? = nil
      escaped = false

      args.each_char do |ch|
        if in_quote
          current << ch
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
          current << ch
        when '(', '[', '{'
          depth += 1
          current << ch
        when ')', ']', '}'
          depth -= 1 if depth > 0
          current << ch
        when ','
          if depth == 0
            parts << current.to_s
            current = String::Builder.new
          else
            current << ch
          end
        else
          current << ch
        end
      end

      parts << current.to_s
      parts
    end

    # A NinjaAPI / Router instance and everything discovered about it.
    class NinjaInstance
      property kind : Int32
      property path : ::String
      property var : ::String
      property base : ::String
      property operations : Array(Operation)
      property edges : Array(RouterEdge)
      property mount_prefixes : Set(::String)

      def initialize(@kind : Int32, @path : ::String, @var : ::String, @base : ::String)
        @operations = [] of Operation
        @edges = [] of RouterEdge
        @mount_prefixes = Set(::String).new
      end
    end

    # A single decorated operation (may serve several HTTP methods).
    class Operation
      property methods : Array(::String)
      property path : ::String
      property line : Int32
      property params : Array(Param)
      property callees : Array(Callee)
      property def_path : ::String

      def initialize(@methods : Array(::String),
                     @path : ::String,
                     @line : Int32,
                     @params : Array(Param),
                     @callees : Array(Callee),
                     @def_path : ::String)
      end
    end

    # An `<api>.add_router(prefix, target)` edge, resolved lazily.
    # `dotted` marks a `"news.api.router"` string target (versus a
    # router variable reference).
    class RouterEdge
      property prefix : ::String
      property target : ::String
      property? dotted : Bool
      property source_file : ::String
      property base : ::String
      property child_key : ::String?

      def initialize(@prefix : ::String,
                     @target : ::String,
                     @dotted : Bool,
                     @source_file : ::String,
                     @base : ::String)
        @child_key = nil
      end
    end
  end
end
