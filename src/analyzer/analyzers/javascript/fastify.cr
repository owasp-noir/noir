require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"
require "../../../utils/url_path"

module Analyzer::Javascript
  class Fastify < JavascriptEngine
    def analyze
      result = [] of Endpoint
      static_dirs = [] of Hash(String, String)
      include_callee = callees_needed?

      # `@fastify/autoload` derives each route file's prefix from its
      # directory path relative to the autoload `dir` — the standard
      # Fastify project layout (`fastify-cli` scaffolds it, the official
      # `fastify/demo` uses it). A route registered as `app.get('/:id')`
      # inside `routes/api/tasks/index.ts` is actually served at
      # `/api/tasks/:id`. Resolve those directory roots once up front so
      # the per-file pass can prepend the convention-derived prefix.
      autoload_roots = collect_autoload_roots

      parallel_file_scan do |path|
        begin
          content = read_file_content(path)
          autoload_prefix = autoload_prefix_for(path, autoload_roots, content)
          parser_endpoints = Noir::JSRouteExtractor.extract_routes(path, content, @is_debug,
            include_callees: include_callee)
          parser_endpoints.each do |endpoint|
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
                  endpoint.push_param(param) if !endpoint.params.any? { |p| p.name == m[1] && p.param_type == "path" }
                end
              end
            end

            result << endpoint
          end

          # Auxiliary pass for `fastify.route({ method, url })` shapes
          # the parser doesn't yet handle (multi-line config objects
          # and the `methods: ['GET','POST']` array form). Skip test
          # stubs (their `.route(` calls aren't registrations) and
          # minified bundles (a multi-MB single line is pure scan cost,
          # never a real config — issue #1903).
          unless Noir::JSRouteExtractor.test_stub_only?(path, content) ||
                 Noir::JSRouteExtractor.minified_content?(content)
            extract_route_configs(path, content, result, include_callee, autoload_prefix)
          end

          collect_static_paths(path, content, static_dirs, :fastify)
        rescue e
          logger.debug "Parser failed for #{path}: #{e.message}, falling back to regex"

          # Fallback to the original regex-based approach if parser fails
          analyze_with_regex(path, result, static_dirs)
        end
      end

      # Process static directories to create endpoints for static files
      process_static_dirs(static_dirs, result)

      result
    end

    # Process static directories and add endpoints for each file
    private def process_static_dirs(static_dirs : Array(Hash(String, String)), result : Array(Endpoint))
      process_js_static_dirs(static_dirs, result)
    end

    # Markers that a file configures `@fastify/autoload`. Both the scoped
    # package and the legacy bare name are matched so older projects work.
    AUTOLOAD_MARKERS = ["@fastify/autoload", "fastify-autoload"]

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
        next unless AUTOLOAD_MARKERS.any? { |m| content.includes?(m) }
        next unless content.includes?("dir")

        base_dir = File.dirname(File.expand_path(path))
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

          root = File.expand_path(File.join([base_dir] + segments))
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
        file_dir = File.dirname(File.expand_path(path))
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

    # Walks a file for `fastify.route({ ... })` registrations that the
    # shared parser misses: the config object may span multiple lines,
    # and `methods` may be an array. For each block, decode the method
    # (or methods) and the url/path and emit one endpoint per method.
    private def extract_route_configs(path : String, content : String, result : Array(Endpoint), include_callee : Bool, autoload_prefix : String = "")
      http_methods = %w[get post put delete patch options head]

      # Match the call site `instance.route(` and walk the balanced
      # parens to capture the whole config object — line-by-line regex
      # would clip multi-line objects.
      content.scan(/\b(?:fastify|app|server)\s*\.\s*route\s*\(/) do |m|
        call_start = m.begin(0)
        next unless call_start

        paren_open = content.index("(", call_start)
        next unless paren_open

        paren_close = Noir::JSRouteExtractor.find_matching_paren(content, paren_open)
        next unless paren_close && paren_close > paren_open

        config = content[(paren_open + 1)...paren_close]
        # Only treat this as an object-literal route() call. Bare
        # references like `route(handler)` aren't config objects and
        # would just produce noise.
        next unless config.lstrip.starts_with?("{")

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

        url = Noir::URLPath.join(autoload_prefix, url) unless autoload_prefix.empty?

        # Compute line number from the call site offset.
        line_no = content[0...call_start].count('\n') + 1

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
          next if result.any? { |e| e.url == url && e.method == method_up }

          endpoint = Endpoint.new(url, method_up)
          endpoint.details = Details.new(PathInfo.new(path, line_no))

          url.scan(/:(\w+)/) do |pm|
            next unless pm.size > 0
            param = Param.new(pm[1], "", "path")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == pm[1] && p.param_type == "path" }
          end

          body_params.each do |bp|
            endpoint.push_param(bp) unless endpoint.params.any? { |p| p.name == bp.name && p.param_type == bp.param_type }
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
      {body, start_line + config[0...open_brace].count('\n')}
    end

    private def skip_whitespace(content : String, pos : Int32) : Int32
      i = pos
      while i < content.size && content[i].whitespace?
        i += 1
      end
      i
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

    private def analyze_with_regex(path : String, result : Array(Endpoint), static_dirs : Array(Hash(String, String)) = [] of Hash(String, String))
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
        endpoint = line_to_endpoint(line)
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

    def extract_path_from_route_handler(line : String) : String
      # Path extraction pattern
      match = line.match(/\(\s*['"]([^'"]+)['"]/)
      match ? match[1] : ""
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

    HTTP_METHODS = %w[get post put delete patch options head]
    # Compiled once — an interpolated regex literal would otherwise be
    # rebuilt (full PCRE2 compile) for every method on every line.
    ROUTE_CALL_RES = HTTP_METHODS.map { |m| {m, /\b(?:fastify|app|server)\s*\.\s*#{m}\s*\(\s*['"]([^'"]+)['"]/} }.to_h

    def line_to_endpoint(line : String) : Endpoint
      http_methods = HTTP_METHODS

      http_methods.each do |method|
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
