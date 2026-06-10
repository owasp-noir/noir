require "../../../miniparsers/python_route_extractor"
require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"

module Analyzer::Python
  class Bottle < PythonEngine
    # Reference: https://bottlepy.org/docs/dev/tutorial.html#request-routing
    #
    # Bottle supports two decorator forms:
    #
    #   1. Instance-bound: `@app.route("/path")` / `@app.get("/path")` / …
    #      Same shape as Flask/Sanic, handled by PythonRouteExtractor.
    #
    #   2. Bare (module-level default app): `@route("/path")` / `@get("/path")` / …
    #      Unique to Bottle-style micro frameworks — `from bottle import route, get`
    #      then decorate a function directly.
    #
    # For parameter extraction, Bottle exposes attributes on `request`:
    #   request.query.<name> / .get("name") / ["name"]       → query
    #   request.forms.<name> / .get("name") / ["name"]       → form
    #   request.json.get("name") / ["name"]                  → json
    #   request.headers.get("X-Foo") / ["X-Foo"]             → header
    #   request.get_cookie("name") / request.cookies.get(...) → cookie
    #
    # Path parameters use `<name>` or `<name:filter>` in the route string
    # and are preserved as-is in endpoint URLs (matching Flask's convention
    # — that's what fixture specs assert against).

    BARE_DECORATORS = %w[route get post put delete patch head options]

    # Per-line matchers, hoisted so they compile once: an interpolated
    # regex literal recompiles (PCRE2 JIT) on every evaluation, and the
    # bare-decorator patterns ran per decorator name on every source
    # line. The `.to_s` expansion is byte-identical to the previous
    # inline form, so matching behaviour is unchanged.
    # Tuple shape: {deco_name, "@deco" guard, bare_re, original_line_re, keyword_path_re}
    BARE_DECORATOR_PATTERNS = BARE_DECORATORS.map do |deco_name|
      {deco_name,
       "@#{deco_name}",
       /^@#{deco_name}\([rf]?['"]([^'"]*)['"](.*)/,
       /@#{deco_name}\s*\(\s*[rf]?['"]([^'"]*)['"]/,
       /^\s*@#{deco_name}\s*\([^)]*\b(?:path|rule|uri)\s*=\s*[rf]?['"]([^'"]*)['"]/m}
    end
    PROGRAMMATIC_ROUTE_RE = /\b(#{PYTHON_VAR_NAME_REGEX})\.route\s*\((.*)\)\s*$/m
    BOTTLE_INSTANCE_RE    = /^(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:bottle\.)?Bottle\(/
    MOUNT_RE              = /\b(#{PYTHON_VAR_NAME_REGEX})\.mount\s*\(\s*[rf]?['"]([^'"]*)['"]\s*,\s*(#{PYTHON_VAR_NAME_REGEX})/

    @keyword_regex_cache = Hash(::String, Regex).new
    @json_var_regex_cache = Hash(::String, Tuple(Regex, Regex)).new

    def analyze
      # Pulls from the detector-built file_map so subtree pruning and
      # --exclude-path apply to this pass too.
      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          next if path.includes?("/site-packages/")
          next if python_test_path?(path)
          @logger.debug "Analyzing #{path}"

          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            file_content = file.gets_to_end
            lines = file_content.lines
            next unless lines.any?(&.includes?("bottle"))

            router_prefixes = collect_router_prefixes(lines)

            # Tree-sitter pre-pass for Form 1 (`@<var>.route(...)` /
            # `@<var>.<method>(...)`). Replaces the per-line regex sweep.
            Noir::TreeSitterPythonRouteExtractor.extract_decorations(file_content).each do |deco|
              methods_literal = deco.methods.map { |m| "'#{m}'" }.join(",")
              extra_params = "methods=[#{methods_literal}]"
              prefixes = router_prefixes[deco.router_name]? || [""]
              prefixes.each do |prefix|
                process_route(
                  path,
                  lines,
                  line_index: deco.decorator_line,
                  route_path: join_paths(prefix, deco.path),
                  extra_params: extra_params,
                  definition_base_path: current_base_path,
                  source: file_content
                )
              end
            end

            # Form 2 still needs per-line regex — bare `@route("/path")` has
            # no router object, so the tree-sitter extractor (which gates
            # on `<router>.<attr>`) doesn't match it.
            lines.each_with_index do |line, line_index|
              effective_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, line_index, line) : line
              stripped = effective_line.gsub(" ", "")
              # `@deco` (contiguous in the source by both regex shapes) is a
              # necessary condition for either match, so non-decorator lines
              # skip the regex work entirely.
              if stripped.includes?('@')
                BARE_DECORATOR_PATTERNS.each do |deco_name, deco_guard, bare_re, orig_re, kw_re|
                  next unless stripped.includes?(deco_guard)
                  # `@route("/foo", method="POST")` or `@get("/foo")` on the stripped line.
                  if bare_match = stripped.match(bare_re)
                    # Recover spaces in path via the original line.
                    path_value = bare_match[1]
                    if orig_match = effective_line.match(orig_re)
                      path_value = orig_match[1]
                    end
                    extra = deco_name == "route" ? bare_match[2] : "methods=['#{deco_name.upcase}']"
                    process_route(
                      path,
                      lines,
                      line_index,
                      path_value,
                      extra,
                      definition_base_path: current_base_path,
                      source: file_content
                    )
                  elsif kw_path_match = effective_line.match(kw_re)
                    extra = deco_name == "route" ? effective_line : "methods=['#{deco_name.upcase}']"
                    process_route(
                      path,
                      lines,
                      line_index,
                      kw_path_match[1],
                      extra,
                      definition_base_path: current_base_path,
                      source: file_content
                    )
                  end
                end
              end

              if !line.lstrip.starts_with?("@") && effective_line.includes?(".route(")
                process_programmatic_route(
                  path,
                  lines,
                  line_index,
                  effective_line,
                  router_prefixes,
                  definition_base_path: current_base_path,
                  source: file_content
                )
              end
            end
          end
        end
      end

      result
    end

    private def process_programmatic_route(path : String,
                                           lines : Array(String),
                                           line_index : Int32,
                                           line : String,
                                           router_prefixes : Hash(String, Array(String)),
                                           *,
                                           definition_base_path : String,
                                           source : String)
      route_match = line.match(PROGRAMMATIC_ROUTE_RE)
      return unless route_match

      receiver = route_match[1]
      args = split_python_arguments(route_match[2])
      route_path = extract_keyword_string(args, "path") ||
                   extract_keyword_string(args, "rule") ||
                   extract_keyword_string(args, "uri") ||
                   args[0]?.try { |arg| extract_python_string(arg) }
      return unless route_path

      callback_name = extract_callback_name(args)
      return unless callback_name

      prefixes = router_prefixes[receiver]? || [""]
      prefixes.each do |prefix|
        process_route_for_function(
          path,
          lines,
          line_index,
          join_paths(prefix, route_path),
          route_match[2],
          callback_name,
          definition_base_path: definition_base_path,
          source: source
        )
      end
    end

    private def collect_router_prefixes(lines : Array(::String)) : Hash(::String, Array(::String))
      prefixes = Hash(::String, Array(::String)).new
      prefixes["app"] = [""]
      mounts = [] of Tuple(::String, ::String, ::String)

      lines.each_with_index do |line, index|
        stripped = line.gsub(" ", "")
        if stripped.includes?("Bottle(") && (instance_match = stripped.match(BOTTLE_INSTANCE_RE))
          prefixes[instance_match[1]] ||= [""]
        end

        next unless line.includes?(".mount(")

        effective_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
        effective_line.scan(MOUNT_RE) do |mount_match|
          next if mount_match.size < 4
          parent_router = mount_match[1]
          prefix = mount_match[2]
          child_router = mount_match[3]
          mounts << {parent_router, prefix, child_router}
          prefixes[child_router] ||= [] of ::String
          prefixes[child_router].delete("")
        end
      end

      changed = true
      iterations = 0
      while changed && iterations < mounts.size
        changed = false
        iterations += 1

        mounts.each do |parent_router, mount_prefix, child_router|
          parent_prefixes = prefixes[parent_router]?
          next unless parent_prefixes

          prefixes[child_router] ||= [] of ::String
          parent_prefixes.each do |parent_prefix|
            composed_prefix = join_paths(parent_prefix, mount_prefix)
            next if prefixes[child_router].includes?(composed_prefix)

            prefixes[child_router] << composed_prefix
            changed = true
          end
        end
      end

      prefixes
    end

    # Turn an (extra_params) string from a decorator into the list of HTTP
    # methods it applies to. Handles `method="POST"`, `method='POST'`,
    # `methods=["GET", "POST"]`, and the extractor-synthesized
    # `methods=['POST']` form.
    private def extract_methods(extra_params : String) : Array(String)
      methods = [] of String

      # Bottle accepts both `method="POST"` and `method=['POST']`, and the
      # PythonRouteExtractor also synthesizes `methods=['GET']` for
      # @<var>.<method> decorators — hence `methods?` covers both singular
      # and plural.
      if m = extra_params.match(/methods?\s*=\s*['"]([A-Za-z]+)['"]/)
        methods << m[1].upcase
      end

      if m = extra_params.match(/methods?\s*=\s*[\[\(]([^\]\)]+)[\]\)]/)
        m[1].scan(/['"]([A-Za-z]+)['"]/) do |method_match|
          methods << method_match[1].upcase
        end
      end

      methods.uniq
    end

    private def process_route(path : String,
                              lines : Array(String),
                              line_index : Int32,
                              route_path : String,
                              extra_params : String,
                              *,
                              definition_base_path : String,
                              source : String)
      methods = extract_methods(extra_params)
      methods = ["GET"] if methods.empty?

      def_index = Noir::PythonRouteExtractor.find_def_line(lines, line_index)
      return if def_index == line_index
      process_route_at_def(path, lines, line_index, route_path, methods, def_index,
        definition_base_path: definition_base_path, source: source)
    end

    private def process_route_for_function(path : String,
                                           lines : Array(String),
                                           line_index : Int32,
                                           route_path : String,
                                           extra_params : String,
                                           function_name : String,
                                           *,
                                           definition_base_path : String,
                                           source : String)
      methods = extract_methods(extra_params)
      methods = ["GET"] if methods.empty?

      def_index = find_function_def(lines, function_name)
      return unless def_index

      process_route_at_def(path, lines, line_index, route_path, methods, def_index,
        definition_base_path: definition_base_path, source: source)
    end

    private def process_route_at_def(path : String,
                                     lines : Array(String),
                                     line_index : Int32,
                                     route_path : String,
                                     methods : Array(String),
                                     def_index : Int32,
                                     *,
                                     definition_base_path : String,
                                     source : String)
      function_body = extract_function_body(lines, def_index)

      request_params = extract_request_params(function_body)

      # Preserve path parameters from `<name>` or `<name:filter>` syntax as path params.
      path_params = [] of Param
      route_path.scan(/<(\w+)(?::[^>]+)?>/) do |match|
        path_params << Param.new(match[1], "", "path")
      end

      # extract_function_body skips the def line, so body row 0 lives
      # at def_index + 1.
      handler_callees = build_callees_from(
        function_body,
        def_index + 1,
        path,
        definition_base_path: definition_base_path,
        source: source
      )

      details = Details.new(PathInfo.new(path, line_index + 1))
      methods.each do |method|
        endpoint = Endpoint.new(route_path, method, details)
        path_params.each { |p| endpoint.push_param(p) }
        request_params.each { |p| endpoint.push_param(p) }
        handler_callees.each { |c| endpoint.push_callee(c) }
        result << endpoint
      end
    end

    private def find_function_def(lines : Array(String), function_name : String) : Int32?
      lines.each_with_index do |line, index|
        stripped = line.lstrip
        if stripped.starts_with?("def #{function_name}(") ||
           stripped.starts_with?("def #{function_name} (") ||
           stripped.starts_with?("async def #{function_name}(") ||
           stripped.starts_with?("async def #{function_name} (")
          return index
        end
      end

      nil
    end

    private def split_python_arguments(args : String) : Array(String)
      parts = [] of String
      current = String::Builder.new
      paren_depth = 0
      bracket_depth = 0
      brace_depth = 0
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
        when '('
          paren_depth += 1
          current << ch
        when ')'
          paren_depth -= 1 if paren_depth > 0
          current << ch
        when '['
          bracket_depth += 1
          current << ch
        when ']'
          bracket_depth -= 1 if bracket_depth > 0
          current << ch
        when '{'
          brace_depth += 1
          current << ch
        when '}'
          brace_depth -= 1 if brace_depth > 0
          current << ch
        when ','
          if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0
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

    # Memoized per keyword — the keyword set is tiny (`path`, `rule`,
    # `uri`) but this runs per argument of every programmatic route.
    private def keyword_string_regex(keyword : String) : Regex
      @keyword_regex_cache[keyword] ||= /^\s*#{Regex.escape(keyword)}\s*=\s*(.+)$/m
    end

    private def extract_keyword_string(args : Array(String), keyword : String) : String?
      keyword_re = keyword_string_regex(keyword)
      args.each do |arg|
        keyword_match = arg.match(keyword_re)
        next unless keyword_match

        return extract_python_string(keyword_match[1])
      end

      nil
    end

    private def extract_python_string(expression : String) : String?
      string_match = expression.strip.match(/^[rf]?['"]([^'"]*)['"]/)
      string_match ? string_match[1] : nil
    end

    private def extract_callback_name(args : Array(String)) : String?
      args.each do |arg|
        callback_match = arg.match(/^\s*callback\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*$/)
        return callback_match[1] if callback_match
      end

      nil
    end

    private def join_paths(prefix : ::String, path : ::String) : ::String
      return normalize_path(path) if prefix.empty?
      return normalize_path(prefix) if path.empty?

      normalize_path("#{prefix}/#{path}")
    end

    private def normalize_path(path : ::String) : ::String
      normalized = path.gsub(/\/+/, "/")
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized
    end

    # Walk forward from `def_index` collecting lines at strictly greater
    # indentation than the def line — that's the function body.
    private def extract_function_body(lines : Array(String), def_index : Int32) : String
      return "" if def_index >= lines.size
      def_line = lines[def_index]
      base_indent = def_line.size - def_line.lstrip.size

      body = [] of String
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

    # Bottle attributes whose parameter type is independent of HTTP method.
    # Maps the Python accessor name on `request.<name>` to the noir param_type.
    DICT_ACCESSORS = {
      "query"   => "query",
      "forms"   => "form",
      "json"    => "json",
      "headers" => "header",
      "cookies" => "cookie",
    }

    # Attribute names on accessor objects that are not user parameters.
    DICT_METHOD_NAMES = Set{"get", "getall", "getone", "items", "keys", "values", "pop"}

    # `extract_request_params` runs once per route and used to rebuild
    # three PCRE2 patterns per accessor on every call. The accessor set
    # is fixed, so precompile the access patterns once here.
    # Tuple shape: {noir_param_type, get_re, bracket_re, attribute_re}
    DICT_ACCESSOR_PATTERNS = DICT_ACCESSORS.map do |accessor, param_type|
      {param_type,
       /request\.#{accessor}\.get\s*\(\s*['"]([^'"]+)['"]/,
       /request\.#{accessor}\s*\[\s*['"]([^'"]+)['"]\s*\]/,
       /request\.#{accessor}\.([A-Za-z_][A-Za-z0-9_]*)\b/}
    end

    private def json_var_regexes(var : String) : Tuple(Regex, Regex)
      @json_var_regex_cache[var] ||= begin
        v = Regex.escape(var)
        {/#{v}\.get\s*\(\s*['"]([^'"]+)['"]/,
         /#{v}\s*\[\s*['"]([^'"]+)['"]\s*\]/}
      end
    end

    # Scan a function body for Bottle's request accessors.
    # Bottle uses explicit accessor names (`request.forms` for form,
    # `request.json` for json, …) so method-based disambiguation isn't needed.
    private def extract_request_params(body : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new
      json_variables = [] of String

      record = ->(name : String, type : String) do
        key = "#{type}:#{name}"
        unless seen.includes?(key)
          params << Param.new(name, "", type)
          seen << key
        end
      end

      body.scan(/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*request\.json\b/) do |m|
        json_variables << m[1] unless json_variables.includes?(m[1])
      end

      DICT_ACCESSOR_PATTERNS.each do |param_type, get_re, bracket_re, attribute_re|
        # request.<accessor>.get("name")
        body.scan(get_re) do |m|
          record.call(m[1], param_type)
        end
        # request.<accessor>["name"]
        body.scan(bracket_re) do |m|
          record.call(m[1], param_type)
        end
        # request.<accessor>.<attribute>  — skip dict-API method names.
        body.scan(attribute_re) do |m|
          next if DICT_METHOD_NAMES.includes?(m[1])
          record.call(m[1], param_type)
        end
      end

      # Bottle-specific cookie helper.
      body.scan(/request\.get_cookie\s*\(\s*['"]([^'"]+)['"]/) do |m|
        record.call(m[1], "cookie")
      end

      json_variables.each do |var|
        get_re, bracket_re = json_var_regexes(var)
        body.scan(get_re) do |m|
          record.call(m[1], "json")
        end
        body.scan(bracket_re) do |m|
          record.call(m[1], "json")
        end
      end

      params
    end
  end
end
