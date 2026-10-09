require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"
require "../../../utils/url_path"

module Analyzer::Javascript
  class Fastify < JavascriptEngine
    analyzer_for "js_fastify"

    def analyze
      result = [] of Endpoint
      static_dirs = [] of Hash(String, String)
      include_callee = callees_needed?
      has_query_method = has_query_http_method?

      # `@fastify/autoload` derives each route file's prefix from its
      # directory path relative to the autoload `dir` — the standard
      # Fastify project layout (`fastify-cli` scaffolds it, the official
      # `fastify/demo` uses it). A route registered as `app.get('/:id')`
      # inside `routes/api/tasks/index.ts` is actually served at
      # `/api/tasks/:id`. Resolve those directory roots once up front so
      # the per-file pass can prepend the convention-derived prefix.
      autoload_roots = collect_autoload_roots

      parallel_file_scan do |path|
        content = read_file_content(path)
        next if Noir::JSRouteExtractor.other_shared_extractor_framework?(content, :fastify)
        autoload_prefix = autoload_prefix_for(path, autoload_roots, content)
        parser_endpoints = Noir::JSRouteExtractor.extract_routes(path, content, @is_debug,
          include_callees: include_callee)
        # "METHOD url" this file already emitted, for the auxiliary passes'
        # de-duplication (a Set: scanning the whole result per route was
        # quadratic).
        recorded = Set(String).new
        parser_endpoints.each do |endpoint|
          # The shared JS parser emits `.query(` shorthand for any receiver
          # and without the addHttpMethod('QUERY') gate or plugin prefixes.
          # The Fastify-specific pass below owns all QUERY emission (gated
          # shorthand plus explicit route configs), so shared-parser QUERY
          # results would only add phantom or unprefixed duplicates.
          next if endpoint.method == "QUERY"

          unless autoload_prefix.empty?
            endpoint.url = Noir::URLPath.join(autoload_prefix, endpoint.url)
          end
          # Preserve the precise route line supplied by the shared extractor.
          # Falling back to path-only keeps older behavior if a parser result
          # somehow lacks location metadata.
          if endpoint.details.code_paths.empty?
            endpoint.details = Details.new(PathInfo.new(path))
          end

          # Parse path parameters from the URL path itself
          if endpoint.url.includes?(":")
            endpoint.url.scan(/:(\w+)/) do |m|
              if m.size > 0
                param = Param.new(m[1], "", "path")
                endpoint.push_param(param)
              end
            end
          end

          result << endpoint
          recorded << "#{endpoint.method} #{endpoint.url}"
        end

        # Auxiliary pass for `fastify.route({ method, url })` shapes
        # the parser doesn't yet handle (multi-line config objects
        # and the `methods: ['GET','POST']` array form). Skip test
        # stubs (their `.route(` calls aren't registrations) and
        # minified bundles (a multi-MB single line is pure scan cost,
        # never a real config — issue #1903).
        unless Noir::JSRouteExtractor.test_stub_only?(path, content) ||
               Noir::JSRouteExtractor.minified_content?(content)
          extract_route_configs(path, content, result, recorded, include_callee, autoload_prefix)
          if has_query_method
            extract_query_shorthand_routes(path, content, result, recorded, include_callee, autoload_prefix)
          end
        end

        collect_static_paths(path, content, static_dirs, :fastify)
      rescue e
        logger.debug "Parser failed for #{path}: #{e.message}, falling back to regex"

        # Fallback to the original regex-based approach if parser fails
        analyze_with_regex(path, result, static_dirs, has_query_method)
      end

      # Process static directories to create endpoints for static files
      process_js_static_dirs(static_dirs, result)

      result
    end

    # Markers that a file configures `@fastify/autoload`. Both the scoped
    # package and the legacy bare name are matched so older projects work.
    # Precompiled once — a single PCRE2-JIT scan replaces two naive
    # String#includes? substring scans. Regex.union auto-escapes each
    # literal, so it is provably equivalent to the OR-of-includes? it
    # replaces.
    AUTOLOAD_MARKERS_RE = Regex.union("@fastify/autoload", "fastify-autoload")

    # A directory `@fastify/autoload` registers. `dir_prefix` records the
    # config's `dirNameRoutePrefix` — when it is `false`, subdirectories
    # do NOT contribute a route prefix (a file's own `autoPrefix` export
    # provides the prefix instead).
    record AutoloadRoot, path : String, dir_prefix : Bool

    # `export const autoPrefix = '/x'` (or CJS `module.exports.autoPrefix
    # = '/x'`) lets a route file declare its own autoload prefix. The
    # `\bautoPrefix\s*=\s*<string>` shape matches the assignment but not a
    # read like `reply.redirect(autoPrefix)`.
    AUTO_PREFIX_RE = /\bautoPrefix\s*=\s*['"]([^'"]+)['"]/

    # Discover the directory roots that `@fastify/autoload` registers.
    # Each `register(autoload, { dir: <expr>, dirNameRoutePrefix?: bool })`
    # names a tree whose subdirectories become route prefixes (unless
    # `dirNameRoutePrefix: false`). `dir` is conventionally
    # `path.join(import.meta.dirname, 'routes')` / `join(__dirname, 'a',
    # 'b')`, so the directory is the config file's own directory plus the
    # string-literal segments of the `dir` expression. Returns the longest
    # roots first so `autoload_prefix_for` can match the most specific.
    private def collect_autoload_roots : Array(AutoloadRoot)
      roots = [] of AutoloadRoot
      all_files.each do |path|
        next unless ExpressConstants::JS_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
        content = read_file_content(path)
        next unless content.matches?(AUTOLOAD_MARKERS_RE)
        next unless content.includes?("dir")

        base_dir = File.dirname(Noir::PathScope.expand(path))
        # Scan each `register(...)` call's argument list as a unit so the
        # `dirNameRoutePrefix` flag is associated with the right `dir:`
        # (a file may register several autoload trees).
        content.scan(/\bregister\s*\(/) do |m|
          paren_open = content.index("(", m.begin(0) || 0)
          next unless paren_open
          paren_close = Noir::JSRouteExtractor.find_matching_paren(content, paren_open)
          next unless paren_close && paren_close > paren_open
          args = content[(paren_open + 1)...paren_close]

          dir_match = args.match(/\bdir\s*:\s*/)
          next unless dir_match
          value_start = dir_match.end(0) || 0
          value_end = route_config_value_end(args, value_start)
          value = args[value_start...value_end]
          segments = [] of String
          value.scan(/['"]([^'"]+)['"]/) { |sm| segments << sm[1] }
          next if segments.empty?

          root = Noir::PathScope.expand(File.join([base_dir] + segments))
          dir_prefix = !args.matches?(/dirNameRoutePrefix\s*:\s*false/)
          roots << AutoloadRoot.new(root, dir_prefix) unless roots.any? { |r| r.path == root }
        end
      rescue
        next
      end
      roots.sort_by! { |r| -r.path.size }
      roots
    end

    # Compute the autoload-derived prefix for a file. Two contributions
    # compose (directory first, then the file's own `autoPrefix`):
    #   * the file's directory path relative to the most specific autoload
    #     root that contains it (skipped when that root set
    #     `dirNameRoutePrefix: false`). `@fastify/autoload` ignores the
    #     filename — an `index.ts` and a sibling `tasks.ts` in `routes/api/`
    #     both mount at `/api`.
    #   * an `export const autoPrefix = '/x'` declared in the file.
    # A file directly in a root with no autoPrefix yields "" (mounted at
    # "/"), which leaves its routes untouched.
    private def autoload_prefix_for(path : String, roots : Array(AutoloadRoot), content : String) : String
      auto_prefix = content.includes?("autoPrefix") && (m = content.match(AUTO_PREFIX_RE)) ? m[1] : ""

      dir_prefix = ""
      unless roots.empty?
        file_dir = File.dirname(Noir::PathScope.expand(path))
        roots.each do |root|
          next unless file_dir == root.path || file_dir.starts_with?("#{root.path}/")
          if root.dir_prefix && file_dir != root.path
            dir_prefix = "/#{file_dir[(root.path.size + 1)..]}"
          end
          break
        end
      end

      return dir_prefix if auto_prefix.empty?
      return auto_prefix if dir_prefix.empty?
      Noir::URLPath.join(dir_prefix, auto_prefix)
    end

    # Markers indicating that HTTP QUERY method support is registered.
    QUERY_METHOD_MARKERS_RE = Regex.union(
      /\baddHttpMethod\s*\(\s*['"]QUERY['"]/i,
      /fastify-http-query/
    )

    private def has_query_http_method? : Bool
      all_files.any? do |path|
        next false unless ExpressConstants::JS_EXTENSIONS.any? { |ext| path.ends_with?(ext) } || path.ends_with?("package.json")
        content = read_file_content(path)
        content.matches?(QUERY_METHOD_MARKERS_RE)
      end
    end

    # Body ranges of prefixed plugins, as {open_brace, close_brace, prefix}
    # BYTE offsets, in the order `plugin_prefix_at` consults them. Built
    # once per file: re-scanning the whole file for every route made a large
    # route file quadratic.
    private def plugin_ranges(content : String) : Array(Tuple(Int32, Int32, String))
      ranges = [] of Tuple(Int32, Int32, String)

      # 1. Anonymous plugin functions:
      #    fastify.register(function (instance) { ... }, { prefix: '/x' })
      #    fastify.register((instance) => { ... }, { prefix: '/x' })
      content.scan(/\b\w+\.register\s*\(\s*(?:async\s+)?(?:function\s*\([^)]*\)|\([^)]*\)\s*=>|\w+\s*=>)\s*\{/) do |m|
        open_brace = content.byte_index('{', m.byte_begin(0))
        next unless open_brace
        close_brace = Noir::JSLiteralScanner.find_matching_brace_at_byte(content, open_brace)
        next unless close_brace

        if prefix_match = content.byte_slice(close_brace).match(/^[^)]*prefix\s*:\s*['"]([^'"]+)['"]/)
          ranges << {open_brace, close_brace, prefix_match[1]}
        end
      end

      # 2. Named plugin functions:
      #    const myRoutes = async (fastify) => { ... }; fastify.register(myRoutes, { prefix: '/x' })
      content.scan(/\b\w+\.register\s*\(\s*(\w+)\s*,\s*\{[^}]*prefix\s*:\s*['"]([^'"]+)['"]/) do |m|
        next unless m.size >= 3
        fn_name = m[1]
        prefix = m[2]

        pattern = /(?:const|let|var)\s+#{Regex.escape(fn_name)}\s*=\s*(?:async\s*)?(?:\([^)]*\)|\w+)\s*=>\s*\{|(?:function\s+#{Regex.escape(fn_name)}\s*\([^)]*\)|(?:const|let|var)\s+#{Regex.escape(fn_name)}\s*=\s*(?:async\s+)?function\b[^{]*)\s*\{/
        if (fn_match = content.match(pattern)) &&
           (open_brace = content.byte_index('{', fn_match.byte_begin(0))) &&
           (close_brace = Noir::JSLiteralScanner.find_matching_brace_at_byte(content, open_brace))
          ranges << {open_brace, close_brace, prefix}
        end
      end

      ranges
    end

    private def plugin_prefix_at(ranges : Array(Tuple(Int32, Int32, String)), offset : Int32) : String
      ranges.find { |open_brace, close_brace, _| offset >= open_brace && offset <= close_brace }.try(&.[2]) || ""
    end

    # `<instance>.route({` / `<instance>.query('/…'` on any receiver: a
    # plugin's instance is whatever its function names it (`api`, `f`,
    # `child`). The argument shape is the gate, and it is in the pattern so
    # the per-call work below never runs for `db.query(sql)` or Express's
    # `router.route('/x')`.
    ROUTE_CONFIG_CALL_RE = /(?<![\w$])([A-Za-z_$][\w$]*)\s*\.\s*route\s*\(\s*\{/
    # A `handler` key: `handler: fn`, `handler(req) {…}` or shorthand `{ handler }`.
    # A `handler` (or `wsHandler`) key (`handler: fn`, `handler(req) {…}`, shorthand
    # `{ handler }`) or a spread that may carry one (`...routeOpts`).
    ROUTE_CONFIG_HANDLER_KEY = /(?<![\w$.])(?:handler|wsHandler)\s*(?:[:(,}]|$)|\.\.\./m
    QUERY_CALL_RE            = /(?<![\w$])([A-Za-z_$][\w$]*)\s*\.\s*query\s*\(\s*[`'"][\/*]/

    # `.query(` is every database and search client's method, so unlike
    # `route({ …, handler })` the call shape cannot vouch for the receiver.
    # It has to be a Fastify instance: conventionally named, or the first
    # parameter of a plugin function (inline in `register(…)`, a function
    # handed to `register(name, …)`, or a module's default export).
    FASTIFY_INSTANCE_NAME  = /\A(?:fastify|app|server|instance)\z|(?:App|Server)\z/
    INLINE_PLUGIN_PARAM    = /\.register\s*\(\s*(?:async\s+)?(?:function\s*[\w$]*\s*\(\s*([A-Za-z_$][\w$]*)|\(\s*([A-Za-z_$][\w$]*)|([A-Za-z_$][\w$]*)\s*=>)/
    REGISTERED_PLUGIN_NAME = /\.register\s*\(\s*([A-Za-z_$][\w$]*)\s*[,)]/
    # `module.exports = routes` / `export default fp(routes)`: registered elsewhere.
    EXPORTED_PLUGIN_NAME = /(?:export\s+default|module\.exports\s*=)\s*(?:[\w$.]+\s*\(\s*)?([A-Za-z_$][\w$]*)\s*[;)\n]/
    FUNCTION_FIRST_PARAM = /function\s+([A-Za-z_$][\w$]*)\s*\(\s*([A-Za-z_$][\w$]*)|(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?(?:function\s*[\w$]*\s*\(\s*([A-Za-z_$][\w$]*)|\(\s*([A-Za-z_$][\w$]*)|([A-Za-z_$][\w$]*)\s*=>)/
    # Optionally wrapped: `module.exports = fp(async function (f) {…})`.
    EXPORTED_PLUGIN_PARAM = /(?:export\s+default|module\.exports\s*=)\s*(?:[\w$.]+\s*\(\s*)?(?:async\s+)?(?:function\s*[\w$]*\s*\(\s*([A-Za-z_$][\w$]*)|\(\s*([A-Za-z_$][\w$]*)|([A-Za-z_$][\w$]*)\s*=>)/

    private def fastify_instance_names(content : String) : Set(String)
      names = Set(String).new
      {INLINE_PLUGIN_PARAM, EXPORTED_PLUGIN_PARAM}.each do |re|
        content.scan(re) { |m| (m[1]? || m[2]? || m[3]?).try { |n| names << n } }
      end
      registered = Set(String).new
      content.scan(REGISTERED_PLUGIN_NAME) { |m| registered << m[1] }
      content.scan(EXPORTED_PLUGIN_NAME) { |m| registered << m[1] }
      return names if registered.empty?

      # One pass over the file's function declarations, not a regex per
      # registered name.
      content.scan(FUNCTION_FIRST_PARAM) do |m|
        next unless registered.includes?(m[1]? || m[3]? || "")
        (m[2]? || m[4]? || m[5]? || m[6]?).try { |n| names << n }
      end
      names
    end

    # Scans for `fastify.query('/url', ...)` route shorthand calls.
    # Fastify only provides this method when registered via
    # `fastify.addHttpMethod('QUERY')` or the `fastify-http-query` plugin.
    private def extract_query_shorthand_routes(path : String, content : String, result : Array(Endpoint), recorded : Set(String), include_callee : Bool, autoload_prefix : String = "")
      ranges = nil
      offsets = nil
      instances = nil
      content.scan(QUERY_CALL_RE) do |m|
        receiver = m[1]
        unless receiver.matches?(FASTIFY_INSTANCE_NAME)
          next unless (instances ||= fastify_instance_names(content)).includes?(receiver)
        end
        # Byte offsets throughout: a char offset costs O(offset) per call.
        call_start = m.byte_begin(0)

        paren_open = content.byte_index('(', call_start)
        next unless paren_open

        paren_close = Noir::JSLiteralScanner.find_matching_paren_at_byte(content, paren_open)
        next unless paren_close && paren_close > paren_open

        args = content.byte_slice(paren_open + 1, paren_close - paren_open - 1)
        first_arg = args.lstrip

        # Match string or template literal URL
        url_match = first_arg.match(/^[`'"]([^`'"]+)[`'"]/)
        next unless url_match

        raw_url = url_match[1]
        # Fastify paths start with `/` (or are `*`); anything else is a
        # client or database call such as `db.query('users', cb)`.
        next unless raw_url.starts_with?('/') || raw_url == "*"
        next if raw_url.includes?(" ")
        # A route takes a handler after the path; `helper.query('/x')` is a
        # plain call.
        next unless first_arg[url_match.end(0)..].lstrip.starts_with?(',')

        prefix_ranges = (ranges ||= plugin_ranges(content))
        plugin_prefix = plugin_prefix_at(prefix_ranges, call_start)
        url = plugin_prefix.empty? ? raw_url : Noir::URLPath.join(plugin_prefix, raw_url)
        url = Noir::URLPath.join(autoload_prefix, url) unless autoload_prefix.empty?

        next unless recorded.add?("QUERY #{url}")

        line_no = (offsets ||= Noir::JSRouteExtractor::ByteOffsets.new(content)).line(call_start)

        endpoint = Endpoint.new(url, "QUERY")
        endpoint.details = Details.new(PathInfo.new(path, line_no))

        # Extract path parameters from URL
        url.scan(/:(\w+)/) do |pm|
          next unless pm.size > 0
          param = Param.new(pm[1], "", "path")
          endpoint.push_param(param)
        end

        # Extract handler params
        args.each_line do |handler_line|
          p = line_to_param(handler_line)
          endpoint.push_param(p) if !p.name.empty?
        end

        if include_callee
          route_callees = Noir::JSCalleeExtractor.callees_for_function_body(args, path, line_no, language: javascript_source_language(path))
          attach_js_callees(endpoint, route_callees)
        end

        result << endpoint
      end
    end

    # Walks a file for `fastify.route({ ... })` registrations that the
    # shared parser misses: the config object may span multiple lines,
    # and `methods` may be an array. For each block, decode the method
    # (or methods) and the url/path and emit one endpoint per method.
    private def extract_route_configs(path : String, content : String, result : Array(Endpoint), recorded : Set(String), include_callee : Bool, autoload_prefix : String = "")
      http_methods = HTTP_METHODS

      # Match the call site `instance.route(` and walk the balanced
      # parens to capture the whole config object — line-by-line regex
      # would clip multi-line objects.
      ranges = nil
      offsets = nil
      content.scan(ROUTE_CONFIG_CALL_RE) do |m|
        # Byte offsets throughout: a char offset costs O(offset) per call.
        call_start = m.byte_begin(0)

        paren_open = content.byte_index('(', call_start)
        next unless paren_open

        paren_close = Noir::JSLiteralScanner.find_matching_paren_at_byte(content, paren_open)
        next unless paren_close && paren_close > paren_open

        config = content.byte_slice(paren_open + 1, paren_close - paren_open - 1)
        # Only treat this as an object-literal route() call. Bare
        # references like `route(handler)` aren't config objects and
        # would just produce noise.
        next unless config.lstrip.starts_with?("{")
        # Fastify requires a handler; `nock.route({ method, url, reply })` or
        # Cypress's `cy.route({ method, url, response })` has none.
        # Off a conventionally named instance any config counts, as before
        # (`{ websocket: true, wsHandler }` has no `handler`).
        next unless m[1].matches?(FASTIFY_INSTANCE_NAME) || config.matches?(ROUTE_CONFIG_HANDLER_KEY)

        methods = [] of String
        url = ""

        # Single-method form: `method: 'GET'`
        if mm = config.match(/method\s*:\s*['"](\w+)['"]/)
          method = mm[1].downcase
          methods << method if http_methods.includes?(method)
        end

        # Array form: `method: ['GET', 'POST']` or `methods: [...]`.
        # Fastify accepts both keys depending on version, so cover both.
        if am = config.match(/methods?\s*:\s*\[([^\]]+)\]/)
          am[1].scan(/['"](\w+)['"]/) do |entry|
            method = entry[1].downcase
            methods << method if http_methods.includes?(method) && !methods.includes?(method)
          end
        end

        if um = config.match(/(?:url|path)\s*:\s*['"]([^'"]+)['"]/)
          url = um[1]
        end

        next if methods.empty? || url.empty?

        prefix_ranges = (ranges ||= plugin_ranges(content))
        plugin_prefix = plugin_prefix_at(prefix_ranges, call_start)
        url = plugin_prefix.empty? ? url : Noir::URLPath.join(plugin_prefix, url)
        url = Noir::URLPath.join(autoload_prefix, url) unless autoload_prefix.empty?

        # Compute line number from the call site offset.
        line_no = (offsets ||= Noir::JSRouteExtractor::ByteOffsets.new(content)).line(call_start)

        # Pre-scan the config body for handler params (request.body.x,
        # request.query.x, ...). The shorthand `.get(url, handler)`
        # path uses the same `line_to_param` helper, so reusing it
        # here keeps param coverage at parity.
        body_params = [] of Param
        config.each_line do |handler_line|
          p = line_to_param(handler_line)
          body_params << p if !p.name.empty? && !body_params.any? { |bp| bp.name == p.name && bp.param_type == p.param_type }
        end
        route_callees = include_callee ? route_config_callees(config, path, line_no) : [] of Noir::JSCalleeExtractor::Entry

        methods.each do |http_method|
          method_up = http_method.upcase
          next unless recorded.add?("#{method_up} #{url}")

          endpoint = Endpoint.new(url, method_up)
          endpoint.details = Details.new(PathInfo.new(path, line_no))

          url.scan(/:(\w+)/) do |pm|
            next unless pm.size > 0
            param = Param.new(pm[1], "", "path")
            endpoint.push_param(param)
          end

          body_params.each do |bp|
            endpoint.push_param(bp)
          end
          attach_js_callees(endpoint, route_callees)

          result << endpoint
        end
      end
    end

    private def route_config_callees(config : String, path : String, start_line : Int32) : Array(Noir::JSCalleeExtractor::Entry)
      if handler = route_config_handler_body(config, start_line)
        body, body_line = handler
        Noir::JSCalleeExtractor.callees_for_function_body(body, path, body_line, language: javascript_source_language(path))
      else
        [] of Noir::JSCalleeExtractor::Entry
      end
    end

    private def route_config_handler_body(config : String, start_line : Int32) : Tuple(String, Int32)?
      if match = config.match(/(?:^|[,{]\s*)handler\s*:/m)
        value_start = skip_whitespace(config, match.end(0) || 0)
        arrow_idx = config.index("=>", value_start)
        function_idx = config.index(/\bfunction\b/, value_start)

        if function_idx && (!arrow_idx || function_idx < arrow_idx)
          if open_brace = config.index("{", function_idx)
            return block_body(config, open_brace, start_line)
          end
        elsif arrow_idx
          body_start = skip_whitespace(config, arrow_idx + 2)
          if config[body_start]? == '{'
            return block_body(config, body_start, start_line)
          end

          body_end = route_config_value_end(config, body_start)
          body = config[body_start...body_end].strip
          return {body, start_line + config[0...body_start].count('\n')} unless body.empty?
        end
      end

      if match = config.match(/(?:^|[,{]\s*)handler\s*\(/m)
        open_paren = config.index("(", match.begin(0) || 0)
        return unless open_paren

        close_paren = Noir::JSRouteExtractor.find_matching_paren(config, open_paren)
        return unless close_paren

        open_brace = skip_whitespace(config, close_paren + 1)
        return unless config[open_brace]? == '{'

        block_body(config, open_brace, start_line)
      end
    end

    private def block_body(config : String, open_brace : Int32, start_line : Int32) : Tuple(String, Int32)?
      close_brace = Noir::JSRouteExtractor.find_matching_brace(config, open_brace)
      return unless close_brace

      body = config[(open_brace + 1)...close_brace]
      # `open_brace` is a CHAR index; convert for an allocation-free,
      # non-ASCII-correct newline count over the byte prefix.
      open_brace_byte = if config.bytesize == config.size
                          open_brace
                        else
                          config.char_index_to_byte_index(open_brace) || config.bytesize
                        end
      {body, start_line + config.to_slice[0, open_brace_byte].count('\n'.ord.to_u8)}
    end

    private def route_config_value_end(config : String, start : Int32) : Int32
      depth = 0
      quote : Char? = nil
      escaped = false
      i = start

      while i < config.size
        char = config[i]

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
        when ')', ']'
          depth -= 1 if depth > 0
        when '}'
          return i if depth == 0
          depth -= 1
        when ','
          return i if depth == 0
        end

        i += 1
      end

      i
    end

    # Helper method to create an endpoint with details
    private def create_endpoint(path : String, url : String, method : String, params : Array(Param)) : Endpoint
      endpoint = Endpoint.new(url, method)
      endpoint.details = Details.new(PathInfo.new(path, 1))
      params.each do |param|
        endpoint.push_param(param)
      end
      endpoint
    end

    private def analyze_with_regex(path : String, result : Array(Endpoint), static_dirs : Array(Hash(String, String)) = [] of Hash(String, String), has_query : Bool = true)
      # Original regex-based analysis as a fallback
      last_endpoint = Endpoint.new("", "")
      # current_router_base = ""
      fastify_instances = [] of String
      route_plugin_prefixes = {} of String => String
      plugin_functions = {} of String => Bool
      file_content = read_file_content(path)

      collect_static_paths(path, file_content, static_dirs, :fastify)

      # First scan for fastify instances and plugin registrations
      file_content.each_line do |line|
        # Detect Fastify initialization
        if line =~ /(?:const|let|var)\s+(\w+)\s*=\s*(?:require\s*\(\s*['"]fastify['"]\s*\)|\s*fastify\()/
          fastify_instances << $1
        end

        # Detect plugin function declarations
        if line =~ /(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s*)?\(\s*(?:fastify|app|server)\s*,\s*options\s*\)\s*=>/
          plugin_functions[$1] = true
        end

        # Also detect traditional function syntax for plugins
        if line =~ /(?:function\s+(\w+)\s*\(\s*(?:fastify|app|server)(?:\s*,\s*options)?\s*\)|(?:const|let|var)\s+(\w+)\s*=\s*function\s*\(\s*(?:fastify|app|server)(?:\s*,\s*options)?\s*\))/
          plugin_name = $1 || $2
          plugin_functions[plugin_name] = true unless plugin_name.empty?
        end

        # Detect plugin registration with prefix - more flexible pattern matching
        if line =~ /(\w+)\.register\s*\(\s*(\w+)(?:[^{]*|\s*,\s*)\{[^}]*prefix\s*:\s*['"]([^'"]+)['"]/
          # fastify_var = $1
          plugin_var = $2
          prefix = $3
          if plugin_functions.has_key?(plugin_var) || plugin_var.includes?("Routes")
            route_plugin_prefixes[plugin_var] = prefix
          end
        end
      end

      # Now process the file line by line for endpoints
      current_plugin_var = ""
      inside_plugin_function = false
      plugin_indent_level = 0
      plugin_prefix = ""

      file_content.each_line.with_index do |line, index|
        # Detect plugin function definitions
        if !inside_plugin_function && line =~ /(?:const|let|var)\s+(\w+Routes|\w+)\s*=\s*(?:async\s*)?\(\s*(?:fastify|app|server)\s*,\s*options\s*\)\s*=>/
          function_name = $1
          current_plugin_var = function_name
          inside_plugin_function = true
          plugin_indent_level = line.index("{") || 0
          plugin_prefix = route_plugin_prefixes.fetch(current_plugin_var, "")
        end

        # Check if we're exiting a plugin function
        if inside_plugin_function && line =~ /^\s*\}\s*;?\s*$/
          # Check if the indentation level matches with the function start
          if line.strip == "}" || line.strip == "};"
            current_indent = line.index("}") || 0
            if current_indent <= plugin_indent_level
              inside_plugin_function = false
              current_plugin_var = ""
              plugin_prefix = ""
            end
          end
        end

        # Detect regular routes or routes within plugins
        endpoint = line_to_endpoint(line, has_query)
        unless endpoint.method.empty?
          # Apply plugin prefix if inside a plugin function
          if inside_plugin_function && !plugin_prefix.empty?
            # Handle path joining properly
            if endpoint.url.starts_with?("/") && plugin_prefix.ends_with?("/")
              endpoint.url = "#{plugin_prefix[0..-2]}#{endpoint.url}"
            elsif !endpoint.url.starts_with?("/") && !plugin_prefix.ends_with?("/")
              endpoint.url = "#{plugin_prefix}/#{endpoint.url}"
            else
              endpoint.url = "#{plugin_prefix}#{endpoint.url}"
            end
          end

          details = Details.new(PathInfo.new(path, index + 1))
          endpoint.details = details
          result << endpoint
          last_endpoint = endpoint
        end

        # Get parameters from line
        param = line_to_param(line)
        if !param.name.empty? && !last_endpoint.method.empty?
          last_endpoint.push_param(param)
        end
      end
    end

    def line_to_param(line : String) : Param
      # Extract params from request object
      if line.includes?("request.body.") || line.includes?("req.body.")
        param_match = line.match(/(?:request|req)\.body\.(\w+)/)
        param = param_match ? param_match[1] : ""
        return Param.new(param, "", "json") if !param.empty?
      end

      if line.includes?("request.query.") || line.includes?("req.query.")
        param_match = line.match(/(?:request|req)\.query\.(\w+)/)
        param = param_match ? param_match[1] : ""
        return Param.new(param, "", "query") if !param.empty?
      end

      if line.includes?("request.cookies.") || line.includes?("req.cookies.")
        param_match = line.match(/(?:request|req)\.cookies\.(\w+)/)
        param = param_match ? param_match[1] : ""
        return Param.new(param, "", "cookie") if !param.empty?
      end

      # Headers
      if line =~ /(?:request|req)\.headers\s*\[\s*['"]([^'"]+)['"]\s*\]/
        return Param.new($1, "", "header")
      end

      if line =~ /(?:request|req)\.header\s*\(\s*['"]([^'"]+)['"]/
        return Param.new($1, "", "header")
      end

      # Path parameters
      if line =~ /(?:request|req)\.params\.(\w+)/
        return Param.new($1, "", "path")
      end

      # Handle destructuring syntax
      if line =~ /(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*(?:request|req)\.body/
        param_list = $1.split(",").map(&.strip)
        if !param_list.empty?
          # Return the first param, since we can only return one
          return Param.new(param_list.first, "", "json")
        end
      end

      Param.new("", "", "")
    end

    HTTP_METHODS = %w[get post put delete patch options head query]
    # Compiled once — an interpolated regex literal would otherwise be
    # rebuilt (full PCRE2 compile) for every method on every line.
    ROUTE_CALL_RES = HTTP_METHODS.map { |m| {m, /\b(?:fastify|app|server)\s*\.\s*#{m}\s*\(\s*['"]([^'"]+)['"]/} }.to_h

    def line_to_endpoint(line : String, has_query : Bool = true) : Endpoint
      http_methods = HTTP_METHODS

      http_methods.each do |method|
        next if method == "query" && !has_query
        # Match fastify.method patterns
        if line =~ ROUTE_CALL_RES[method]
          path = $1
          return Endpoint.new(path, method.upcase)
        end
      end

      # Handle route method with method as a parameter
      if line =~ /\b(?:fastify|app|server)\s*\.\s*route\s*\(\s*\{/ &&
         (line.includes?("method:") || line.includes?("url:") || line.includes?("path:"))
        # Extract method and path from route configuration object
        method_match = line.match(/method\s*:\s*['"](\w+)['"]/)
        path_match = line.match(/(?:url|path)\s*:\s*['"]([^'"]+)['"]/)

        if method_match && path_match
          method = method_match[1].downcase
          path = path_match[1]
          if http_methods.includes?(method)
            return Endpoint.new(path, method.upcase)
          end
        end
      end

      Endpoint.new("", "")
    end
  end
end
