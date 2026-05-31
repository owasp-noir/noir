require "../../../models/analyzer"
require "../../../miniparsers/cpp_callee_extractor"

module Analyzer::Cpp
  class Crow < Analyzer
    CPP_EXTENSIONS = [".cpp", ".cc", ".cxx", ".h", ".hpp", ".hxx"]
    # CROW_ROUTE(app, "/path") — the app identifier and route literal.
    ROUTE_REGEX = /CROW_ROUTE\s*\(\s*[A-Za-z_][A-Za-z0-9_]*\s*,\s*"([^"]*)"\s*\)/
    # CROW_BP_ROUTE(bp, "/path") — blueprint-scoped route registration.
    BP_ROUTE_REGEX = /CROW_BP_ROUTE\s*\(\s*[A-Za-z_][A-Za-z0-9_]*\s*,\s*"([^"]*)"\s*\)/
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

      lines.each_with_index do |line, index|
        next if line.lstrip.starts_with?("//")

        websocket = false
        route_match = line.match(ROUTE_REGEX) || line.match(BP_ROUTE_REGEX) || line.match(ROUTE_DYNAMIC_REGEX)
        unless route_match
          if ws_match = line.match(WEBSOCKET_REGEX)
            route_match = ws_match
            websocket = true
          end
        end
        next unless route_match

        route_path = route_match[1]
        normalized_path, path_params = normalize_path(route_path)
        details = Details.new(PathInfo.new(path, index + 1))
        route_offset = line_offsets[index] + (route_match.begin(0) || 0)
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
      offsets = [
        source.index("CROW_ROUTE", search_start),
        source.index("CROW_BP_ROUTE", search_start),
        source.index("CROW_WEBSOCKET_ROUTE", search_start),
        source.index("route_dynamic", search_start),
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
