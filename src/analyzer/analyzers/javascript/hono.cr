require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"
require "./express/router_mount_scanner"

module Analyzer::Javascript
  class Hono < JavascriptEngine
    ON_ROUTE_CALL_HINTS   = [".on(", ".on ("]
    ON_ROUTE_CALL_PATTERN = /\.(?:\s|\n|\r)*on(?:\s|\n|\r)*\(/

    def analyze
      result = [] of Endpoint
      static_dirs = [] of Hash(String, String)

      scan_for_router_mounts

      parallel_file_scan do |path|
        begin
          content = read_file_content(path)
          include_callee = callees_needed?
          callees_by_route = include_callee ? Noir::JSCalleeExtractor.callees_for_routes(content, path) : {} of String => Array(Noir::JSCalleeExtractor::Entry)
          parser_endpoints = Noir::JSRouteExtractor.extract_routes(path, content, @is_debug,
            include_callees: include_callee, route_callees: callees_by_route)
          parser_endpoints.each do |endpoint|
            extract_path_params(endpoint)
            result << endpoint
          end

          # Extract app.on() patterns not handled by JSRouteExtractor.
          # The primary extractor already gates on `test_stub_only?` and
          # minified bundles; this auxiliary pass has its own regex
          # walk, so it has to repeat the same gates — without the stub
          # gate, `app.on('GET', '/x10', ...)` from hono's own
          # `*.test.ts` suites slips through, and without the minified
          # gate a multi-MB bundle pays the full scan (issue #1903).
          if on_route_candidate?(content) &&
             !Noir::JSRouteExtractor.test_stub_only?(path, content) &&
             !Noir::JSRouteExtractor.minified_content?(content)
            extract_on_routes(path, content, result, callees_by_route, include_callee)
          end

          collect_static_paths(path, content, static_dirs, :hono)
        rescue e
          logger.debug "Parser failed for #{path}: #{e.message}, falling back to regex"
          analyze_with_regex(path, result)
        end
      end

      process_static_dirs(static_dirs, result)

      result
    end

    private def process_static_dirs(static_dirs : Array(Hash(String, String)), result : Array(Endpoint))
      process_js_static_dirs(static_dirs, result)
    end

    private def on_route_candidate?(content : String) : Bool
      ON_ROUTE_CALL_HINTS.any? { |hint| content.includes?(hint) } ||
        content.matches?(ON_ROUTE_CALL_PATTERN)
    end

    private def extract_on_routes(path : String,
                                  content : String,
                                  result : Array(Endpoint),
                                  callees_by_route : Hash(String, Array(Noir::JSCalleeExtractor::Entry)),
                                  include_callee : Bool)
      http_methods = %w[get post put delete patch options head]
      lines = content.lines
      line_offset = 0
      lines.each_with_index do |line, index|
        methods = [] of String
        url = ""
        call_start = nil.as(Int32?)

        # app.on('GET', '/path', ...) - single method string
        if match = line.match(/\b(?:app|router|hono)\s*\.\s*on\s*\(\s*['"](\w+)['"]\s*,\s*['"]([^'"]+)['"]/)
          method = match[1].downcase
          if http_methods.includes?(method)
            methods << method
            url = match[2]
            call_start = line_offset + (match.begin(0) || 0)
          end
          # app.on(['GET', 'POST'], '/path', ...) - array of methods
        elsif match = line.match(/\b(?:app|router|hono)\s*\.\s*on\s*\(\s*\[([^\]]+)\]\s*,\s*['"]([^'"]+)['"]/)
          methods_str = match[1]
          url = match[2]
          call_start = line_offset + (match.begin(0) || 0)
          methods_str.scan(/['"](\w+)['"]/) do |m|
            method = m[1].downcase
            methods << method if http_methods.includes?(method) && !methods.includes?(method)
          end
        end

        if methods.empty? || url.empty?
          line_offset += line.bytesize + 1
          next
        end

        # Pre-extract handler-body params once so each method-variant
        # endpoint gets the same params without re-walking lines.
        body_params = [] of Param
        ((index + 1)...lines.size).each do |i|
          handler_line = lines[i]
          break if handler_line =~ /^\s*\}\s*\)\s*$/
          line_to_params(handler_line).each do |param|
            body_params << param
          end
        end
        direct_callees = include_callee && call_start ? on_route_callees(content, path, call_start) : [] of Noir::JSCalleeExtractor::Entry

        methods.each do |http_method|
          next if result.any? { |e| e.url == url && e.method == http_method.upcase }

          endpoint = Endpoint.new(url, http_method.upcase)
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint.details = details
          Noir::JSRouteExtractor.attach_callees(endpoint, callees_by_route, http_method.upcase, url, index + 1)
          attach_js_callees(endpoint, direct_callees)

          body_params.each { |param| endpoint.push_param(param) }
          extract_path_params(endpoint)

          result << endpoint
        end
        line_offset += line.bytesize + 1
      end
    end

    private def on_route_callees(content : String, path : String, call_start : Int32) : Array(Noir::JSCalleeExtractor::Entry)
      paren_open = content.index("(", call_start)
      return [] of Noir::JSCalleeExtractor::Entry unless paren_open

      paren_close = Noir::JSRouteExtractor.find_matching_paren(content, paren_open)
      return [] of Noir::JSCalleeExtractor::Entry unless paren_close

      args = split_top_level_args(content, paren_open + 1, paren_close)
      return [] of Noir::JSCalleeExtractor::Entry if args.size < 3

      handler_source, handler_start = args[2]
      handler_callees(handler_source, handler_start, content, path)
    end

    private def handler_callees(handler_source : String, handler_start : Int32, content : String, path : String) : Array(Noir::JSCalleeExtractor::Entry)
      if arrow_idx = handler_source.index("=>")
        body_start = skip_whitespace(content, handler_start + arrow_idx + 2)
        return [] of Noir::JSCalleeExtractor::Entry if body_start >= content.size

        if content[body_start]? == '{'
          return block_handler_callees(content, path, body_start)
        end

        body = content[body_start...(handler_start + handler_source.size)].strip
        return [] of Noir::JSCalleeExtractor::Entry if body.empty?

        return Noir::JSCalleeExtractor.callees_for_function_body(body, path, line_for_pos(content, body_start), language: javascript_source_language(path))
      end

      function_idx = handler_source.index(/\bfunction\b/)
      return [] of Noir::JSCalleeExtractor::Entry unless function_idx

      open_brace = content.index("{", handler_start + function_idx)
      return [] of Noir::JSCalleeExtractor::Entry unless open_brace

      block_handler_callees(content, path, open_brace)
    end

    private def block_handler_callees(content : String, path : String, open_brace : Int32) : Array(Noir::JSCalleeExtractor::Entry)
      close_brace = Noir::JSRouteExtractor.find_matching_brace(content, open_brace)
      return [] of Noir::JSCalleeExtractor::Entry unless close_brace

      body = content[(open_brace + 1)...close_brace]
      Noir::JSCalleeExtractor.callees_for_function_body(body, path, line_for_pos(content, open_brace), language: javascript_source_language(path))
    end

    private def split_top_level_args(content : String, start_pos : Int32, end_pos : Int32) : Array(Tuple(String, Int32))
      args = [] of Tuple(String, Int32)
      arg_start = start_pos
      depth = 0
      quote : Char? = nil
      escaped = false
      i = start_pos

      while i < end_pos
        char = content[i]

        if quote
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            quote = nil
          end
          i += 1
          next
        end

        case char
        when '\'', '"', '`'
          quote = char
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when ','
          if depth == 0
            args << normalized_arg(content, arg_start, i)
            arg_start = i + 1
          end
        end

        i += 1
      end

      args << normalized_arg(content, arg_start, end_pos)
      args
    end

    private def normalized_arg(content : String, start_pos : Int32, end_pos : Int32) : Tuple(String, Int32)
      start_idx = skip_whitespace(content, start_pos)
      stop_idx = end_pos
      while stop_idx > start_idx && content[stop_idx - 1].whitespace?
        stop_idx -= 1
      end

      {content[start_idx...stop_idx], start_idx}
    end

    private def skip_whitespace(content : String, pos : Int32) : Int32
      i = pos
      while i < content.size && content[i].whitespace?
        i += 1
      end
      i
    end

    private def line_for_pos(content : String, pos : Int32) : Int32
      content[0...pos].count('\n') + 1
    end

    private def analyze_with_regex(path : String, result : Array(Endpoint))
      last_endpoint = Endpoint.new("", "")
      file_content = read_file_content(path)

      file_content.each_line.with_index do |line, index|
        endpoints = line_to_endpoints(line)
        endpoints.each do |endpoint|
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint.details = details
          result << endpoint
          last_endpoint = endpoint
        end

        line_to_params(line).each do |param|
          unless last_endpoint.method.empty?
            last_endpoint.push_param(param)
          end
        end
      end
    end

    private def extract_path_params(endpoint : Endpoint)
      if endpoint.url.includes?(":")
        endpoint.url.scan(/:(\w+)/) do |m|
          if m.size > 0
            param = Param.new(m[1], "", "path")
            endpoint.push_param(param) if !endpoint.params.any? { |p| p.name == m[1] && p.param_type == "path" }
          end
        end
      end
    end

    def line_to_params(line : String) : Array(Param)
      # c.req.query('param') - any variable name (c, ctx, context, etc.)
      if line =~ /\w+\.req\.query\s*\(\s*['"]([^'"]+)['"]\s*\)/
        return [Param.new($1, "", "query")]
      end

      # c.req.queries('param') - returns array
      if line =~ /\w+\.req\.queries\s*\(\s*['"]([^'"]+)['"]\s*\)/
        return [Param.new($1, "", "query")]
      end

      # c.req.param('id')
      if line =~ /\w+\.req\.param\s*\(\s*['"]([^'"]+)['"]\s*\)/
        return [Param.new($1, "", "path")]
      end

      # c.req.header('X-Custom')
      if line =~ /\w+\.req\.header\s*\(\s*['"]([^'"]+)['"]\s*\)/
        return [Param.new($1, "", "header")]
      end

      # await c.req.json() destructuring: const { name, email } = await c.req.json()
      if line =~ /(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*await\s+\w+\.req\.json\s*\(/
        return $1.split(",").map(&.strip).reject(&.empty?).map { |name| Param.new(name, "", "json") }
      end

      # c.req.parseBody() destructuring
      if line =~ /(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*await\s+\w+\.req\.parseBody\s*\(/
        return $1.split(",").map(&.strip).reject(&.empty?).map { |name| Param.new(name, "", "form") }
      end

      # Cookie: getCookie(c, 'name') from hono/cookie
      if line =~ /getCookie\s*\(\s*\w+\s*,\s*['"]([^'"]+)['"]\s*\)/
        return [Param.new($1, "", "cookie")]
      end

      [] of Param
    end

    HTTP_METHODS = %w[get post put delete patch options head]
    # Compiled once — an interpolated regex literal would otherwise be
    # rebuilt (full PCRE2 compile) for every method on every line.
    ROUTE_CALL_RES = HTTP_METHODS.map { |m| {m, /\b(?:app|router|hono)\s*\.\s*#{m}\s*\(\s*['"]([^'"]+)['"]/} }.to_h

    def line_to_endpoints(line : String) : Array(Endpoint)
      http_methods = HTTP_METHODS

      http_methods.each do |method|
        if line =~ ROUTE_CALL_RES[method]
          path = $1
          return [Endpoint.new(path, method.upcase)]
        end
      end

      # app.all('/path', ...) - registers for all HTTP methods
      if line =~ /\b(?:app|router|hono)\s*\.\s*all\s*\(\s*['"]([^'"]+)['"]/
        path = $1
        return http_methods.map { |m| Endpoint.new(path, m.upcase) }
      end

      # app.on('GET', '/path', ...) - single method string
      if line =~ /\b(?:app|router|hono)\s*\.\s*on\s*\(\s*['"](\w+)['"]\s*,\s*['"]([^'"]+)['"]/
        method = $1.downcase
        path = $2
        if http_methods.includes?(method)
          return [Endpoint.new(path, method.upcase)]
        end
      end

      # app.on(['GET', 'POST'], '/path', ...) - array of methods
      if line =~ /\b(?:app|router|hono)\s*\.\s*on\s*\(\s*\[([^\]]+)\]\s*,\s*['"]([^'"]+)['"]/
        methods_str = $1
        path = $2
        endpoints = [] of Endpoint
        methods_str.scan(/['"](\w+)['"]/) do |m|
          method = m[1].downcase
          if http_methods.includes?(method) && !endpoints.any? { |e| e.method == method.upcase }
            endpoints << Endpoint.new(path, method.upcase)
          end
        end
        return endpoints unless endpoints.empty?
      end

      [] of Endpoint
    end

    private def scan_for_router_mounts
      scanner = RouterMountScanner.new(all_files, @base_paths, base_path, logger)
      scanner.scan
    end
  end
end
