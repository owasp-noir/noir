require "../../../miniparsers/python_route_extractor"
require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"

module Analyzer::Python
  class Robyn < PythonEngine
    # Reference: https://robyn.tech/documentation
    #
    # Robyn is a Rust-backed Python web framework whose route registration
    # mirrors FastAPI's decorator shape but with two notable differences:
    #
    #   1. Path-param syntax uses `:name` instead of `{name}` — normalize
    #      to Noir's `{name}` convention so URL matching aligns with the
    #      rest of the analyzers.
    #   2. Sub-routing is `SubRouter(__file__, "/prefix")` + `app.include_router(sub)`;
    #      the prefix is a positional argument (not `prefix=` like FastAPI).
    #
    # Param extraction is best-effort:
    #   * Path params come from `:name` segments in the URL.
    #   * Body params come from `request.json()` keys when accessed via
    #     bracket / `.get()` notation.

    HTTP_METHOD_DECORATORS = %w[get post put patch delete head options trace]
    WEBSOCKET_ATTRIBUTES   = {"websocket" => "GET"}

    # Hoisted out of the per-line loops: an interpolated regex literal
    # recompiles (PCRE2 JIT) on every evaluation, and these interpolate
    # only constants. The `.to_s` expansion is byte-identical to the
    # previous inline form, so matching behaviour is unchanged.
    ROBYN_INSTANCE_RE = /^\s*(#{PYTHON_VAR_NAME_REGEX})\s*=\s*(?:robyn\.)?Robyn\s*\(/
    SUBROUTER_RE      = /^\s*(#{PYTHON_VAR_NAME_REGEX})\s*=\s*(?:robyn\.)?SubRouter\s*\((.*)/m
    INCLUDE_ROUTER_RE = /\b(#{PYTHON_VAR_NAME_REGEX})\.include_router\s*\(\s*(#{PYTHON_VAR_NAME_REGEX})/

    @json_var_regex_cache = Hash(::String, Tuple(Regex, Regex)).new

    def analyze
      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        router_prefixes = Hash(::String, ::String).new
        # `app` is the canonical Robyn instance name — accept it implicitly
        # so a fresh fixture without an explicit prefix registration still
        # surfaces routes.
        router_prefixes["app"] = ""
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          next if path.includes?("/site-packages/")
          next if python_test_path?(path)

          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            file_content = file.gets_to_end
            next unless file_content.includes?("robyn")
            lines = file_content.lines

            # Capture `name = Robyn(__file__)` and `name = SubRouter(__file__, "/prefix")`
            # so prefix composition can resolve via include_router below.
            collect_router_assignments(lines, router_prefixes)

            # `app.include_router(sub_router)` — propagate the SubRouter's
            # prefix without rewriting the original entry; the SubRouter
            # already owns its prefix.
            scan_include_routers(lines, router_prefixes)

            # Decorator-driven routes via tree-sitter (handles multi-line
            # decorator headers cleanly).
            Noir::TreeSitterPythonRouteExtractor.extract_decorations(file_content, nil, WEBSOCKET_ATTRIBUTES).each do |deco|
              next unless router_prefixes.has_key?(deco.router_name)
              attr = deco.attribute_name.downcase
              next unless attr.in?(HTTP_METHOD_DECORATORS) || attr == "websocket"

              http_method = attr == "websocket" ? "GET" : attr.upcase
              prefix = router_prefixes[deco.router_name]
              route_path = normalize_path(deco.path)
              full_path = join_prefix(prefix, route_path)

              params = [] of Param
              # `:name` and `{name}` segments are path params.
              full_path.scan(/\{([A-Za-z_][A-Za-z0-9_]*)\}/) do |m|
                params << Param.new(m[1], "", "path")
              end

              def_index = deco.def_line >= 0 ? deco.def_line : Noir::PythonRouteExtractor.find_def_line(lines, deco.decorator_line)
              if def_index >= 0 && def_index < lines.size
                handler_body = extract_function_body(lines, def_index)
                extract_body_params(handler_body).each { |p| params << p }
              end

              details = Details.new(PathInfo.new(path, deco.decorator_line + 1))
              endpoint = Endpoint.new(full_path, http_method, params, details)
              endpoint.protocol = "ws" if attr == "websocket"
              result << endpoint
            end
          end
        end
      end

      Fiber.yield
      result
    end

    # Capture `<name> = (robyn.)?Robyn(...)` and `<name> = (robyn.)?SubRouter(...)`.
    # Robyn's SubRouter takes the prefix as a positional argument:
    #   SubRouter(__file__, "/api")
    private def collect_router_assignments(lines : Array(::String), router_prefixes : Hash(::String, ::String))
      lines.each_with_index do |line, index|
        if line.includes?("Robyn") && (m = line.match(ROBYN_INSTANCE_RE))
          router_prefixes[m[1]] = ""
        end

        effective_line = if line.includes?("SubRouter") && python_paren_delta(line) > 0
                           join_until_python_call_closes(lines, index, line)
                         else
                           line
                         end
        if effective_line.includes?("SubRouter") && (m = effective_line.match(SUBROUTER_RE))
          name = m[1]
          tail = m[2]
          prefix = extract_subrouter_prefix(tail)
          router_prefixes[name] = normalize_path(prefix)
        end
      end
    end

    # SubRouter signature: SubRouter(__file__, "/prefix")
    # Extract the second positional argument (the prefix string) or fall
    # back to a `prefix=` keyword if the caller uses one. Returns "" when
    # no prefix can be resolved from the call site.
    private def extract_subrouter_prefix(tail : ::String) : ::String
      if kw = tail.match(/prefix\s*=\s*[rf]?['"]([^'"]*)['"]/)
        return kw[1]
      end
      # Positional form: skip the first argument, take the next string
      # literal up to the closing paren.
      args = tail.split(")", 2).first
      parts = args.split(",", 3)
      return "" if parts.size < 2
      if pm = parts[1].strip.match(/^[rf]?['"]([^'"]*)['"]$/)
        return pm[1]
      end
      ""
    end

    # `parent.include_router(child)` composes nested SubRouter prefixes.
    # The root Robyn app usually has an empty prefix, but real apps also
    # nest routers, e.g. `api.include_router(admin)`, which should place
    # `admin` routes under `/api/admin`.
    private def scan_include_routers(lines : Array(::String), router_prefixes : Hash(::String, ::String))
      includes = [] of Tuple(::String, ::String)

      lines.each_with_index do |line, index|
        next unless line.includes?(".include_router(")

        effective_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
        effective_line.scan(INCLUDE_ROUTER_RE) do |m|
          next if m.size < 3
          includes << {m[1], m[2]}
        end
      end

      changed = true
      iterations = 0
      while changed && iterations < includes.size
        changed = false
        iterations += 1

        includes.each do |parent, child|
          parent_prefix = router_prefixes[parent]?
          child_prefix = router_prefixes[child]?
          next if parent_prefix.nil? || child_prefix.nil? || parent_prefix.empty?
          next if child_prefix == parent_prefix || child_prefix.starts_with?("#{parent_prefix}/")

          composed_prefix = normalize_path(join_prefix(parent_prefix, child_prefix))
          next if composed_prefix == child_prefix

          router_prefixes[child] = composed_prefix
          changed = true
        end
      end
    end

    # Robyn uses `:name` for path params; Noir's canonical form is `{name}`.
    # Convert each `:identifier` segment when it occupies a full path
    # segment (i.e. preceded by `/` or start, followed by `/` or end).
    private def normalize_path(path : ::String) : ::String
      path.gsub(/(^|\/):([A-Za-z_][A-Za-z0-9_]*)/) do |_, match|
        prefix = match[1]
        name = match[2]
        "#{prefix}{#{name}}"
      end
    end

    private def join_prefix(prefix : ::String, route : ::String) : ::String
      return route if prefix.empty?
      normalized_prefix = prefix.ends_with?("/") ? prefix[0..-2] : prefix
      if route.starts_with?("/")
        "#{normalized_prefix}#{route}"
      else
        "#{normalized_prefix}/#{route}"
      end
    end

    # Walk forward from `def_index` collecting lines at strictly greater
    # indentation than the def line — that's the function body.
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

    # Memoized per JSON-variable name (`data`, `body`, ...): the patterns
    # interpolate a discovered name so they can't be class constants, but
    # handler bodies reuse the same few names across a whole project.
    private def json_var_regexes(var : ::String) : Tuple(Regex, Regex)
      @json_var_regex_cache[var] ||= begin
        v = Regex.escape(var)
        {/#{v}\[['"]([^'"]+)['"]\]/,
         /#{v}\.get\(['"]([^'"]+)['"]/}
      end
    end

    # Robyn exposes `request.json()`, `request.query_params`, and
    # `request.headers` for parameter access. The fixture-level idioms
    # are bracket / `.get()` access, which is enough to recover the
    # field names without modelling the full request object.
    private def extract_body_params(body : ::String) : Array(Param)
      params = [] of Param
      seen = Set(::String).new

      record = ->(name : ::String, type : ::String) do
        key = "#{type}:#{name}"
        unless seen.includes?(key)
          params << Param.new(name, "", type)
          seen << key
        end
      end

      # `data = request.json()` — collect the variable name, then look up
      # bracket / `.get(...)` accesses on it.
      json_vars = [] of ::String
      body.scan(/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:await\s+)?request\.json\s*\(\s*\)/) do |m|
        json_vars << m[1]
      end

      # Direct one-liners: `request.json()["name"]` /
      # `request.json().get("name")`.
      body.scan(/(?:await\s+)?request\.json\s*\(\s*\)\s*\[['"]([^'"]+)['"]\]/) do |m|
        record.call(m[1], "json")
      end
      body.scan(/(?:await\s+)?request\.json\s*\(\s*\)\.get\(['"]([^'"]+)['"]/) do |m|
        record.call(m[1], "json")
      end

      json_vars.each do |var|
        bracket_re, get_re = json_var_regexes(var)
        body.scan(bracket_re) { |m| record.call(m[1], "json") }
        body.scan(get_re) { |m| record.call(m[1], "json") }
      end

      # `request.query_params.get("name")` / `request.query_params["name"]`
      body.scan(/request\.query_params\.get\(['"]([^'"]+)['"]/) { |m| record.call(m[1], "query") }
      body.scan(/request\.query_params\[['"]([^'"]+)['"]\]/) { |m| record.call(m[1], "query") }

      # `request.headers.get("X-Foo")` / `request.headers["X-Foo"]`
      body.scan(/request\.headers\.get\(['"]([^'"]+)['"]/) { |m| record.call(m[1], "header") }
      body.scan(/request\.headers\[['"]([^'"]+)['"]\]/) { |m| record.call(m[1], "header") }

      params
    end
  end
end
