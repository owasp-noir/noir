require "../../../models/analyzer"
require "../../../miniparsers/cpp_callee_extractor"

module Analyzer::Cpp
  class Crow < Analyzer
    CPP_EXTENSIONS = [".cpp", ".cc", ".cxx", ".h", ".hpp", ".hxx"]
    # CROW_ROUTE(app, "/path") — the app identifier and route literal.
    ROUTE_REGEX = /CROW_ROUTE\s*\(\s*[A-Za-z_][A-Za-z0-9_]*\s*,\s*"([^"]*)"\s*\)/
    # CROW_BP_ROUTE(bp, "/path") — blueprint-scoped route registration.
    # Group 1 = blueprint identifier, group 2 = route literal.
    BP_ROUTE_REGEX = /CROW_BP_ROUTE\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*"([^"]*)"\s*\)/
    # crow::Blueprint name("prefix", ...) — first string arg is the URL prefix.
    BLUEPRINT_DECL_REGEX = /(?:crow::)?Blueprint\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*"([^"]*)"/
    # parent.register_blueprint(child) — nests `child` under `parent`'s prefix.
    BP_NEST_REGEX = /([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*register_blueprint\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/
    # app.route_dynamic("/path") — runtime string route (no compile-time macro).
    ROUTE_DYNAMIC_REGEX = /\.\s*route_dynamic\s*\(\s*"([^"]*)"\s*\)/
    # CROW_WEBSOCKET_ROUTE(app, "/path") — websocket upgrade endpoint.
    WEBSOCKET_REGEX = /CROW_WEBSOCKET_ROUTE\s*\(\s*[A-Za-z_][A-Za-z0-9_]*\s*,\s*"([^"]*)"\s*\)/
    # .methods("POST"_method, "GET"_method) clause.
    METHODS_REGEX     = /\.methods\s*\(([^)]*)\)/
    METHOD_TOKEN      = /"([A-Za-z]+)"_method/
    HTTP_METHOD_TOKEN = /(?:crow::)?HTTPMethod::([A-Za-z]+)/
    CROW_METHOD_TOKEN = /CROW_HTTP_METHOD_([A-Za-z]+)/
    # Path placeholder: <int>, <string>, <uint>, <double>, <path> — and the
    # non-standard but occasionally seen <type:name> form.
    PATH_PARAM_REGEX = /<([^<>:]+)(?::([^<>]+))?>/
    # url_params.get("x") plus the list/dict variants get_list / get_dict.
    URL_PARAM_GET = /url_params\s*\.\s*get(?:_list|_dict)?(?:\s*<[^>]+>)?\s*\(\s*"([^"]+)"/
    HEADER_VALUE  = /get_header_value\s*\(\s*"([^"]+)"/
    # ctx.get_cookie("name") via the CookieParser middleware.
    COOKIE_GET  = /\bget_cookie\s*\(\s*"([^"]+)"/
    BODY_ACCESS = /\b(req|request)\s*\.\s*body\b/

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      begin
        locator = CodeLocator.instance
        files = CPP_EXTENSIONS.flat_map { |ext| locator.files_by_extension(ext) }

        parallel_analyze(files) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)
          analyze_file(path, include_callee)
        end
      rescue e
        logger.debug "Crow analyzer failed: #{e.message}"
      end

      result
    end

    private def analyze_file(path : String, include_callee : Bool)
      source = read_file_content(path)
      return unless source.includes?("CROW_ROUTE") || source.includes?("CROW_BP_ROUTE") ||
                    source.includes?("CROW_WEBSOCKET_ROUTE") || source.includes?("route_dynamic")

      # Blank comments so commented-out routes (e.g. inside `/* ... */`) and
      # documentation snippets are not picked up as real endpoints.
      source = Noir::CppCalleeExtractor.strip_comments(source)
      lines = source.split("\n")
      line_offsets = line_start_offsets(source)
      bp_prefixes = source.includes?("CROW_BP_ROUTE") ? blueprint_prefixes(source) : nil

      lines.each_with_index do |line, index|
        next if line.lstrip.starts_with?("//")

        websocket = false
        if bp_match = line.match(BP_ROUTE_REGEX)
          route_match = bp_match
          # Blueprint routes are registered as `'/' + prefix + rule`, where the
          # prefix walks up any `register_blueprint` nesting chain.
          route_path = join_blueprint_prefix(bp_prefixes.try &.[bp_match[1]]?, bp_match[2])
        elsif std_match = (line.match(ROUTE_REGEX) || line.match(ROUTE_DYNAMIC_REGEX))
          route_match = std_match
          route_path = std_match[1]
        elsif ws_match = line.match(WEBSOCKET_REGEX)
          route_match = ws_match
          route_path = ws_match[1]
          websocket = true
        else
          next
        end

        normalized_path, path_params = normalize_path(route_path)
        details = Details.new(PathInfo.new(path, index + 1))
        # line_offsets is byte-based; begin(0) is a char index within the line —
        # convert the line prefix to its byte length so route_offset is a true
        # byte offset consistent with the byte-based extractor/search below.
        route_offset = line_offsets[index] + line[0, (route_match.begin(0) || 0)].bytesize
        search_start = route_offset + route_match[0].bytesize

        # The websocket handler is a chain of `.onopen/.onmessage/...` lambdas
        # rather than a single request handler, so we register the upgrade
        # endpoint without trying to mine request params from it.
        if websocket
          endpoint = Endpoint.new(normalized_path, "GET", path_params.dup, details)
          endpoint.protocol = "ws"
          result << endpoint
          next
        end

        # `.methods(...)` may sit on the same line as the route or on one of the
        # following continuation lines before the handler lambda.
        search_window = line
        (1..3).each do |offset|
          break if index + offset >= lines.size
          next_line = lines[index + offset]
          break if route_line?(next_line)
          search_window += " " + next_line
        end

        methods = [] of String
        if methods_match = search_window.match(METHODS_REGEX)
          methods = parse_methods(methods_match[1])
        end
        methods << "GET" if methods.empty?

        route_callees = include_callee ? callees_for_route(source, path, search_start) : [] of Noir::CppCalleeExtractor::Entry
        route_params = params_for_route(source, search_start)

        methods.uniq.each do |method|
          endpoint = Endpoint.new(normalized_path, method, path_params.dup, details)
          route_params.each { |param| push_unique(endpoint, param) }
          Noir::CppCalleeExtractor.attach_to(endpoint, route_callees) if include_callee
          result << endpoint
        end
      end
    end

    private def route_line?(line : String) : Bool
      !!(line.match(ROUTE_REGEX) || line.match(BP_ROUTE_REGEX) ||
        line.match(ROUTE_DYNAMIC_REGEX) || line.match(WEBSOCKET_REGEX))
    end

    private def callees_for_route(source : String, path : String, search_start : Int32) : Array(Noir::CppCalleeExtractor::Entry)
      block = Noir::CppCalleeExtractor.extract_lambda_block_after(source, search_start, next_route_offset(source, search_start))
      return [] of Noir::CppCalleeExtractor::Entry unless block

      body, start_line = block
      Noir::CppCalleeExtractor.callees_for_body(body, path, start_line)
    end

    private def params_for_route(source : String, search_start : Int32) : Array(Param)
      block = Noir::CppCalleeExtractor.extract_lambda_block_after(source, search_start, next_route_offset(source, search_start))
      return [] of Param unless block

      body, _ = block
      collect_params_from_block(body)
    end

    private def next_route_offset(source : String, search_start : Int32) : Int32
      # search_start is a byte offset; use byte_index so the returned limit stays
      # in byte space (consistent with the byte-based lambda extractor).
      offsets = [
        source.byte_index("CROW_ROUTE", search_start),
        source.byte_index("CROW_BP_ROUTE", search_start),
        source.byte_index("CROW_WEBSOCKET_ROUTE", search_start),
        source.byte_index("route_dynamic", search_start),
      ].compact
      offsets.min? || source.bytesize
    end

    private def line_start_offsets(source : String) : Array(Int32)
      offsets = [0]
      index = 0
      while index < source.bytesize
        offsets << index + 1 if source.byte_at(index) == '\n'.ord
        index += 1
      end
      offsets
    end

    # Builds the effective URL prefix for every blueprint declared in `source`,
    # resolving `register_blueprint` nesting. Crow prepends a parent blueprint's
    # prefix to its children (`blueprint.prefix_ = prefix_ + '/' + blueprint.prefix_`).
    private def blueprint_prefixes(source : String) : Hash(String, String)
      own = {} of String => String
      source.scan(BLUEPRINT_DECL_REGEX) { |m| own[m[1]] = m[2] }
      return own if own.empty?

      parent = {} of String => String
      source.scan(BP_NEST_REGEX) do |m|
        par, child = m[1], m[2]
        # Only blueprint→blueprint nesting matters; `app.register_blueprint(bp)`
        # attaches `bp` to the app root, which carries no prefix.
        parent[child] = par if own.has_key?(par) && own.has_key?(child) && par != child
      end

      effective = {} of String => String
      own.each_key { |name| effective[name] = resolve_blueprint_prefix(name, own, parent, Set(String).new) }
      effective
    end

    private def resolve_blueprint_prefix(name : String, own : Hash(String, String), parent : Hash(String, String), seen : Set(String)) : String
      base = own[name]? || ""
      return base unless seen.add?(name) # cycle guard
      if par = parent[name]?
        parent_prefix = resolve_blueprint_prefix(par, own, parent, seen)
        return parent_prefix.empty? ? base : "#{parent_prefix}/#{base}"
      end
      base
    end

    # Mirrors Crow's `'/' + prefix_ + rule` rule registration, collapsing any
    # accidental double slash (e.g. an empty-prefix blueprint).
    private def join_blueprint_prefix(prefix : String?, rule : String) : String
      return rule if prefix.nil? || prefix.empty?
      ("/" + prefix + rule).gsub(%r{/{2,}}, "/")
    end

    private def normalize_path(route_path : String) : Tuple(String, Array(Param))
      params = [] of Param
      counter = 0
      normalized = route_path.gsub(PATH_PARAM_REGEX) do |_|
        maybe_name = $~[2]?
        name = if maybe_name && !maybe_name.empty?
                 maybe_name
               else
                 counter += 1
                 "param#{counter}"
               end
        params << Param.new(name, "", "path")
        "{#{name}}"
      end
      {normalized, params}
    end

    private def parse_methods(raw : String) : Array(String)
      methods = [] of String
      raw.scan(METHOD_TOKEN) do |m|
        methods << m[1].upcase
      end
      raw.scan(HTTP_METHOD_TOKEN) do |m|
        methods << normalize_method_name(m[1])
      end
      raw.scan(CROW_METHOD_TOKEN) do |m|
        methods << normalize_method_name(m[1])
      end
      methods.reject(&.empty?).uniq!
    end

    private def normalize_method_name(name : String) : String
      case name.upcase
      when "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"
        name.upcase
      else
        ""
      end
    end

    private def collect_params_from_block(block : String) : Array(Param)
      params = [] of Param
      block.each_line do |line|
        collect_params(line).each do |param|
          next if params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
          params << param
        end
      end
      params
    end

    private def collect_params(line : String) : Array(Param)
      params = [] of Param
      line.scan(URL_PARAM_GET) do |m|
        params << Param.new(m[1], "", "query")
      end
      line.scan(HEADER_VALUE) do |m|
        params << Param.new(m[1], "", "header")
      end
      line.scan(COOKIE_GET) do |m|
        params << Param.new(m[1], "", "cookie")
      end
      if line.match(BODY_ACCESS)
        params << Param.new("body", "", "json")
      end
      params
    end

    private def push_unique(endpoint : Endpoint, param : Param)
      return if endpoint.params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      endpoint.push_param(param)
    end
  end
end
