require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"
require "../../../utils/top_level_split"
require "./express/router_mount_scanner"

module Analyzer::Javascript
  class Hono < JavascriptEngine
    analyzer_for "js_hono"

    ON_ROUTE_CALL_PATTERN = /\.(?:\s|\n|\r)*on(?:\s|\n|\r)*\(/

    def analyze
      result = [] of Endpoint
      static_dirs = [] of Hash(String, String)

      scan_for_router_mounts
      # HonoX mounts a route module's `new Hono()` app at the module's file
      # path (js_honox); read here, its routes would lose that prefix.
      honox = js_package_owners(["\"honox\""])

      parallel_file_scan do |path|
        next if base_relative_path(path).includes?("/app/routes/") && owned_by_js_package?(path, honox)
        # Blanked once here: the `app.on()` pass and `line_to_params` read
        # the text with their own regexes. Lines and columns are kept.
        content = Noir::JSRouteExtractor.strip_js_comments(read_file_content(path))
        next if Noir::JSRouteExtractor.other_shared_extractor_framework?(content, :hono)
        include_callee = callees_needed?
        callees_by_route = include_callee ? Noir::JSCalleeExtractor.callees_for_routes(content, path) : {} of String => Array(Noir::JSCalleeExtractor::Entry)
        parser_endpoints = Noir::JSRouteExtractor.extract_routes(path, content, @is_debug,
          include_callees: include_callee, route_callees: callees_by_route)
        # "METHOD url" this file already emitted, for the app.on() pass's
        # de-duplication (a Set: scanning the whole result per route was
        # quadratic).
        recorded = Set(String).new
        parser_endpoints.each do |endpoint|
          extract_path_params(endpoint)
          result << endpoint
          recorded << "#{endpoint.method} #{endpoint.url}"
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
          extract_on_routes(path, content, result, recorded, callees_by_route, include_callee)
        end

        collect_static_paths(path, content, static_dirs, :hono)
      rescue e
        logger.debug "Parser failed for #{path}: #{e.message}, falling back to regex"
        analyze_with_regex(path, result)
      end

      process_js_static_dirs(static_dirs, result)

      result
    end

    private def on_route_candidate?(content : String) : Bool
      # `ON_ROUTE_CALL_PATTERN` already matches both ".on(" and ".on ("
      # (its `(?:\s|\n|\r)*` groups allow zero-or-more whitespace around
      # "on"), so the two former String#includes? checks ahead of it were
      # a strictly redundant pre-filter — and per this project's own
      # benchmarking, Crystal's naive includes? scan is slower than a
      # PCRE2-JIT matches? call, so the "pre-gate" was a pure regression.
      content.matches?(ON_ROUTE_CALL_PATTERN)
    end

    # `<receiver>.on('GET', '/path', …)` (method in group 2) or
    # `.on(['GET', 'POST'], '/path', …)` (group 3); the path is group 4. Any
    # receiver (`books`, `api`, …) with a `/` or `*` path — an event name is
    # neither — except the usual event-emitter names, whose `.on('get',
    # '/room/1', cb)` has the same shape.
    ON_ROUTE_RE            = /(?<![\w$])([A-Za-z_$][\w$]*)\s*\.\s*on\s*\(\s*(?:['"](\w+)['"]|\[([^\]\n]+)\])\s*,\s*['"]([\/*][^'"\n]*)['"]/
    EVENT_EMITTER_RECEIVER = /\A(?:ee|io|ws|process|events?|\w*(?:[Ee]mitter|[Ss]ocket|[Ss]tream))\z/

    private def extract_on_routes(path : String,
                                  content : String,
                                  result : Array(Endpoint),
                                  recorded : Set(String),
                                  callees_by_route : Hash(String, Array(Noir::JSCalleeExtractor::Entry)),
                                  include_callee : Bool)
      bytes = content.to_slice
      # Matches arrive in order, so the line is counted incrementally from
      # the match's own byte offset. Summing `line.bytesize + 1` over
      # `content.lines` (terminators stripped) drifted one byte per CRLF
      # line and mixed bytes with the char offsets callees are found by.
      line_byte = 0
      index = 0
      content.scan(ON_ROUTE_RE) do |match|
        methods = [] of String
        next if match[1].matches?(EVENT_EMITTER_RECEIVER)
        if single = match[2]?
          method = single.downcase
          methods << method if HTTP_METHODS.includes?(method)
        elsif list = match[3]?
          list.scan(/['"](\w+)['"]/) do |m|
            method = m[1].downcase
            methods << method if HTTP_METHODS.includes?(method) && !methods.includes?(method)
          end
        end
        url = match[4]
        next if methods.empty? || url.empty?

        match_byte = match.byte_begin(0)
        index += bytes[line_byte, match_byte - line_byte].count('\n'.ord.to_u8)
        line_byte = match_byte

        # Handler params, read once for every method variant from the
        # call's own arguments. Walking the following lines up to a `})`
        # line skipped a one-line handler and read the next route's instead.
        body_params = [] of Param
        direct_callees = [] of Noir::JSCalleeExtractor::Entry
        if (open = content.byte_index('(', match_byte)) &&
           (close = Noir::JSLiteralScanner.find_matching_paren_at_byte(content, open))
          args_src = content.byte_slice(open + 1, close - open - 1)
          args_src.each_line do |handler_line|
            body_params.concat(line_to_params(handler_line))
          end
          if include_callee
            args_line = index + 1 + bytes[match_byte, open - match_byte].count('\n'.ord.to_u8)
            direct_callees = on_route_callees(args_src, path, args_line)
          end
        end

        methods.each do |http_method|
          next unless recorded.add?("#{http_method.upcase} #{url}")

          endpoint = Endpoint.new(url, http_method.upcase)
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint.details = details
          Noir::JSRouteExtractor.attach_callees(endpoint, callees_by_route, http_method.upcase, url, index + 1)
          attach_js_callees(endpoint, direct_callees)

          body_params.each { |param| endpoint.push_param(param) }
          extract_path_params(endpoint)

          result << endpoint
        end
      end
    end

    # Callees of an `on()` handler (the call's third argument), read from the
    # call's own argument text so the cost stays local to the call — the
    # file-wide char-offset walk was quadratic in the route count. Lines are
    # shifted from the slice back to the file; `args_line` is the line the
    # arguments start on.
    private def on_route_callees(args_src : String, path : String, args_line : Int32) : Array(Noir::JSCalleeExtractor::Entry)
      args = split_top_level_args(args_src, 0, args_src.size)
      return [] of Noir::JSCalleeExtractor::Entry if args.size < 3

      handler_source, handler_start = args[2]
      handler_callees(handler_source, handler_start, args_src, path).map do |name, file, line|
        {name, file, line + args_line - 1}
      end
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
            endpoint.push_param(param)
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

    HTTP_METHODS = %w[get post put delete patch options head query]
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
        return %w[get post put delete patch options head].map { |m| Endpoint.new(path, m.upcase) }
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
      scanner = RouterMountScanner.new(all_files, @base_paths, base_path, logger, :hono)
      scanner.scan
    end
  end
end
