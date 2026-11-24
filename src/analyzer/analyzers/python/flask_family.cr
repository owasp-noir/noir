require "../../../miniparsers/python"
require "../../../miniparsers/python_method_guard"
require "../../engines/python_engine"

module Analyzer::Python
  # State and helpers shared by the Flask and Quart analyzers: Quart
  # re-implements Flask's API 1:1 (request object, Blueprints,
  # `add_url_rule`, class-based views), so both read sources the same way.
  module FlaskFamily
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
    # The get-access pattern accepts `.get(` and `.getlist(`: Werkzeug's
    # request MultiDicts (`request.args`, `request.form`, …) expose
    # `getlist("key")` as the standard accessor for repeated keys
    # (`?tag=a&tag=b`), and it reads the same first string argument as the
    # key — so `.get(?:list)?` captures both without a separate pattern.
    REQUEST_PARAM_FIELD_PATTERNS = REQUEST_PARAM_FIELDS.map do |field_name, tuple|
      {
        tuple[1],
        Regex.new("request\\.#{field_name}\\[[rf]?['\"]([^'\"]*)['\"]\\]"),
        Regex.new("request\\.#{field_name}\\.get(?:list)?\\([rf]?['\"]([^'\"]*)['\"]"),
      }
    end

    @file_content_cache = Hash(::String, ::String).new
    @parsers = Hash(::String, PythonParser).new

    # JSON-variable access patterns interpolate a discovered (dynamic but
    # low-cardinality) identifier, so they can't be hoisted to constants —
    # memoize them per variable name instead.
    @json_param_regex_cache = Hash(::String, Tuple(Regex, Regex)).new

    private def json_param_regexes(json_variable_name : ::String) : Tuple(Regex, Regex)
      @json_param_regex_cache[json_variable_name] ||= {
        # Not `request.args[...]` for a variable named `args`.
        /(?<![\w.])#{Regex.escape(json_variable_name)}\[[rf]?['"]([^'"]*)['"]\]/,
        /(?<![\w.])#{Regex.escape(json_variable_name)}\.get(?:list)?\([rf]?['"]([^'"]*)['"]/,
      }
    end

    # `data = request.form` (or `await request.form`, `.to_dict()`,
    # `request.form or {}`): reads through `data[...]` / `data.get(...)` are
    # that field's params. Not `name = request.form.get("name")`, which binds
    # one value, nor a `form=request.form` keyword argument.
    REQUEST_FIELD_ALIAS_RE = /\A\s*([a-zA-Z_]\w*)\s*(?::[^=]+)?=\s*(?:await\s+)?request\.(form|args|values|files|headers|cookies)(?:\.to_dict\([^)]*\))?(?![\w.\[(]|\s+[.\[(])/

    # `request.form["a"]` / `request.form.get("b")` reads on `line`, and the
    # same reads through each `{variable, param_type}` alias (a JSON body
    # variable, `data = request.form`). Bracket and `.get` reads both count:
    # `"{} {}".format(data["a"], data.get("b"))` reads two fields.
    # (Alias regexes are memoized in @json_param_regex_cache: they
    # interpolate a discovered identifier so they can't be consts.)
    private def scan_request_reads(line : ::String, aliases : Array(Tuple(::String, ::String)), params : Array(Param))
      REQUEST_PARAM_FIELD_PATTERNS.each do |param_type, bracket_re, get_re|
        line.scan(bracket_re) { |m| params << Param.new(m[1], "", param_type) }
        line.scan(get_re) { |m| params << Param.new(m[1], "", param_type) }
      end
      aliases.each do |name, param_type|
        bracket_re, get_re = json_param_regexes(name)
        line.scan(bracket_re) { |m| params << Param.new(m[1], "", param_type) }
        line.scan(get_re) { |m| params << Param.new(m[1], "", param_type) }
      end
    end

    # `{variable, param_type}` for each such alias in `codeblock_lines`.
    private def request_field_aliases(codeblock_lines : Array(::String)) : Array(Tuple(::String, ::String))
      aliases = [] of Tuple(::String, ::String)
      codeblock_lines.each do |line|
        next unless line.includes?("request.")
        if m = line.match(REQUEST_FIELD_ALIAS_RE)
          aliases << {m[1], REQUEST_PARAM_FIELDS[m[2]][1]}
        end
      end
      aliases.uniq
    end

    # Fetch file content, preferring the detector-populated global
    # cache. The per-analyzer `@file_content_cache` is kept on top to
    # keep the internal lookups (called 2–3× per file across the
    # class/blueprint passes) cheap even when the global cache is
    # disabled — otherwise the fallback would do that many fresh
    # `File.read` calls per file.
    private def fetch_file_content(path : ::String) : ::String
      @file_content_cache[path] ||= read_file_content(path)
    end

    @file_lines_cache = Hash(::String, Array(::String)).new

    # `fetch_file_content(path).lines`, split once per file: the per-route
    # emit loops otherwise re-split the whole file for every route, which
    # is quadratic in a single file holding thousands of routes.
    private def fetch_file_lines(path : ::String) : Array(::String)
      @file_lines_cache[path] ||= fetch_file_content(path).lines
    end

    # Get a parser for a given path
    def get_parser(path : ::String, content : ::String = "") : PythonParser
      @parsers[path] ||= create_parser(path, content)
      @parsers[path]
    end

    # Create a Python parser for a given path and content. The
    # parser walks the file with tree-sitter and recursively
    # absorbs globals from imported modules — no lexer step.
    def create_parser(path : ::String, content : ::String = "") : PythonParser
      content = fetch_file_content(path) if content.empty?
      PythonParser.new(path, content, @parsers, depth: 0)
    end

    # Build endpoints from a single route decoration: split on declared
    # `methods=[...]`, default to `method`, run the analyzer's own
    # parameter extractor over the lines reachable for each verb.
    def get_endpoints(method : ::String, route_path : ::String, extra_params : ::String, codeblock_lines : Array(::String), prefix : ::String, path : ::String? = nil)
      endpoints = [] of Endpoint
      methods = [] of ::String

      # `route("")` is the prefix itself: no slash is added.
      if !prefix.ends_with?("/") && !route_path.starts_with?("/") && !route_path.empty?
        prefix = "#{prefix}/"
      end

      methods_match = extra_params.match /methods\s*=\s*(.*)/
      if !methods_match.nil? && methods_match.size == 2
        methods_match[1].scan(/['"]([^'"]*)['"']/) do |m|
          method_name = m[1].upcase
          methods << method_name if PythonEngine::HTTP_METHODS.any? { |hm| hm.upcase == method_name }
        end
      end
      methods << method.upcase if methods.empty?

      methods.uniq.each do |http_method_name|
        route_url = "#{prefix}#{route_path}"
        route_url = "/#{route_url}" unless route_url.starts_with?("/")

        params = handler_request_params(codeblock_lines, http_method_name, path)
        endpoints << Endpoint.new(route_url.gsub("//", "/"), http_method_name, params)
      end

      endpoints
    end

    private def handler_request_params(lines : Array(::String), method : ::String, path : ::String? = nil) : Array(Param)
      scoped = Noir::PythonMethodGuard.lines_for(lines, method)
      get_filtered_params(method, extract_request_params(scoped, method, path))
    end

    private def extract_request_params(lines : Array(::String), method : ::String, path : ::String?) : Array(Param)
      extract_request_params(lines)
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

    private def clone_path_api_instances(path_api_instances : Hash(::String, Hash(::String, ::String))) : Hash(::String, Hash(::String, ::String))
      cloned = Hash(::String, Hash(::String, ::String)).new
      path_api_instances.each do |path, api_instances|
        cloned[path] = api_instances.dup
      end

      cloned
    end

    # Record a `register_blueprint(bp, url_prefix=...)` against the file
    # declaring `bp`. A blueprint registered twice keeps both prefixes.
    private def add_registered_prefix(registered : Hash(::String, Hash(::String, Array(::String))),
                                      path : ::String, name : ::String, prefix : ::String) : Nil
      list = (registered[path] ||= Hash(::String, Array(::String)).new)[name] ||= [] of ::String
      list << prefix unless list.includes?(prefix)
    end

    # Prefixes a route on blueprint `name` (declared in `path`) is served
    # under: every registration's when there are several, else `prefix`.
    private def route_prefixes(registered : Hash(::String, Hash(::String, Array(::String))),
                               path : ::String, name : ::String, prefix : ::String) : Array(::String)
      list = registered[path]?.try(&.[name]?)
      list && list.size > 1 ? list : [prefix]
    end

    @import_symbols_cache = Hash(::String, Hash(::String, Tuple(::String, ::String))).new

    # Where the blueprint a `register_blueprint(<expr>)` call names is
    # declared, as {file, declared name}. The call site routinely spells it
    # differently from the declaration (`users_bp` for `bp as users_bp`,
    # `posts.bp`, `auth_blueprint`), and routes are keyed on the declared one.
    private def blueprint_declaration(path : ::String, expr : ::String, seen = Set(Tuple(::String, ::String)).new) : Tuple(::String, ::String)?
      return unless seen.add?({path, expr})
      gv = get_parser(path).@global_variables[expr]?
      if gv && gv.value.matches?(/\A#{PythonEngine::DOT_NATION}\z/) && gv.value != expr
        declaration = blueprint_declaration(gv.path, gv.value, seen)
        return declaration if declaration
      end
      return {gv.path, gv.name} if gv && gv.type == "Blueprint"
      imported_declaration(path, expr)
    end

    # Resolve `name` (`bp`, `users_bp`, `views.bp`) used in `path` through
    # the file's imports, including ones indented inside `create_app()`,
    # to {declaring file, declared name}.
    private def imported_declaration(path : ::String, name : ::String) : Tuple(::String, ::String)?
      symbols = imported_symbols(path)
      if (target = symbols[name]?) && !target[1].empty?
        return target
      end
      dot = name.rindex('.') || return
      if (target = symbols[name[0, dot]]?) && target[1].empty?
        {target[0], name[(dot + 1)..]}
      end
    end

    private def imported_symbols(path : ::String) : Hash(::String, Tuple(::String, ::String))
      @import_symbols_cache[path] ||= Noir::ImportGraph::Python.find_imported_symbols(
        python_package_root(path), path, fetch_file_content(path))
    end

    @visible_strings = Hash(::String, Hash(::String, ::String)).new

    # The string constants `path` can name: its own module-level ones, the
    # ones it imports by name from project modules (`from .config import
    # API_PREFIX`), and `<module>.<NAME>` for a module it imports whole.
    private def visible_strings(path : ::String) : Hash(::String, ::String)
      @visible_strings[path] ||= begin
        strings = Noir::TreeSitterPythonRouteExtractor.module_string_constants(fetch_file_content(path)).dup
        imported_symbols(path).each do |local, (file, name)|
          exported = Noir::TreeSitterPythonRouteExtractor.module_string_constants(fetch_file_content(file))
          if name.empty?
            exported.each { |constant, value| strings["#{local}.#{constant}"] = value }
          elsif (value = exported[name]?) && !strings.has_key?(local)
            strings[local] = value
          end
        end
        strings
      end
    end

    # The directory absolute imports in `path` resolve against: the parent
    # of the outermost package (`__init__.py` directory) holding the file.
    private def python_package_root(path : ::String) : ::String
      dir = File.dirname(path)
      # A namespace subpackage (no `__init__.py`, PEP 420) inside a regular
      # one — Dify's `controllers/console/explore/` — still imports from the
      # enclosing package's root, so start from the nearest regular package.
      stop = python_base_path_for(path)
      probe = dir
      until File.exists?(File.join(probe, "__init__.py")) || probe == stop || File.dirname(probe) == probe
        probe = File.dirname(probe)
      end
      dir = probe if File.exists?(File.join(probe, "__init__.py"))
      while File.exists?(File.join(dir, "__init__.py"))
        parent = File.dirname(dir)
        break if parent == dir
        # The scan is rooted at the package itself: its parent was not
        # scanned, and the import resolver reads `pkg.x` from the base as `x`.
        break if Noir::PathScope.normalize_root(dir) == Noir::PathScope.normalize_root(stop)
        dir = parent
      end
      dir
    end

    # Prefixes a route on `router_name` in `path` is served under.
    private def router_prefixes(path_api_instances : Hash(::String, Hash(::String, ::String)),
                                registered : Hash(::String, Hash(::String, Array(::String))),
                                path : ::String, router_name : ::String) : Array(::String)
      if prefix = path_api_instances[path]?.try(&.[router_name]?)
        route_prefixes(registered, path, router_name, prefix)
      else
        imported_router_prefixes(path_api_instances, registered, path, router_name) || [""]
      end
    end

    # Prefixes for a route on a blueprint the route file imports rather
    # than declares (`from . import auth` in `auth/views.py`): the ones
    # resolved for it in the declaring file. Nil when it isn't imported.
    private def imported_router_prefixes(path_api_instances : Hash(::String, Hash(::String, ::String)),
                                         registered : Hash(::String, Hash(::String, Array(::String))),
                                         path : ::String, router_name : ::String) : Array(::String)?
      decl_path, decl_name = imported_declaration(path, router_name) || return
      prefix = path_api_instances[decl_path]?.try(&.[decl_name]?) || return
      route_prefixes(registered, decl_path, decl_name, prefix)
    end

    # A child mounted on a blueprint of another file is served under each of
    # that blueprint's prefixes joined with the registration's url_prefix
    # (its own one when omitted), next to any mount on the app. Passes run
    # until no chain (A in B in C) changes, bounded against a cycle.
    private def apply_cross_file_mounts(cross_file_mounts : Array(Tuple(::String, ::String, ::String, ::String, ::String?)),
                                        registered : Hash(::String, Hash(::String, Array(::String))),
                                        path_api_instances : Hash(::String, Hash(::String, ::String)),
                                        own_api_instances : Hash(::String, Hash(::String, ::String))) : Nil
      return if cross_file_mounts.empty?
      direct = Hash(Tuple(::String, ::String), Array(::String)).new
      cross_file_mounts.each do |_, _, child_path, child_name, _|
        direct[{child_path, child_name}] = registered[child_path]?.try(&.[child_name]?).try(&.dup) || [] of ::String
      end
      resolved = Hash(Tuple(::String, ::String), Array(::String)).new
      (cross_file_mounts.size + 1).times do
        pass = direct.transform_values(&.dup)
        cross_file_mounts.each do |parent_path, parent_name, child_path, child_name, mount|
          parents = resolved[{parent_path, parent_name}]? ||
                    registered[parent_path]?.try(&.[parent_name]?) ||
                    [path_api_instances[parent_path]?.try(&.[parent_name]?) || ""]
          child_prefix = mount || own_api_instances[child_path]?.try(&.[child_name]?) || ""
          list = pass[{child_path, child_name}]
          parents.each do |parent_prefix|
            joined = File.join(parent_prefix, child_prefix)
            list << joined unless list.includes?(joined)
          end
        end
        break if pass == resolved
        resolved = pass
      end
      resolved.each do |(path, name), prefixes|
        next if prefixes.empty?
        (registered[path] ||= Hash(::String, Array(::String)).new)[name] = prefixes
        (path_api_instances[path] ||= Hash(::String, ::String).new)[name] = prefixes.first
      end
    end

    FUNCTION_DEF_RE = /^\s*(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/

    # First `def <name>(` line per name, built once per lines array (keyed
    # by identity; the arrays come from `fetch_file_lines`). A linear scan
    # per call made many `add_url_rule(view_func=...)` routes quadratic.
    @function_def_index = Hash(Array(::String), Hash(::String, Int32)).new.compare_by_identity

    private def find_function_def(lines : Array(::String), function_name : ::String) : Int32?
      index = @function_def_index[lines] ||= begin
        defs = Hash(::String, Int32).new
        lines.each_with_index do |line, line_index|
          next unless line.includes?("def")
          if match = line.match(FUNCTION_DEF_RE)
            defs[match[1]] = line_index unless defs.has_key?(match[1])
          end
        end
        defs
      end
      index[function_name]?
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
              methods << method if PythonEngine::HTTP_METHODS.any? { |known| known.upcase == method }
            end
            break
          end
        end
        i += 1
      end

      methods.uniq
    end

    REGISTER_BLUEPRINT_RE = /(#{PythonEngine::DOT_NATION})\.register_blueprint\(\s*(?:blueprint\s*=\s*)?(#{PythonEngine::DOT_NATION})/

    alias ScopedNameKey = Tuple(::String, ::String)

    private record BlueprintScanState,
      app_instances : Hash(ScopedNameKey, ::String),
      blueprint_prefixes : Hash(ScopedNameKey, ::String),
      path_api_instances : Hash(::String, Hash(::String, ::String)),
      register_blueprint : Hash(::String, Hash(::String, Array(::String))),
      # Blueprint-parent edges, including same-file children, resolve together:
      # {parent file, parent, child file, child, url_prefix}.
      cross_file_mounts : Array(Tuple(::String, ::String, ::String, ::String, ::String?)),
      # flask-restx namespaces are module-level singletons: the Api host
      # file (`api/__init__.py`) wires `api.add_namespace(ns, "/x")` with
      # the blueprint's `url_prefix` (`/api/v1`), but each namespace's
      # ROUTES live in a different file (`api/v1/x.py`). `path_api_instances`
      # is per-file, so the route file never saw the host-computed prefix
      # and every `@ns.route` surfaced without `/api/v1`. This GLOBAL map
      # ({declaring file, namespace var name} -> fully-resolved prefix)
      # bridges the two files.
      namespace_prefixes : Hash(ScopedNameKey, ::String),
      # flask-restful / flask-restx `name = Api(host, prefix=...)`:
      # {file, name, host or nil, own prefix}.
      api_hosts : Array(Tuple(::String, ::String, ::String?, ::String)),
      # `api.add_namespace(ns, path=...)`: {Api file, Api name, local
      # namespace name, declaring file, declared name, mount path or nil}.
      namespace_mounts : Array(Tuple(::String, ::String, ::String, ::String, ::String, ::String?)) do
      def self.empty : BlueprintScanState
        new(
          app_instances: Hash(ScopedNameKey, ::String).new,
          blueprint_prefixes: Hash(ScopedNameKey, ::String).new,
          path_api_instances: Hash(::String, Hash(::String, ::String)).new,
          register_blueprint: Hash(::String, Hash(::String, Array(::String))).new,
          cross_file_mounts: [] of Tuple(::String, ::String, ::String, ::String, ::String?),
          namespace_prefixes: Hash(ScopedNameKey, ::String).new,
          api_hosts: [] of Tuple(::String, ::String, ::String?, ::String),
          namespace_mounts: [] of Tuple(::String, ::String, ::String, ::String, ::String, ::String?),
        )
      end
    end

    private def indent_of(line : ::String) : Int32
      line.size - line.lstrip.size
    end

    # Where the blueprint a `register_blueprint(<expr>)` names is declared.
    # A blueprint built inside the function that registers it (`def
    # load_blueprints(app): bp = Blueprint(...)`) is no module global, so it
    # is declared where it is registered. A factory (`tags.construct_blueprint
    # (datastore)`, or `bp = views.make_bp()` registered as `bp`) is the
    # blueprint its `def` returns.
    private def registered_blueprint_declaration(path : ::String, lines : Array(::String), api_instances : Hash(::String, ::String), name : ::String, line_index : Int32) : Tuple(::String, ::String)?
      declaration = blueprint_declaration(path, name)
      declaration ||= {path, name} if api_instances.has_key?(name)
      unless declaration
        if callee = assigned_call(lines, line_index, name)
          declaration = blueprint_declaration(path, callee)
          name = callee
        end
        declaration ||= {path, name} if !name.includes?('.') && find_function_def(lines, name)
      end
      declaration ? factory_blueprint(declaration) : nil
    end

    # The callee of the nearest `name = f(...)` above line `idx` in the
    # same scope (`bp = alpha.make()` ... `bp = beta.make()`): no deeper
    # than line `idx`, and not past the `def` holding it.
    private def assigned_call(lines : Array(::String), idx : Int32, name : ::String) : ::String?
      indent = indent_of(lines[idx])
      assignment = /\A[ \t]*#{Regex.escape(name)}[ \t]*=[ \t]*(#{PythonEngine::DOT_NATION})[ \t]*\(/
      (idx - 1).downto(0) do |j|
        line = lines[j]
        next if line.blank?
        line_indent = indent_of(line)
        next if line_indent > indent
        return if line_indent < indent && line.lstrip.matches?(/\A(?:async[ \t]+)?def\b/)
        # Out of the block holding the call: a deeper line above is in a
        # nested `def` or a sibling block.
        indent = line_indent if line_indent < indent
        if m = line.match(assignment)
          return m[1]
        end
      end
    end

    FACTORY_RETURN_RE = /^[ \t]+return[ \t]+([A-Za-z_]\w*)[ \t]*(?:#.*)?$/

    # `{file, name}` of the blueprint `def name(...)` in `file` builds and
    # returns, else `declaration` unchanged.
    private def factory_blueprint(declaration : Tuple(::String, ::String)) : Tuple(::String, ::String)
      path, name = declaration
      lines = fetch_file_lines(path)
      idx = find_function_def(lines, name) || return declaration
      indent = indent_of(lines[idx])
      body = [] of ::String
      lines[(idx + 1)..].each do |line|
        next if line.blank? || line.lstrip.starts_with?('#')
        break if indent_of(line) <= indent
        body << line
      end
      body.reverse_each do |line|
        returned = line.match(FACTORY_RETURN_RE).try(&.[1]) || next
        assigned = /^[ \t]+#{Regex.escape(returned)}[ \t]*=[ \t]*(?:(?:flask|quart)\.)?Blueprint[ \t]*\(/
        next unless body.any?(&.matches?(assigned))
        # Routes are keyed by file and name: two factories building the
        # same local name in one file cannot be told apart, so neither
        # takes the registration's prefix.
        return declaration if lines.count(&.matches?(assigned)) > 1
        return {path, returned}
      end
      declaration
    end

    # `url_prefix=app.config["X"]` / `app.config.get("X", "/d")`: the
    # strings the project's config modules assign `X`, else the `.get`
    # default. Which config class is live is read, not guessed from file
    # order: the class `config.from_object(...)` names (or the base it
    # inherits `X` from), else module-level settings and the base/default
    # classes (`Config`, `BaseConfig`, `DefaultConfig`, one others inherit
    # from). Values still in conflict each give a row.
    CONFIG_URL_PREFIX_RE = /url_prefix\s*=\s*#{PythonEngine::DOT_NATION}\.config\s*(?:\[\s*['"](\w+)['"]\s*\]|\.get\s*\(\s*['"](\w+)['"]\s*(?:,\s*[rf]?['"]([^'"]*)['"])?)/
    CONFIG_CLASS_RE      = /\Aclass\s+(\w+)\s*(?:\(([^)]*)\))?\s*:/
    FROM_OBJECT_RE       = /\.from_object\(\s*(?:['"]([\w.]+)['"]|([\w.]+)\s*\))/

    @config_string_values = Hash(::String, Array(::String)).new
    @config_from_object_classes = Hash(::String, Array(::String)).new

    private def config_url_prefixes(line : ::String, base_path : ::String) : Array(::String)
      match = line.match(CONFIG_URL_PREFIX_RE) || return [] of ::String
      key = match[1]? || match[2]
      values = config_string_values(key, base_path)
      values.empty? && (default = match[3]?) ? [default] : values
    end

    # Only the project's own config modules: a monorepo neighbour's
    # same-named setting configures a different app.
    private def config_string_values(key : ::String, base_path : ::String) : Array(::String)
      @config_string_values["#{base_path}\0#{key}"] ||= begin
        value_re = /\A[ \t]*#{key}[ \t]*(?::[^=\n]+)?=[ \t]*(?:[rR]?['"]([^'"\n]*)['"]|(?:os\.)?(?:environ\.get|getenv)\(\s*['"]\w+['"]\s*,\s*[rR]?['"]([^'"\n]*)['"]\s*\))[ \t]*(?:#.*)?\z/
        module_values = [] of ::String
        class_values = Hash(::String, ::String).new
        class_bases = Hash(::String, Array(::String)).new
        python_source_files.each do |path|
          next unless path_under_root?(path, base_path)
          stem = File.basename(path).downcase
          next unless stem.includes?("config") || stem.includes?("setting") || path.includes?("/config")
          source = fetch_file_content(path)
          next unless source.includes?(key) || source.includes?("class ")
          current = nil
          fetch_file_lines(path).each do |l|
            next if l.blank?
            unless l[0].ascii_whitespace?
              current = nil
              if c = l.match(CONFIG_CLASS_RE)
                current = c[1]
                class_bases[current] = c[2]?.to_s.split(',').map(&.strip.split('.').last).reject(&.empty?)
              end
            end
            next unless l.includes?(key)
            v = l.match(value_re) || next
            value = v[1]? || v[2]
            if cls = current
              class_values[cls] ||= value
            elsif !l[0].ascii_whitespace?
              module_values << value
            end
          end
        end
        chosen = from_object_classes(base_path).compact_map { |cls| config_class_value(cls, class_values, class_bases, 0) }
        if chosen.empty?
          inherited = class_bases.values.flatten.to_set
          base_classes = class_values.keys.select { |cls| cls.matches?(/\A(?:Base|Default)?Config\z|\A(?:Base|Default)/) || inherited.includes?(cls) }
          chosen = module_values + base_classes.map { |cls| class_values[cls] }
        end
        chosen = class_values.values if chosen.empty?
        chosen.uniq
      end
    end

    # `cls`'s own value, else the first one up its bases.
    private def config_class_value(cls : ::String, values : Hash(::String, ::String),
                                   bases : Hash(::String, Array(::String)), depth : Int32) : ::String?
      return values[cls] if values.has_key?(cls)
      return if depth > 8
      bases[cls]?.try &.each do |base|
        found = config_class_value(base, values, bases, depth + 1)
        return found if found
      end
      nil
    end

    # Class names handed to `<x>.config.from_object(...)` anywhere in the
    # project, as a dotted string or a name.
    private def from_object_classes(base_path : ::String) : Array(::String)
      @config_from_object_classes[base_path] ||= begin
        names = [] of ::String
        python_source_files.each do |path|
          next unless path_under_root?(path, base_path)
          source = fetch_file_content(path)
          next unless source.includes?("from_object")
          source.scan(FROM_OBJECT_RE) { |m| names << (m[1]? || m[2]).split('.').last }
        end
        names.uniq
      end
    end

    private def record_family_blueprint_registration(path : ::String, base_path : ::String,
                                                     lines : Array(::String), api_instances : Hash(::String, ::String),
                                                     state : BlueprintScanState, line_index : Int32,
                                                     original_line : ::String, line : ::String) : Nil
      # `app.register_blueprint(\n    views.construct_blueprint(), url_prefix="/x"\n)`
      if line.includes?(".register_blueprint(") && python_paren_delta(original_line) > 0
        original_line = join_until_python_call_closes(lines, line_index, original_line)
        line = original_line.gsub(" ", "")
      end
      register_blueprint_match = line.includes?(".register_blueprint(") ? line.match(REGISTER_BLUEPRINT_RE) : nil
      if register_blueprint_match
        parent_name = register_blueprint_match[1]
        blueprint_name = register_blueprint_match[2]
        # `url_prefix=API_PREFIX + "/users"` / `f"{API_PREFIX}/items"`: the
        # string the expression evaluates to, else the literal it starts with.
        mount_prefix = Noir::TreeSitterPythonRouteExtractor.call_url_prefix(original_line.strip, visible_strings(path)) if original_line.includes?("url_prefix")
        mount_prefix ||= original_line.match(/url_prefix\s*=\s*[rf]?['"]([^'"]*)['"]/).try(&.[1])
        mount_prefixes = mount_prefix ? [mount_prefix] : config_url_prefixes(original_line, base_path)
        # Keep declarations, not call-site spellings. Classify the parent only
        # after every file's Blueprint declarations have been discovered.
        parent = registered_blueprint_declaration(path, lines, api_instances, parent_name, line_index) || {path, parent_name}
        child = registered_blueprint_declaration(path, lines, api_instances, blueprint_name, line_index) || {path, blueprint_name}
        (mount_prefixes.empty? ? [nil] : mount_prefixes).each do |mount|
          state.cross_file_mounts << {parent[0], parent[1], child[0], child[1], mount}
        end
      end
    end

    private def resolve_family_blueprint_prefixes(state : BlueprintScanState) : Nil
      # Preserve constructor prefixes before applying registration overrides.
      own_api_instances = clone_path_api_instances(state.path_api_instances)
      declarations = Set(ScopedNameKey).new
      state.path_api_instances.each_key do |path|
        _, blueprints = Noir::TreeSitterPythonRouteExtractor.extract_decorations_and_blueprints(fetch_file_content(path), ["flask", "quart"])
        blueprints.each { |blueprint| declarations << {path, blueprint.name} }
      end
      mounts = [] of Tuple(::String, ::String, ::String, ::String, ::String?)
      state.cross_file_mounts.each do |parent_path, parent, child_path, child, mount|
        if declarations.includes?({parent_path, parent})
          mounts << {parent_path, parent, child_path, child, mount}
        else
          # An omitted prefix is still a direct registration and must survive
          # alongside registrations through other blueprints.
          prefix = mount || own_api_instances[child_path]?.try(&.[child]?) || ""
          add_registered_prefix(state.register_blueprint, child_path, child, prefix)
        end
      end
      state.register_blueprint.each do |path, blueprint_info|
        blueprint_info.each do |blueprint_name, registered_prefixes|
          if state.path_api_instances.has_key?(path)
            api_instances = state.path_api_instances[path]
            # Flask's `BlueprintSetupState` uses the registration's
            # url_prefix in place of the blueprint's own one; it falls
            # back to the own prefix only when url_prefix is omitted.
            api_instances[blueprint_name] = registered_prefixes.first
          end
        end
      end
      apply_cross_file_mounts(mounts, state.register_blueprint, state.path_api_instances, own_api_instances)
    end
  end
end
