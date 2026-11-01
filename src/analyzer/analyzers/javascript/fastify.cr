require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"
require "../../../utils/url_path"
require "./express/router_mount_scanner"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/extraction_result_cache"

module Analyzer::Javascript
  class Fastify < JavascriptEngine
    analyzer_for "js_fastify"

    PACKAGE_MARKERS = ["\"fastify\"", "\"@fastify/", "\"fastify-plugin\"", "\"@platformatic/"]

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
      # Cross-file `register(require('./x'), { prefix })` prefixes, read back
      # by the shared route extractor through `CodeLocator`.
      RouterMountScanner.new(all_files, @base_paths, base_path, logger, :fastify).scan
      # A sibling Hapi service's plugin module (`server.route({ method,
      # path })`, no import) reads as a Fastify route config; only the
      # closest package.json tells them apart. No package.json: keep it.
      owners = js_package_owners(PACKAGE_MARKERS)

      parallel_file_scan do |path|
        next if (package_dir = js_package_dir(path, owners)) && !owners[package_dir]
        # The plugin-prefix, route-config and QUERY passes below read the
        # text with their own regexes; blanking comments keeps lines.
        content = Noir::JSRouteExtractor.strip_js_comments(read_file_content(path))
        next if Noir::JSRouteExtractor.other_shared_extractor_framework?(content, :fastify)
        facts = fastify_file_facts(path, content, include_callee)
        autoload_prefix = autoload_prefix_for(path, autoload_roots, content)
        parser_endpoints = Noir::JSRouteExtractor.extract_routes(path, content, @is_debug,
          include_callees: include_callee)
        # "METHOD url" this file already emitted, for the auxiliary passes'
        # de-duplication (a Set: scanning the whole result per route was
        # quadratic).
        recorded = Set(String).new
        schema_by_line = facts.schema_params_by_line
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

          endpoint.details.code_paths.first?.try(&.line).try { |line| schema_by_line.try(&.[line]?) }.try &.each do |param|
            endpoint.push_param(param)
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
          # A file registered from another file is served under that
          # register's prefix(es), which the shared extractor applied above.
          mounts = CodeLocator.instance.all(ExpressConstants.file_key(Noir::PathScope.expand(path)))
          (mounts.empty? ? [""] : mounts).each do |mount|
            prefix = Noir::URLPath.join(autoload_prefix, mount)
            extract_route_configs(path, content, result, recorded, include_callee, prefix, facts)
            if has_query_method
              extract_query_shorthand_routes(path, content, result, recorded, include_callee, prefix, facts)
            end
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

    AUTO_PREFIX_RE = /\bautoPrefix\s*=\s*['"]([^'"]+)['"]/

    record FastifyRouteConfig,
      methods : Array(String),
      url : String,
      line : Int32,
      call_start : Int32,
      body_params : Array(Param),
      callees : Array(Noir::JSCalleeExtractor::Entry)

    record FastifyQueryCall,
      receiver : String,
      raw_url : String,
      call_start : Int32,
      line : Int32,
      body_params : Array(Param),
      callees : Array(Noir::JSCalleeExtractor::Entry)

    record FastifyFileFacts,
      autoload_roots : Array(AutoloadRoot),
      plugin_ranges : Array(Tuple(Int32, Int32, String)),
      route_configs : Array(FastifyRouteConfig),
      query_calls : Array(FastifyQueryCall),
      schema_params_by_line : Hash(Int32, Array(Param))

    @@memo = Hash(UInt64, FastifyFileFacts).new
    @@memo_mutex = Mutex.new

    Noir::ExtractionResultCache.register_clearer do
      @@memo_mutex.synchronize { @@memo.clear }
    end

    private def fastify_file_facts(path : String, content : String, include_callee : Bool) : FastifyFileFacts
      key = Noir::ExtractionResultCache.key(content, "fastify_facts", path, include_callee ? "1" : "0")
      Noir::ExtractionResultCache.fetch(@@memo, key, @@memo_mutex) do
        extract_fastify_facts(path, content, include_callee)
      end
    end

    private def extract_fastify_facts(path : String, source : String, include_callees : Bool) : FastifyFileFacts
      autoload_roots = [] of AutoloadRoot
      plugin_ranges = [] of Tuple(Int32, Int32, String)
      route_configs = [] of FastifyRouteConfig
      query_calls = [] of FastifyQueryCall
      schema_params_by_line = Hash(Int32, Array(Param)).new

      Noir::TreeSitter.parse_js_family(source, path) do |root|
        declarations = Hash(String, LibTreeSitter::TSNode).new
        collect_top_level_declarations(root, source, declarations)

        Noir::TreeSitter.walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"

          callee = Noir::TreeSitter.field(node, "function") || next
          callee = Noir::TreeSitter.unwrap_expression(callee)

          method_name = ""
          recv_name = ""
          if Noir::TreeSitter.node_type(callee) == "member_expression"
            if prop = Noir::TreeSitter.field(callee, "property")
              method_name = Noir::TreeSitter.node_text(prop, source)
            end
            if obj = Noir::TreeSitter.field(callee, "object")
              recv_name = Noir::TreeSitter.node_text(Noir::TreeSitter.unwrap_expression(obj), source)
            end
          elsif Noir::TreeSitter.node_type(callee) == "identifier"
            method_name = Noir::TreeSitter.node_text(callee, source)
          end

          args_node = Noir::TreeSitter.field(node, "arguments")
          args = [] of LibTreeSitter::TSNode
          if args_node
            Noir::TreeSitter.each_named_arg(args_node) { |a| args << a }
          end

          case method_name
          when "register"
            # 1. Autoload roots check: { dir: <expr>, dirNameRoutePrefix?: bool }
            args.each do |arg|
              arg_unwrapped = Noir::TreeSitter.unwrap_expression(arg)
              if Noir::TreeSitter.node_type(arg_unwrapped) == "object"
                if dir_prop = extract_prop_value(arg_unwrapped, "dir", source)
                  segments = [] of String
                  Noir::TreeSitter.walk(dir_prop) do |child|
                    case Noir::TreeSitter.node_type(child)
                    when "string", "template_string"
                      if s = decode_string(child, source)
                        segments << s unless s.empty?
                      end
                    end
                  end
                  unless segments.empty?
                    base_dir = File.dirname(Noir::PathScope.expand(path))
                    root_path = Noir::PathScope.expand(File.join([base_dir] + segments))
                    dir_prefix = true
                    if dp = extract_prop_value(arg_unwrapped, "dirNameRoutePrefix", source)
                      dir_prefix = false if Noir::TreeSitter.node_text(dp, source).strip == "false"
                    end
                    autoload_roots << AutoloadRoot.new(root_path, dir_prefix) unless autoload_roots.any? { |r| r.path == root_path }
                  end
                end
              end
            end

            # 2. Plugin ranges: fastify.register(fn, { prefix: '/x' })
            fn_node = nil.as(LibTreeSitter::TSNode?)
            prefix_val = nil.as(String?)
            args.each do |arg|
              unwrapped = Noir::TreeSitter.unwrap_expression(arg)
              case Noir::TreeSitter.node_type(unwrapped)
              when "arrow_function", "function_expression"
                fn_node = unwrapped
              when "identifier"
                ident = Noir::TreeSitter.node_text(unwrapped, source)
                if decl = declarations[ident]?
                  decl_unwrapped = Noir::TreeSitter.unwrap_expression(decl)
                  if {"arrow_function", "function_expression", "function_declaration"}.includes?(Noir::TreeSitter.node_type(decl_unwrapped))
                    fn_node = decl_unwrapped
                  end
                end
              when "object"
                if p = extract_prop_value(unwrapped, "prefix", source)
                  prefix_val = decode_string(Noir::TreeSitter.unwrap_expression(p), source)
                end
              end
            end

            if fn_node && prefix_val
              body_node = Noir::TreeSitter.field(fn_node, "body") || fn_node
              open_byte = LibTreeSitter.ts_node_start_byte(body_node).to_i
              close_byte = LibTreeSitter.ts_node_end_byte(body_node).to_i
              plugin_ranges << {open_byte, close_byte, prefix_val}
            end
          when "route"
            config_node = args.first?.try { |a| Noir::TreeSitter.unwrap_expression(a) }
            if config_node && Noir::TreeSitter.node_type(config_node) == "object"
              has_handler_key = false
              Noir::TreeSitter.each_named_child(config_node) do |child|
                t = Noir::TreeSitter.node_type(child)
                if t == "spread_element"
                  has_handler_key = true
                elsif t == "method_definition"
                  name = Noir::TreeSitter.field(child, "name").try { |n| property_key_name(n, source) }
                  has_handler_key = true if name == "handler" || name == "wsHandler"
                elsif t == "pair"
                  key = Noir::TreeSitter.field(child, "key").try { |k| property_key_name(k, source) }
                  has_handler_key = true if key == "handler" || key == "wsHandler"
                end
              end

              if recv_name.matches?(FASTIFY_INSTANCE_NAME) || has_handler_key
                methods = [] of String
                if m_val = extract_prop_value(config_node, "method", source)
                  m_unwrapped = Noir::TreeSitter.unwrap_expression(m_val)
                  if s = decode_string(m_unwrapped, source)
                    methods << s.downcase if HTTP_METHODS.includes?(s.downcase)
                  elsif Noir::TreeSitter.node_type(m_unwrapped) == "array"
                    Noir::TreeSitter.each_named_arg(m_unwrapped) do |elem|
                      if s = decode_string(Noir::TreeSitter.unwrap_expression(elem), source)
                        methods << s.downcase if HTTP_METHODS.includes?(s.downcase) && !methods.includes?(s.downcase)
                      end
                    end
                  end
                end
                if m_val = extract_prop_value(config_node, "methods", source)
                  m_unwrapped = Noir::TreeSitter.unwrap_expression(m_val)
                  if Noir::TreeSitter.node_type(m_unwrapped) == "array"
                    Noir::TreeSitter.each_named_arg(m_unwrapped) do |elem|
                      if s = decode_string(Noir::TreeSitter.unwrap_expression(elem), source)
                        methods << s.downcase if HTTP_METHODS.includes?(s.downcase) && !methods.includes?(s.downcase)
                      end
                    end
                  end
                end

                url = ""
                if u_val = extract_prop_value(config_node, "url", source) || extract_prop_value(config_node, "path", source)
                  url = decode_string(Noir::TreeSitter.unwrap_expression(u_val), source) || ""
                end

                unless methods.empty? || url.empty?
                  call_start = LibTreeSitter.ts_node_start_byte(node).to_i
                  line = Noir::TreeSitter.node_start_row(node) + 1

                  handler_node = nil.as(LibTreeSitter::TSNode?)
                  if h_val = extract_prop_child(config_node, "handler", source) || extract_prop_child(config_node, "wsHandler", source)
                    if Noir::TreeSitter.node_type(h_val) == "method_definition"
                      handler_node = h_val
                    elsif Noir::TreeSitter.node_type(h_val) == "pair"
                      if v_node = Noir::TreeSitter.field(h_val, "value")
                        val = Noir::TreeSitter.unwrap_expression(v_node)
                        if {"arrow_function", "function_expression"}.includes?(Noir::TreeSitter.node_type(val))
                          handler_node = val
                        elsif Noir::TreeSitter.node_type(val) == "identifier"
                          ident = Noir::TreeSitter.node_text(val, source)
                          if decl = declarations[ident]?
                            decl_unwrapped = Noir::TreeSitter.unwrap_expression(decl)
                            if {"arrow_function", "function_expression", "function_declaration"}.includes?(Noir::TreeSitter.node_type(decl_unwrapped))
                              handler_node = decl_unwrapped
                            end
                          end
                        end
                      end
                    end
                  end

                  body_params = [] of Param
                  config_text = Noir::TreeSitter.node_text(config_node, source)
                  config_text.each_line do |handler_line|
                    p = line_to_param(handler_line)
                    body_params << p if !p.name.empty? && !body_params.any? { |bp| bp.name == p.name && bp.param_type == p.param_type }
                  end

                  if s_val = extract_prop_value(config_node, "schema", source)
                    s_params = extract_schema_params_from_node(s_val, declarations, source)
                    body_params.concat(s_params)
                    schema_params_by_line[line] = s_params unless s_params.empty?
                  end

                  callees = [] of Noir::JSCalleeExtractor::Entry
                  if include_callees && handler_node
                    callees = Noir::JSCalleeExtractor.callees_for_handler_node(handler_node, source, path)
                  end

                  route_configs << FastifyRouteConfig.new(methods, url, line, call_start, body_params, callees)
                end
              end
            end
          when "query"
            if args.size >= 2
              first_arg = Noir::TreeSitter.unwrap_expression(args[0])
              if raw_url = decode_string(first_arg, source)
                if raw_url.starts_with?('/') || raw_url == "*"
                  unless raw_url.includes?(" ")
                    call_start = LibTreeSitter.ts_node_start_byte(node).to_i
                    line = Noir::TreeSitter.node_start_row(node) + 1

                    body_params = [] of Param
                    args_text = args_node ? Noir::TreeSitter.node_text(args_node, source) : ""
                    args_text.each_line do |handler_line|
                      p = line_to_param(handler_line)
                      body_params << p if !p.name.empty?
                    end

                    callees = [] of Noir::JSCalleeExtractor::Entry
                    if include_callees
                      handler_node = nil.as(LibTreeSitter::TSNode?)
                      args[1..].each do |arg|
                        unwrapped = Noir::TreeSitter.unwrap_expression(arg)
                        if {"arrow_function", "function_expression"}.includes?(Noir::TreeSitter.node_type(unwrapped))
                          handler_node = unwrapped
                          break
                        end
                      end
                      if handler_node
                        callees = Noir::JSCalleeExtractor.callees_for_handler_node(handler_node, source, path)
                      else
                        callees = Noir::JSCalleeExtractor.callees_for_function_body(args_text, path, line)
                      end
                    end

                    query_calls << FastifyQueryCall.new(recv_name, raw_url, call_start, line, body_params, callees)
                  end
                end
              end
            end
          else
            if HTTP_METHODS.includes?(method_name) || method_name == "all"
              options_node = nil.as(LibTreeSitter::TSNode?)
              if args.size >= 3
                options_node = Noir::TreeSitter.unwrap_expression(args[1])
              elsif args.size >= 2
                cand = Noir::TreeSitter.unwrap_expression(args[1])
                options_node = cand if Noir::TreeSitter.node_type(cand) == "object"
              end

              if options_node
                if s_val = extract_prop_value(options_node, "schema", source)
                  s_params = extract_schema_params_from_node(s_val, declarations, source)
                  line = Noir::TreeSitter.node_start_row(node) + 1
                  schema_params_by_line[line] = s_params unless s_params.empty?
                end
              end
            end
          end
        end
      end

      autoload_roots.sort_by! { |r| -r.path.size }
      FastifyFileFacts.new(autoload_roots, plugin_ranges, route_configs, query_calls, schema_params_by_line)
    end

    private def collect_autoload_roots : Array(AutoloadRoot)
      roots = [] of AutoloadRoot
      all_files.each do |path|
        next unless ExpressConstants::JS_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
        content = read_file_content(path)
        next unless content.matches?(AUTOLOAD_MARKERS_RE)
        next unless content.includes?("dir")
        content = Noir::JSRouteExtractor.strip_js_comments(content)

        facts = fastify_file_facts(path, content, false)
        facts.autoload_roots.each do |r|
          roots << r unless roots.any? { |existing| existing.path == r.path }
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
    # Cheap per-file gate ahead of the comment strip the markers are read from.
    QUERY_METHOD_GATE_RE = /\baddHttpMethod\b|fastify-http-query/

    private def has_query_http_method? : Bool
      all_files.any? do |path|
        next false unless ExpressConstants::JS_EXTENSIONS.any? { |ext| path.ends_with?(ext) } || path.ends_with?("package.json")
        content = read_file_content(path)
        # Read with comments blanked, so `addHttpMethod(/* x */ 'QUERY')`
        # counts and `// app.addHttpMethod('QUERY')` does not.
        content.matches?(QUERY_METHOD_GATE_RE) &&
          Noir::JSRouteExtractor.strip_js_comments(content).matches?(QUERY_METHOD_MARKERS_RE)
      end
    end

    # Every prefixed plugin body around `offset`, joined outermost first:
    # `register(async (i) => { i.register(async (v2) => { … }, { prefix: '/v2' }) }, { prefix: '/internal' })`
    # serves the inner routes under `/internal/v2`. A body seen twice (a named
    # plugin registered under several prefixes) keeps its first prefix.
    private def plugin_prefix_at(ranges : Array(Tuple(Int32, Int32, String)), offset : Int32) : String
      ranges.select { |open_brace, close_brace, _| offset >= open_brace && offset <= close_brace }
        .uniq! { |open_brace, close_brace, _| {open_brace, close_brace} }
        .sort_by! { |open_brace, close_brace, _| open_brace - close_brace }
        .reduce("") { |joined, range| Noir::URLPath.join(joined, range[2]) }
    end

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
    private def extract_query_shorthand_routes(path : String, content : String, result : Array(Endpoint), recorded : Set(String), include_callee : Bool, autoload_prefix : String = "", facts : FastifyFileFacts? = nil)
      ffacts = facts || fastify_file_facts(path, content, include_callee)
      prefix_ranges = ffacts.plugin_ranges
      instances = nil

      ffacts.query_calls.each do |qc|
        unless qc.receiver.matches?(FASTIFY_INSTANCE_NAME)
          next unless (instances ||= fastify_instance_names(content)).includes?(qc.receiver)
        end

        plugin_prefix = plugin_prefix_at(prefix_ranges, qc.call_start)
        url = plugin_prefix.empty? ? qc.raw_url : Noir::URLPath.join(plugin_prefix, qc.raw_url)
        url = Noir::URLPath.join(autoload_prefix, url) unless autoload_prefix.empty?

        next unless recorded.add?("QUERY #{url}")

        endpoint = Endpoint.new(url, "QUERY")
        endpoint.details = Details.new(PathInfo.new(path, qc.line))

        # Extract path parameters from URL
        url.scan(/:(\w+)/) do |pm|
          next unless pm.size > 0
          param = Param.new(pm[1], "", "path")
          endpoint.push_param(param)
        end

        qc.body_params.each do |p|
          endpoint.push_param(p)
        end
        attach_js_callees(endpoint, qc.callees)

        result << endpoint
      end
    end

    # Walks a file for `fastify.route({ ... })` registrations that the
    # shared parser misses: the config object may span multiple lines,
    # and `methods` may be an array. For each block, decode the method
    # (or methods) and the url/path and emit one endpoint per method.
    private def extract_route_configs(path : String, content : String, result : Array(Endpoint), recorded : Set(String), include_callee : Bool, autoload_prefix : String = "", facts : FastifyFileFacts? = nil)
      ffacts = facts || fastify_file_facts(path, content, include_callee)
      prefix_ranges = ffacts.plugin_ranges

      ffacts.route_configs.each do |rc|
        plugin_prefix = plugin_prefix_at(prefix_ranges, rc.call_start)
        url = plugin_prefix.empty? ? rc.url : Noir::URLPath.join(plugin_prefix, rc.url)
        url = Noir::URLPath.join(autoload_prefix, url) unless autoload_prefix.empty?

        rc.methods.each do |http_method|
          method_up = http_method.upcase
          next unless recorded.add?("#{method_up} #{url}")

          endpoint = Endpoint.new(url, method_up)
          endpoint.details = Details.new(PathInfo.new(path, rc.line))

          url.scan(/:(\w+)/) do |pm|
            next unless pm.size > 0
            param = Param.new(pm[1], "", "path")
            endpoint.push_param(param)
          end

          rc.body_params.each do |bp|
            endpoint.push_param(bp)
          end
          attach_js_callees(endpoint, rc.callees)

          result << endpoint
        end
      end
    end

    # A route's `schema` is its declared input, validated by Fastify itself.
    SCHEMA_PARAM_TYPES = {"querystring" => "query", "query" => "query", "body" => "json", "headers" => "header"}

    private def property_key_name(node : LibTreeSitter::TSNode, source : String) : String
      node = Noir::TreeSitter.unwrap_expression(node)
      case Noir::TreeSitter.node_type(node)
      when "identifier", "property_identifier"
        Noir::TreeSitter.node_text(node, source)
      when "string", "template_string"
        decode_string(node, source) || ""
      else
        ""
      end
    end

    private def extract_prop_value(obj_node : LibTreeSitter::TSNode, name : String, source : String) : LibTreeSitter::TSNode?
      obj_node = Noir::TreeSitter.unwrap_expression(obj_node)
      return unless Noir::TreeSitter.node_type(obj_node) == "object"
      Noir::TreeSitter.each_named_child(obj_node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "pair"
          if key_node = Noir::TreeSitter.field(child, "key")
            return Noir::TreeSitter.field(child, "value") if property_key_name(key_node, source) == name
          end
        when "shorthand_property_identifier"
          return child if Noir::TreeSitter.node_text(child, source) == name
        end
      end
      nil
    end

    private def extract_prop_child(obj_node : LibTreeSitter::TSNode, name : String, source : String) : LibTreeSitter::TSNode?
      obj_node = Noir::TreeSitter.unwrap_expression(obj_node)
      return unless Noir::TreeSitter.node_type(obj_node) == "object"
      Noir::TreeSitter.each_named_child(obj_node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "pair"
          if key_node = Noir::TreeSitter.field(child, "key")
            return child if property_key_name(key_node, source) == name
          end
        when "method_definition"
          if name_node = Noir::TreeSitter.field(child, "name")
            return child if property_key_name(name_node, source) == name
          end
        when "shorthand_property_identifier"
          return child if Noir::TreeSitter.node_text(child, source) == name
        end
      end
      nil
    end

    private def decode_string(node : LibTreeSitter::TSNode, source : String) : String?
      node = Noir::TreeSitter.unwrap_expression(node)
      raw = Noir::TreeSitter.node_text(node, source).strip
      return if raw.size < 2
      first = raw[0]
      last = raw[-1]
      return unless (first == '\'' || first == '"' || first == '`') && first == last
      return if first == '`' && raw.includes?("${")
      raw[1..-2]
    end

    private def extract_schema_params_from_node(node : LibTreeSitter::TSNode, declarations : Hash(String, LibTreeSitter::TSNode), source : String) : Array(Param)
      params = [] of Param
      node = resolve_decl_or_expr(node, declarations, source)
      if typebox_call?(node, source)
        args_node = Noir::TreeSitter.field(node, "arguments")
        node = args_node.try { |a| Noir::TreeSitter.first_named_arg(a) } || return params
        node = resolve_decl_or_expr(node, declarations, source)
      end
      return params unless Noir::TreeSitter.node_type(node) == "object"

      SCHEMA_PARAM_TYPES.each do |part, type|
        part_node = extract_prop_value(node, part, source) || next
        part_node = resolve_decl_or_expr(part_node, declarations, source)
        if typebox_call?(part_node, source)
          if args_node = Noir::TreeSitter.field(part_node, "arguments")
            if arg = Noir::TreeSitter.first_named_arg(args_node)
              arg = resolve_decl_or_expr(arg, declarations, source)
              if Noir::TreeSitter.node_type(arg) == "object"
                collect_object_property_names(arg, source).each do |pname|
                  params << Param.new(pname, "", type)
                end
              end
            end
          end
        elsif Noir::TreeSitter.node_type(part_node) == "object"
          if props = extract_prop_value(part_node, "properties", source)
            props = resolve_decl_or_expr(props, declarations, source)
            if Noir::TreeSitter.node_type(props) == "object"
              collect_object_property_names(props, source).each do |pname|
                params << Param.new(pname, "", type)
              end
            end
          end
        end
      end

      params
    end

    private def resolve_decl_or_expr(node : LibTreeSitter::TSNode, declarations : Hash(String, LibTreeSitter::TSNode), source : String) : LibTreeSitter::TSNode
      node = Noir::TreeSitter.unwrap_expression(node)
      if Noir::TreeSitter.node_type(node) == "identifier"
        name = Noir::TreeSitter.node_text(node, source)
        if decl = declarations[name]?
          return resolve_decl_or_expr(decl, declarations, source)
        end
      end
      node
    end

    private def typebox_call?(node : LibTreeSitter::TSNode, source : String) : Bool
      return false unless Noir::TreeSitter.node_type(node) == "call_expression"
      fn = Noir::TreeSitter.field(node, "function") || return false
      fn_text = Noir::TreeSitter.node_text(fn, source)
      fn_text.ends_with?("Object")
    end

    private def collect_object_property_names(obj_node : LibTreeSitter::TSNode, source : String) : Array(String)
      names = [] of String
      Noir::TreeSitter.each_named_child(obj_node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "pair"
          if k = Noir::TreeSitter.field(child, "key")
            name = property_key_name(k, source)
            names << name unless name.empty?
          end
        when "shorthand_property_identifier"
          names << Noir::TreeSitter.node_text(child, source)
        end
      end
      names
    end

    private def collect_top_level_declarations(root : LibTreeSitter::TSNode, source : String, declarations : Hash(String, LibTreeSitter::TSNode))
      Noir::TreeSitter.each_named_child(root) do |child|
        node = child
        if Noir::TreeSitter.node_type(node) == "export_statement"
          if decl = Noir::TreeSitter.field(node, "declaration")
            node = decl
          end
        end

        case Noir::TreeSitter.node_type(node)
        when "lexical_declaration", "variable_declaration"
          Noir::TreeSitter.each_named_child(node) do |vdecl|
            next unless Noir::TreeSitter.node_type(vdecl) == "variable_declarator"
            name_node = Noir::TreeSitter.field(vdecl, "name")
            val_node = Noir::TreeSitter.field(vdecl, "value")
            if name_node && val_node && Noir::TreeSitter.node_type(name_node) == "identifier"
              name = Noir::TreeSitter.node_text(name_node, source)
              declarations[name] = val_node
            end
          end
        when "function_declaration"
          if name_node = Noir::TreeSitter.field(node, "name")
            name = Noir::TreeSitter.node_text(name_node, source)
            declarations[name] = node
          end
        end
      end
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
