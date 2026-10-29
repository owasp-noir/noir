require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"
require "../../../miniparsers/import_graph"
require "../../../miniparsers/js_handler_resolver"
require "../../../utils/top_level_split"

module Analyzer::Javascript
  class Nextjs < JavascriptEngine
    analyzer_for "js_nextjs"

    HTTP_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
    EXTENSIONS   = [".js", ".jsx", ".ts", ".tsx", ".mjs"]

    # Compiled once per verb — interpolated regex literals would otherwise
    # be rebuilt (full PCRE2 compile) for every method on every file.
    EXPORT_VERB_FUNCTION_RES = HTTP_METHODS.map { |m| {m, /export\s+(?:async\s+)?function\s+#{m}\b/} }.to_h
    EXPORT_VERB_CONST_RES    = HTTP_METHODS.map { |m| {m, /export\s+const\s+#{m}\s*=/} }.to_h
    EXPORT_VERB_BRACE_RES    = HTTP_METHODS.map { |m| {m, /export\s+\{[^}]*\b#{m}\b[^}]*\}/} }.to_h
    # `export const { POST } = serve<Input>(...)` — handler(s) destructured
    # from a factory call (e.g. @upstash/workflow/nextjs). The plain brace
    # regex misses it because `const` sits between `export` and `{`.
    EXPORT_VERB_CONST_BRACE_RES  = HTTP_METHODS.map { |m| {m, /export\s+const\s+\{[^}]*\b#{m}\b[^}]*\}\s*=/} }.to_h
    EXPORT_VERB_FUNCTION_SIG_RES = HTTP_METHODS.map { |m| {m, /export\s+(?:async\s+)?function\s+#{m}\b\s*\([^)]*\)/} }.to_h
    EXPORT_VERB_CONST_ARROW_RES  = HTTP_METHODS.map { |m| {m, /export\s+const\s+#{m}\s*=\s*(?:async\s*)?(?:\([^)]*\)|\w+)(?:\s*:\s*[^=]+?)?\s*=>/} }.to_h

    # Pages Router method checks. The receiver is `req.method` /
    # `request.method`, or a bare `method` once the file binds it from the
    # request (`const { method } = req`, `const method = req.method`).
    METHOD_FROM_REQUEST      = /(?<![\w$.])method\s*=\s*(?:req|request)\.method\b/
    DESTRUCTURE_FROM_REQUEST = /\{((?:[^{}]++|\{[^{}]*+\})*+)\}\s*=\s*(?:req|request)\b(?!\s*[.\[])/
    BARE_METHOD_KEY          = /(?<![\w$.:])method\b(?!\s*:)/
    METHOD_EQ                = /\b(?:req|request)\.method\s*===?\s*['"]([A-Z]+)['"]/
    METHOD_EQ_BARE           = /(?:\b(?:req|request)\.|(?<![\w$.]))method\s*===?\s*['"]([A-Z]+)['"]/
    METHOD_NE                = /\b(?:req|request)\.method\s*!==?\s*['"]([A-Z]+)['"]/
    METHOD_NE_BARE           = /(?:\b(?:req|request)\.|(?<![\w$.]))method\s*!==?\s*['"]([A-Z]+)['"]/
    METHOD_SWITCH            = /switch\s*\(\s*(?:req|request)\.method\s*\)/
    METHOD_SWITCH_BARE       = /switch\s*\(\s*(?:(?:req|request)\.)?method\s*\)/
    METHOD_INCLUDES          = /\[\s*([^\]]+)\]\s*\.includes\s*\(\s*(?:req|request)\.method/
    METHOD_INCLUDES_BARE     = /\[\s*([^\]]+)\]\s*\.includes\s*\(\s*(?:(?:req|request)\.)?method\b/
    # `if (<cond>)` followed by its consequent: an immediate `throw`, the
    # block up to its first brace (captured in a lookahead, so a guard
    # nested in that block is still scanned), or a `return` statement.
    # Every repetition is possessive or a single char class: grouped
    # repetition overflowed the PCRE2 JIT stack on long hostile input.
    METHOD_GUARD = /\bif\s*\(((?:[^(){};]++|\([^()]*+\))*+)\)\s*(?:(throw)\b|(?=\{([^{}]*))|return\b([^{};\n]*))/
    # What makes a consequent a rejection, and what makes it conditional
    # (a nested `if`, ternary or `&&`/`||` ahead of the rejection).
    GUARD_REJECTS     = /\bthrow\b|\b4\d\d\b|\bMETHOD_NOT_ALLOWED\b|(?i:not allowed)/
    GUARD_CONDITIONAL = /\bif\b|\?|&&|\|\|/

    # `export default withMiddlewares({ GET: ..., POST: ... })`: a wrapper
    # handed a verb-keyed object serves exactly those methods.
    DEFAULT_EXPORT_CALL_OBJECT = /export\s+default\s+(?!(?:async|function|class)\b)[\w$.]+\s*\(\s*\{/
    VERB_MAP_KEY               = /\A(?:async\s+)?["']?(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)["']?\s*(?::|\(|\z)/

    # `export default function handler(` / `export default async (req, res) =>`.
    DEFAULT_EXPORT_FUNCTION  = /export\s+default\s+(?:async\s+)?(?:function\b\s*\*?\s*([\w$]+)?|(?:\([^)]*\)|[\w$]+)(?:\s*:\s*[^=]+?)?\s*=>)/
    REEXPORT_DEFAULT         = /export\s*\{\s*(?:([\w$]+)\s+as\s+)?default\s*\}\s*from\s*['"`]([^'"`]+)['"`]/
    DEFAULT_EXPORT           = /export\s+default\s+(?!(?:async|function|class)\b)/
    WRAPPER_CALL             = /\A\s*(?!(?:async|function|new)\b)[\w$.]+\s*(?:<[^>()]*>)?\s*\(/
    DEFAULT_KEY_OBJECT       = /\A\{\s*default\s*:\s*(.+?)\s*,?\s*\}\z/m
    FUNCTION_DEFINITION_LINE = /\bfunction\b|=>|=\s*(?:async\s*)?\(/
    DYNAMIC_IMPORT           = /\A(?:await\s+)?import\s*\(\s*['"`]([^'"`]+)['"`]\s*\)\z/

    CONFIG_BASENAMES = ["next.config.js", "next.config.ts", "next.config.mjs", "next.config.cjs"]
    BASE_PATH_RE     = /\bbasePath\s*:\s*(['"`])(\/[^'"`$]*)\1/

    # Config directory => its `basePath`, which prefixes every route below it.
    @next_base_paths = {} of String => String

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new
      include_callee = callees_needed?
      project_roots = discover_js_project_roots(["\"next\""], CONFIG_BASENAMES)
      @next_base_paths = collect_base_paths

      parallel_file_scan(EXTENSIONS) do |path|
        next unless path_under_project_roots?(path, project_roots)
        next if ignored_next_path?(path)

        if app_router_file?(path)
          analyze_app_router_file(path, result, mutex, include_callee)
        elsif pages_router_file?(path)
          analyze_pages_router_file(path, result, mutex, include_callee)
        else
          analyze_server_actions_file(path, result, mutex, include_callee)
        end
      end

      result
    end

    # Every config is recorded, a missing `basePath` as "": a nested app
    # without one must not inherit its parent's.
    private def collect_base_paths : Hash(String, String)
      base_paths = {} of String => String
      CONFIG_BASENAMES.each do |basename|
        get_files_by_basename(basename).each do |file|
          content = Noir::JSRouteExtractor.strip_js_comments(read_file_content(file))
          dir = File.dirname(Noir::PathScope.expand(file))
          base_paths[dir] = content.match(BASE_PATH_RE).try(&.[2].rstrip('/')) || base_paths[dir]? || ""
        rescue IO::Error
          next
        end
      end
      base_paths
    end

    # `basePath` of the closest `next.config.*` above `path`.
    private def base_path_for(path : String) : String
      return "" if @next_base_paths.values.all?(&.empty?)
      dir = File.dirname(Noir::PathScope.expand(path))
      loop do
        return @next_base_paths[dir] if @next_base_paths.has_key?(dir)
        parent = File.dirname(dir)
        return "" if parent == dir
        dir = parent
      end
    end

    private def ignored_next_path?(path : String) : Bool
      # Scan-base-relative, never absolute: a `__tests__/` or `test/`
      # directory ABOVE the scan base is not this project's test tree.
      relative = base_relative_path(path)
      relative.includes?(".test.") || relative.includes?(".spec.") ||
        relative.includes?("/__tests__/") || relative.includes?("/__mocks__/") ||
        relative.includes?("/test/fixtures/") || relative.includes?("/tests/fixtures/") ||
        e2e_project?(relative)
    end

    # An e2e harness app, judged on the project location above the router
    # directory only: `app/api/e2e/...` below it is a real URL (dub).
    private def e2e_project?(relative : String) : Bool
      idx = [relative.index("/pages/api/"), relative.index("/app/")].compact.min? || return false
      relative[0..idx].matches?(Noir::JSRouteExtractor::STRICT_TEST_PATH_MARKER)
    end

    # The router-directory markers below name directories *inside* the
    # Next.js project, so they are matched on the scan-base-relative
    # path. On the absolute path a checkout that merely lived under an
    # `app/` directory turned every `route.ts` in the tree into an
    # app-router handler, and `String#index` (first occurrence) then
    # derived the URL from that outside directory.
    private def app_router_file?(path : String) : Bool
      return false unless base_relative_path(path).includes?("/app/")
      EXTENSIONS.any? { |ext| path.ends_with?("/route#{ext}") }
    end

    private def pages_router_file?(path : String) : Bool
      base_relative_path(path).includes?("/pages/api/")
    end

    private def analyze_pages_router_file(path : String, result : Array(Endpoint), mutex : Mutex, include_callee : Bool)
      scoped = base_relative_path(path)
      idx = scoped.index("/pages/api/")
      return if idx.nil?

      relative = scoped[(idx + "/pages/api/".size)..-1]
      relative = strip_extension(relative)

      # Skip private folders/files (leading underscore)
      return if relative.split("/").any?(&.starts_with?("_"))

      url = "#{base_path_for(path)}/api/" + convert_segments(relative)
      url = normalize_url(url)

      begin
        content = read_file_content(path)
      rescue e
        logger.debug "Error reading file #{path}: #{e.message}"
        return
      end
      return if Noir::JSRouteExtractor.trpc_next_mount?(path, content)
      sanitized = Noir::JSRouteExtractor.strip_js_comments(content)

      methods = detect_pages_router_methods(sanitized)
      # Comments are blanked in place, so lines and callee positions still
      # match the file.
      default_body_info = extract_default_export_body(sanitized)
      default_source_line = default_body_info.try(&.[1]) || 1

      methods.each do |method|
        endpoint = Endpoint.new(url, method)
        handler = verb_export_handler(sanitized, path, method) || default_export_handler(sanitized, path, method)
        body_info = extract_exported_method_body(sanitized, method) || default_body_info || same_file_body(sanitized, path, handler)
        endpoint.details = Details.new(PathInfo.new(path, body_info.try(&.[1]) || default_source_line))
        endpoint.handler = handler

        extract_path_params(url, endpoint)
        extract_pages_router_params(sanitized, endpoint)
        if include_callee
          attach_callees(endpoint, path, body_info) if body_info
        end

        mutex.synchronize { result << endpoint }
      end
    end

    private def analyze_app_router_file(path : String, result : Array(Endpoint), mutex : Mutex, include_callee : Bool)
      scoped = base_relative_path(path)
      idx = scoped.index("/app/")
      return if idx.nil?

      relative = scoped[(idx + "/app/".size)..-1]
      # Drop /route.ext
      EXTENSIONS.each do |ext|
        if relative.ends_with?("/route#{ext}")
          relative = relative[0..(relative.size - "/route#{ext}".size - 1)]
          break
        elsif relative == "route#{ext}"
          relative = ""
          break
        end
      end

      # Skip private folders (leading underscore)
      return if relative.split("/").any?(&.starts_with?("_"))

      # Strip route groups (parenthesized segments)
      segments = relative.split("/").reject { |seg| seg.empty? || (seg.starts_with?("(") && seg.ends_with?(")")) }
      converted = segments.map { |seg| convert_segment(seg) }

      url = "#{base_path_for(path)}/" + converted.join("/")
      analyze_route_handler_file(path, normalize_url(url), result, mutex, include_callee)
    end

    # Verb-exported Web `Request` handlers in one module, served at `url`.
    # Shared with Expo Router's `+api` files, which use the same shape.
    private def analyze_route_handler_file(path : String, url : String, result : Array(Endpoint), mutex : Mutex, include_callee : Bool)
      begin
        content = read_file_content(path)
      rescue e
        logger.debug "Error reading file #{path}: #{e.message}"
        return
      end
      sanitized = Noir::JSRouteExtractor.strip_js_comments(content)

      methods = extract_app_router_methods(sanitized)
      methods = methods_from_reexport(path, sanitized) if methods.empty?
      return if methods.empty?

      methods.each do |method|
        endpoint = Endpoint.new(url, method)
        # Read from the blanked text: `export {\n  list as GET, // x\n}` hid
        # the alias, and the line fell back to 1.
        handler = verb_export_handler(sanitized, path, method)
        method_body_info = extract_exported_method_body(sanitized, method)
        # A wrapped handler's own body misses the helpers it calls
        # (`validateRequest(req)` reading `apiKey`), so params keep reading
        # the whole file there; the line and callees are the handler's.
        param_source = method_body_info.try(&.[0]) || sanitized
        method_body_info ||= same_file_body(sanitized, path, handler)
        endpoint.details = Details.new(PathInfo.new(path, method_body_info.try(&.[1]) || 1))
        endpoint.handler = handler

        extract_path_params(url, endpoint)
        extract_app_router_params(param_source, endpoint)
        if include_callee
          attach_callees(endpoint, path, method_body_info) if method_body_info
        end

        mutex.synchronize { result << endpoint }
      end
    end

    private def analyze_server_actions_file(path : String, result : Array(Endpoint), mutex : Mutex, include_callee : Bool)
      begin
        content = read_file_content(path)
      rescue e
        logger.debug "Error reading file #{path}: #{e.message}"
        return
      end

      # File must declare "use server" directive at the top
      return unless has_use_server_directive?(content)
      sanitized = Noir::JSRouteExtractor.strip_js_comments(content)

      seen = Set(String).new

      # export async function NAME(args) { ... }
      sanitized.scan(/export\s+async\s+function\s+(\w+)\s*\(([^)]*)\)/) do |match|
        action_name = match[1]
        next unless seen.add?(action_name)
        register_server_action(path, action_name, match[2], sanitized, match, result, mutex, include_callee)
      end

      # export const NAME = async (args) => { ... }
      sanitized.scan(/export\s+const\s+(\w+)\s*=\s*async\s*\(([^)]*)\)/) do |match|
        action_name = match[1]
        next unless seen.add?(action_name)
        register_server_action(path, action_name, match[2], sanitized, match, result, mutex, include_callee)
      end

      # Note: `export default` actions are unaddressable by name, and
      # `export { foo, bar }` re-exports are out of scope (too complex to parse safely).
    end

    private def register_server_action(path : String, action_name : String, args : String,
                                       sanitized : String, match : Regex::MatchData,
                                       result : Array(Endpoint), mutex : Mutex, include_callee : Bool)
      param_body_info = extract_action_body(sanitized, match)
      body = param_body_info.try(&.[0]) || ""

      url = "/" + action_name
      endpoint = Endpoint.new(url, "POST")
      endpoint.kind = "server-action"
      endpoint.details = Details.new(PathInfo.new(path, param_body_info.try(&.[1]) || line_number_for_index(sanitized, match.begin(0) || 0)))
      endpoint.handler = Handler.new(action_name, path, line_number_for_index(sanitized, match.begin(0) || 0))

      extract_server_action_params(args, body, endpoint)
      # The blanked body: a commented-out declaration of the same name no
      # longer lends its callees.
      attach_callees(endpoint, path, param_body_info) if include_callee && param_body_info

      mutex.synchronize { result << endpoint }
    end

    # Return the text and opening line for the braced function body that starts
    # after the match's args list.
    private def extract_action_body(content : String, match : Regex::MatchData) : Tuple(String, Int32)?
      match_end = match.end(0)
      return if match_end.nil?
      extract_braced_body(content, match_end)
    end

    private def extract_default_export_body(content : String) : Tuple(String, Int32)?
      match = content.match(/export\s+default\s+(?:async\s+)?function(?:\s+\w+)?\s*\([^)]*\)/)
      if match
        match_end = match.end(0)
        return extract_braced_body(content, match_end) if match_end
      end

      arrow_match = content.match(/export\s+default\s+(?:async\s*)?(?:\([^)]*\)|\w+)(?:\s*:\s*[^=]+?)?\s*=>/)
      if arrow_match
        match_end = arrow_match.end(0)
        return extract_braced_body(content, match_end) if match_end
      end

      alias_match = content.match(/export\s+default\s+([A-Za-z_$][\w$]*)\s*;?/)
      extract_named_function_body(content, alias_match[1]) if alias_match
    end

    # The function serving `method` when the module exports the verb: the
    # export itself (`export async function GET`), the local it aliases
    # (`export { list as GET }`), or what the wrapper it is bound to wraps
    # (`export const GET = withAuth(getHandler)`). Nil when no verb export.
    private def verb_export_handler(content : String, path : String, method : String) : Handler?
      if m = content.match(EXPORT_VERB_FUNCTION_RES[method]) || content.match(EXPORT_VERB_CONST_ARROW_RES[method])
        return Handler.new(method, path, line_number_for_index(content, m.begin(0)))
      end
      if local = exported_alias_for_method(content, method)
        line = line_number_for_index(content, content.index(EXPORT_VERB_BRACE_RES[method]) || 0)
        return function_handler(local, content, path) || Handler.new(local, path, line)
      end
      if m = content.match(EXPORT_VERB_CONST_RES[method])
        wrapped_handler(content, m.end(0), path, method, line_number_for_index(content, m.begin(0)))
      end
    end

    # `export const GET = withAuth(getHandler)`: the wrapped function's body
    # when it is declared in this file, for the line, params and callees.
    private def same_file_body(content : String, path : String, handler : Handler?) : Tuple(String, Int32)?
      extract_named_function_body(content, handler.name) if handler && handler.path == path
    end

    # The pages-router default export: a function declared in place, or the
    # function it names through a wrapper call or, for a verb-keyed
    # `export default wrapper({ GET: ... })`, through `method`'s value.
    private def default_export_handler(content : String, path : String, method : String) : Handler?
      if m = content.match(DEFAULT_EXPORT_FUNCTION)
        return Handler.new(m[1]? || "default", path, line_number_for_index(content, m.begin(0)))
      end
      if m = content.match(REEXPORT_DEFAULT)
        name = m[1]? || "default"
        return Noir::JSHandlerResolver.resolve_module_export(m[2], name, path) ||
          Handler.new(name, path, line_number_for_index(content, m.begin(0)))
      end
      m = content.match(DEFAULT_EXPORT) || return
      line = line_number_for_index(content, m.begin(0))
      if content.match(DEFAULT_EXPORT_CALL_OBJECT).try(&.begin(0)) == m.begin(0)
        open = content.index('{', m.end(0)) || return
        close = Noir::JSRouteExtractor.find_matching_brace(content, open) || return
        Noir::TopLevelSplit.split(content[(open + 1)...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).each do |part|
          key = part.match(VERB_MAP_KEY)
          next unless key && key[1] == method
          # `GET: wrap(h)`, shorthand `GET`; a method body `GET() {` is inline.
          value = key[0].ends_with?(':') ? part[key.end(0)..] : (key[0].ends_with?('(') ? "" : key[1])
          return resolved_or_export(unwrap_handler(value, content, path), "default", path, line)
        end
        return Handler.new("default", path, line)
      end
      wrapped_handler(content, m.end(0), path, "default", line)
    end

    # `export_name`'s value from `start`: a reference, or a call whose first
    # argument (unwrapped a few levels) is one. Points at the export line
    # when what it wraps is not a definition the scan can open.
    private def wrapped_handler(content : String, start : Int32, path : String, export_name : String, line : Int32) : Handler
      rest = content[start..]
      value = if call = rest.match(WRAPPER_CALL)
                close = Noir::JSRouteExtractor.find_matching_paren(rest, call.end(0) - 1)
                # `withX(opts)(handler)`: the first call's argument is not the handler.
                close && !rest[(close + 1)..].lstrip.starts_with?('(') ? rest[0..close] : ""
              else
                rest[/\A\s*[\w$.]+/]? || ""
              end
      resolved_or_export(unwrap_handler(value, content, path), export_name, path, line)
    end

    private def resolved_or_export(handler : Handler?, export_name : String, path : String, line : Int32) : Handler
      handler || Handler.new(export_name, path, line)
    end

    # `reference` resolved to a definition that is a function: `NextAuth(
    # authOptions)` wraps a config object, which serves nothing.
    private def function_handler(reference : String, content : String, path : String) : Handler?
      handler = Noir::JSHandlerResolver.resolve(reference, content, path) || return
      def_path, def_line = handler.path, handler.line
      return unless def_path && def_line
      source = def_path == path ? content : (read_file_content(def_path) rescue return)
      handler if source.lines[def_line - 1]?.try(&.matches?(FUNCTION_DEFINITION_LINE))
    end

    # `defaultResponder(handler)`, `Promise.resolve({ default: wrap(h) })`,
    # `import("./_get")`: peel wrapper calls (first argument) and
    # `{ default: x }` objects down to a reference or a dynamic import.
    private def unwrap_handler(value : String, content : String, path : String) : Handler?
      text = value.strip.chomp(';').strip
      4.times do
        if m = text.match(DYNAMIC_IMPORT)
          return Noir::JSHandlerResolver.resolve_module_export(m[1], nil, path)
        end
        return function_handler(text, content, path) if text.matches?(Noir::JSHandlerResolver::REFERENCE_RE)
        if m = text.match(DEFAULT_KEY_OBJECT)
          text = m[1].strip
          next
        end
        call = text.match(WRAPPER_CALL) || return
        close = Noir::JSRouteExtractor.find_matching_paren(text, call.end(0) - 1) || return
        text = Noir::TopLevelSplit.split(text[call.end(0)...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).first?.try(&.strip) || return
      end
      nil
    end

    private def extract_exported_method_body(content : String, method : String) : Tuple(String, Int32)?
      if body_info = extract_direct_exported_method_body(content, method)
        return body_info
      end

      if local_name = exported_alias_for_method(content, method)
        extract_named_function_body(content, local_name)
      end
    end

    private def extract_direct_exported_method_body(content : String, method : String) : Tuple(String, Int32)?
      # `method` is always one of HTTP_METHODS here, so the per-verb
      # precompiled tables apply.
      function_match = content.match(EXPORT_VERB_FUNCTION_SIG_RES[method])
      if function_match
        match_end = function_match.end(0)
        return extract_braced_body(content, match_end) if match_end
      end

      const_match = content.match(EXPORT_VERB_CONST_ARROW_RES[method])
      if const_match
        match_end = const_match.end(0)
        extract_braced_body(content, match_end) if match_end
      end
    end

    private def extract_named_function_body(content : String, name : String) : Tuple(String, Int32)?
      function_match = content.match(cached_regex("nextjs:named_fn:#{name}") { /(?:^|[^\w$])(?:async\s+)?function\s+#{Regex.escape(name)}\b\s*\([^)]*\)/ })
      if function_match
        match_end = function_match.end(0)
        return extract_braced_body(content, match_end) if match_end
      end

      const_match = content.match(cached_regex("nextjs:named_const:#{name}") { /(?:const|let|var)\s+#{Regex.escape(name)}\s*=\s*(?:async\s*)?(?:\([^)]*\)|\w+)(?:\s*:\s*[^=]+?)?\s*=>/ })
      if const_match
        match_end = const_match.end(0)
        extract_braced_body(content, match_end) if match_end
      end
    end

    private def exported_alias_for_method(content : String, method : String) : String?
      content.scan(/export\s+\{([^}]+)\}/) do |match|
        split_top_level_commas(match[1]).each do |part|
          pieces = part.strip.split(/\s+as\s+/)
          next if pieces.empty?

          if pieces.size == 1
            name = pieces[0].strip
            return name if name == method
          elsif pieces.size == 2
            local_name = pieces[0].strip
            exported_name = pieces[1].strip
            return local_name if exported_name == method
          end
        end
      end
      nil
    end

    private def extract_braced_body(content : String, start_pos : Int32) : Tuple(String, Int32)?
      open_pos = content.index('{', start_pos)
      return if open_pos.nil?
      depth = 1
      i = open_pos + 1
      # `content[i]` re-decodes UTF-8 from byte 0 on every call once the
      # string isn't single_byte_optimizable? (any non-ASCII char), making
      # this depth-scan O(n^2) on a large non-ASCII handler body. Index a
      # pre-materialized Char array instead — same char-by-char semantics,
      # O(1) per lookup.
      chars = content.chars
      while i < chars.size && depth > 0
        case chars[i]
        when '{'
          depth += 1
        when '}'
          depth -= 1
          break if depth == 0
        end
        i += 1
      end
      return if depth > 0

      {content[(open_pos + 1)...i], line_number_for_index(content, open_pos)}
    end

    private def attach_callees(endpoint : Endpoint, path : String, body_info : Tuple(String, Int32))
      body, open_brace_line = body_info
      language = typescript_source?(path) ? :typescript : :javascript
      Noir::JSCalleeExtractor.callees_for_function_body(body, path, open_brace_line, language: language).each do |name, callee_path, line|
        endpoint.push_callee(Callee.new(name, path: callee_path, line: line))
      end
    end

    private def typescript_source?(path : String) : Bool
      path.ends_with?(".ts") || path.ends_with?(".tsx")
    end

    private def detect_pages_router_methods(content : String) : Array(String)
      # If named HTTP method exports exist, use them; otherwise default handler covers all.
      explicit = [] of String
      HTTP_METHODS.each do |m|
        if content.match(EXPORT_VERB_FUNCTION_RES[m]) ||
           content.match(EXPORT_VERB_CONST_RES[m])
          explicit << m
        end
      end

      return explicit unless explicit.empty?

      if mapped = default_export_verb_map(content)
        return mapped
      end

      # Heuristic: look for req.method checks to infer declared methods.
      bare = binds_bare_method?(content)
      inferred = [] of String
      content.scan(bare ? METHOD_EQ_BARE : METHOD_EQ) do |m|
        method = m[1]
        inferred << method if HTTP_METHODS.includes?(method) && !inferred.includes?(method)
      end

      # `if (req.method !== 'POST') return res.status(405)...` — an early
      # exit guard names the methods that get past it. A negation that only
      # gates some branch says nothing, so it must lead to a rejection, and
      # only an `||` arm made purely of `&&`-joined method negations bounds
      # the method (`!== 'GET' && !token` still lets an authed POST in).
      if content.includes?("!=")
        ne = bare ? METHOD_NE_BARE : METHOD_NE
        content.scan(METHOD_GUARD) do |guard|
          next unless guard[2]? || rejecting_consequent?(guard[3]? || guard[4]? || "")
          guard[1].split("||").each do |arm|
            next unless arm.gsub(ne, "").gsub(/[\s()&]/, "").empty?
            arm.scan(ne) do |m|
              method = m[1]
              inferred << method if HTTP_METHODS.includes?(method) && !inferred.includes?(method)
            end
          end
        end
      end

      infer_switch_method_cases(content, bare).each do |method|
        inferred << method if HTTP_METHODS.includes?(method) && !inferred.includes?(method)
      end

      content.scan(bare ? METHOD_INCLUDES_BARE : METHOD_INCLUDES) do |m|
        m[1].scan(/['"]([A-Z]+)['"]/) do |mm|
          method = mm[1]
          inferred << method if HTTP_METHODS.includes?(method) && !inferred.includes?(method)
        end
      end

      return inferred unless inferred.empty?

      # Default-export handler — applies to ALL methods.
      ["GET", "POST", "PUT", "DELETE", "PATCH"]
    end

    # Verb keys of the object literal passed to the default-export call, or
    # nil when there is none or it cannot be read completely (spread or
    # computed key). Uppercase keys only.
    private def default_export_verb_map(content : String) : Array(String)?
      start = content.match(DEFAULT_EXPORT_CALL_OBJECT) || return
      open = start.end(0) - 1
      close = Noir::JSRouteExtractor.find_matching_brace(content, open) || return
      verbs = [] of String
      Noir::TopLevelSplit.split(content[(open + 1)...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).each do |part|
        return if part.starts_with?("...") || part.starts_with?('[')
        if key = part.match(VERB_MAP_KEY)
          verbs << key[1]
        end
      end
      HTTP_METHODS.select { |m| verbs.includes?(m) } unless verbs.empty?
    end

    # A block or `return` statement that rejects the request outright, with
    # no nested condition ahead of the rejection: the write branch of
    # `if (req.method !== 'GET') { if (!id) return res.status(400) ... }`
    # validates, it does not reject non-GET methods.
    private def rejecting_consequent?(text : String) : Bool
      return false unless reject = text =~ GUARD_REJECTS
      conditional = text =~ GUARD_CONDITIONAL
      conditional.nil? || reject < conditional
    end

    # `const method = req.method`, or `method` among the top-level keys of
    # an object pattern destructured from the request — nested patterns
    # (`{ query: { id }, method }`) are dropped before looking.
    private def binds_bare_method?(content : String) : Bool
      return true if content.matches?(METHOD_FROM_REQUEST)
      content.scan(DESTRUCTURE_FROM_REQUEST) do |m|
        return true if m[1].gsub(/\{[^{}]*\}/, "").matches?(BARE_METHOD_KEY)
      end
      false
    end

    private def infer_switch_method_cases(content : String, bare : Bool) : Array(String)
      methods = [] of String
      content.scan(bare ? METHOD_SWITCH_BARE : METHOD_SWITCH) do |match|
        match_end = match.end(0)
        next unless match_end

        open_brace = content.index("{", match_end)
        next unless open_brace

        close_brace = Noir::JSRouteExtractor.find_matching_brace(content, open_brace)
        next unless close_brace

        content[(open_brace + 1)...close_brace].scan(/case\s+['"]([A-Z]+)['"]\s*:/) do |case_match|
          method = case_match[1]
          methods << method if HTTP_METHODS.includes?(method) && !methods.includes?(method)
        end
      end
      methods
    end

    private def extract_app_router_methods(content : String) : Array(String)
      methods = [] of String
      HTTP_METHODS.each do |m|
        if content.match(EXPORT_VERB_FUNCTION_RES[m]) ||
           content.match(EXPORT_VERB_CONST_RES[m]) ||
           content.match(EXPORT_VERB_BRACE_RES[m]) ||
           content.match(EXPORT_VERB_CONST_BRACE_RES[m])
          methods << m
        end
      end
      methods
    end

    # An app-router `route.ts` may re-export its verb handlers wholesale
    # from another route via `export * from "<spec>"` (dub uses this for
    # ~18 alias routes). The file itself carries no verb token, so resolve
    # the target relative to this file, read it, and report ITS methods —
    # emitted at the current file's URL by the caller. Bounded recursion
    # follows a chain of re-exports.
    private def methods_from_reexport(path : String, content : String, depth : Int32 = 0) : Array(String)
      return [] of String if depth > 3
      specs = [] of String
      content.scan(/export\s+\*\s+from\s+['"]([^'"]+)['"]/) { |m| specs << m[1] }
      return [] of String if specs.empty?

      methods = [] of String
      specs.each do |spec|
        target = Noir::ImportGraph.resolve_relative_import(path, spec, boundary: import_boundary_for(path))
        next unless target
        begin
          target_content = Noir::JSRouteExtractor.strip_js_comments(read_file_content(target))
        rescue
          next
        end
        found = extract_app_router_methods(target_content)
        found = methods_from_reexport(target, target_content, depth + 1) if found.empty?
        methods.concat(found)
      end
      methods.uniq
    end

    private def extract_pages_router_params(content : String, endpoint : Endpoint)
      # req.query.X and req.query["X"]
      content.scan(/req\.query\.(\w+)/) do |m|
        add_param(endpoint, m[1], "query")
      end
      content.scan(/req\.query\[['"]([^'"]+)['"]\]/) do |m|
        add_param(endpoint, m[1], "query")
      end

      # Destructured query: const { foo, bar } = req.query
      content.scan(/(?:const|let|var)\s*\{\s*([^}]+?)\s*\}\s*=\s*req\.query/) do |m|
        extract_simple_destructure_params(m[1]).each do |name|
          add_param(endpoint, name, "query")
        end
      end

      # req.body.X and req.body["X"]
      content.scan(/req\.body\.(\w+)/) do |m|
        add_param(endpoint, m[1], "body")
      end
      content.scan(/req\.body\[['"]([^'"]+)['"]\]/) do |m|
        add_param(endpoint, m[1], "body")
      end

      # Destructured body: const { foo, bar } = req.body
      content.scan(/(?:const|let|var)\s*\{\s*([^}]+?)\s*\}\s*=\s*req\.body/) do |m|
        extract_simple_destructure_params(m[1]).each do |name|
          add_param(endpoint, name, "body")
        end
      end

      # Headers — Pages Router (req object)
      content.scan(/req\.headers\[['"]([^'"]+)['"]\]/) do |m| # req.headers["x-token"]
        add_param(endpoint, m[1], "header")
      end
      content.scan(/req\.headers\[([A-Za-z_$]\w*)\]/) do |m| # req.headers[CONST] — unresolved
        add_unresolved_param(endpoint, m[1], "header")
      end
      content.scan(/req\.headers\.(\w+)/) do |m| # req.headers.authorization
        add_param(endpoint, m[1], "header")
      end

      # Cookies — Pages Router (req object)
      content.scan(/req\.cookies\[['"]([^'"]+)['"]\]/) do |m| # req.cookies["session"]
        add_param(endpoint, m[1], "cookie")
      end
      content.scan(/req\.cookies\[([A-Za-z_$]\w*)\]/) do |m| # req.cookies[CONST] — unresolved
        add_unresolved_param(endpoint, m[1], "cookie")
      end
      content.scan(/req\.cookies\.(\w+)/) do |m| # req.cookies.session
        add_param(endpoint, m[1], "cookie")
      end
    end

    private def extract_app_router_params(content : String, endpoint : Endpoint)
      # request.nextUrl.searchParams.get("X") or searchParams.get("X")
      content.scan(/(?:searchParams|nextUrl\.searchParams)\.(?:get|getAll|has)\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        add_param(endpoint, m[1], "query")
      end

      # await request.json() — body present; try to extract field access patterns
      if content.includes?("request.json()") || content.includes?(".json()")
        # Destructured: const { foo, bar } = await request.json()
        content.scan(/(?:const|let|var)\s*\{\s*([^}]+?)\s*\}\s*=\s*(?:await\s+)?(?:request|req)\.json\s*\(\s*\)/) do |m|
          extract_simple_destructure_params(m[1]).each do |name|
            add_param(endpoint, name, "json")
          end
        end

        # Aliased: const body = await request.json(); then body.X or body["X"]
        content.scan(/(?:const|let|var)\s+(\w+)\s*=\s*(?:await\s+)?(?:request|req)\.json\s*\(\s*\)/) do |m|
          varname = m[1]
          content.scan(cached_regex("nextjs:var_dot:#{varname}") { /\b#{Regex.escape(varname)}\.(\w+)/ }) do |mm|
            add_param(endpoint, mm[1], "json")
          end
          content.scan(cached_regex("nextjs:var_bracket:#{varname}") { /\b#{Regex.escape(varname)}\[['"]([^'"]+)['"]\]/ }) do |mm|
            add_param(endpoint, mm[1], "json")
          end
        end
      end

      # formData: const formData = await request.formData(); formData.get("name")
      if content.includes?("formData()")
        form_vars = ["formData"]
        content.scan(/(?:const|let|var)\s+(\w+)\s*=\s*(?:await\s+)?(?:request|req)\.formData\s*\(\s*\)/) do |m|
          form_vars << m[1] unless form_vars.includes?(m[1])
        end
        form_vars.each do |varname|
          content.scan(cached_regex("nextjs:var_get:#{varname}") { /\b#{Regex.escape(varname)}\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/ }) do |m|
            add_param(endpoint, m[1], "form")
          end
        end
      end

      # Headers — Web Request API (request/req object)
      content.scan(/(?:request|req)\.headers\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m| # .get("literal")
        add_param(endpoint, m[1], "header")
      end
      content.scan(/(?:request|req)\.headers\.get\s*\(\s*([A-Za-z_$]\w*)\s*\)/) do |m| # .get(CONST) — unresolved
        add_unresolved_param(endpoint, m[1], "header")
      end

      # Headers — Next.js server API: headers() from "next/headers"
      content.scan(/headers\(\)\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m| # .get("literal")
        add_param(endpoint, m[1], "header")
      end
      content.scan(/headers\(\)\.get\s*\(\s*([A-Za-z_$]\w*)\s*\)/) do |m| # .get(CONST) — unresolved
        add_unresolved_param(endpoint, m[1], "header")
      end

      # Cookies — Next.js server API: cookies() from "next/headers"
      content.scan(/cookies\(\)\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m| # .get("literal")
        add_param(endpoint, m[1], "cookie")
      end
      content.scan(/cookies\(\)\.get\s*\(\s*([A-Za-z_$]\w*)\s*\)/) do |m| # .get(CONST) — unresolved
        add_unresolved_param(endpoint, m[1], "cookie")
      end
      content.scan(/(?:const|let|var)\s+(\w+)\s*=\s*(?:await\s+)?cookies\s*\(\s*\)/) do |m|
        varname = m[1]
        content.scan(cached_regex("nextjs:var_get:#{varname}") { /\b#{Regex.escape(varname)}\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/ }) do |mm| # store.get("literal")
          add_param(endpoint, mm[1], "cookie")
        end
        content.scan(cached_regex("nextjs:var_get_ident:#{varname}") { /\b#{Regex.escape(varname)}\.get\s*\(\s*([A-Za-z_$]\w*)\s*\)/ }) do |mm| # store.get(CONST) — unresolved
          add_unresolved_param(endpoint, mm[1], "cookie")
        end
      end
    end

    private def extract_server_action_params(args : String, body : String, endpoint : Endpoint)
      # Scan the action body for .get("X") calls (formData.get / data.get, etc.) → form param
      body.scan(/\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        add_param(endpoint, m[1], "form")
      end

      # Extract only simple top-level identifier args (skip anything with {, <, =, ()
      split_top_level_commas(args).each do |arg|
        arg = arg.strip
        next if arg.empty?
        # Strip type annotation (everything after `:`)
        name_part = arg.split(":").first.strip
        # Skip destructures, generics, default values, nested calls
        next if name_part.includes?("{") || name_part.includes?("(") ||
                name_part.includes?("<") || name_part.includes?("=")
        next unless name_part.match(/^\w+$/)
        next if name_part == "formData"
        add_param(endpoint, name_part, "body")
      end
    end

    # Unlike every other JS/TS splitter this one has NO quote handling at all,
    # counts `<` `>` as nesting, and neither strips nor drops empty parts —
    # reproduced verbatim from the body it replaces.
    #
    # The two callers explain the shape: `exported_alias_for_method` passes the
    # inside of an `export { a, b as c }` clause and
    # `extract_server_action_params` passes a TypeScript parameter list, so
    # generics have to nest (`{ params }: { params: Promise<{ id: string }> }`)
    # but neither input can contain a string literal. Both strip each part and
    # skip the empties themselves.
    SPLIT_TOP_LEVEL_COMMAS_RULES = Noir::TopLevelSplit::Rules.new(
      nest: Noir::TopLevelSplit::Nest::Paren | Noir::TopLevelSplit::Nest::Bracket |
            Noir::TopLevelSplit::Nest::Brace | Noir::TopLevelSplit::Nest::Angle,
      quotes: "",
      escape: Noir::TopLevelSplit::Escape::None,
      strip: false,
      empties: Noir::TopLevelSplit::Empties::Keep,
      per_kind: false,
      clamp: true,
    )

    # Split a comma-separated string at top-level commas only (ignoring those inside
    # braces, brackets, parens, or angle brackets).
    private def split_top_level_commas(s : String) : Array(String)
      Noir::TopLevelSplit.split(s, ',', SPLIT_TOP_LEVEL_COMMAS_RULES)
    end

    # Extract only simple top-level identifiers from a flat destructure body.
    # Returns [] if the destructure contains nested structures, type annotations,
    # or default values (too complex to parse safely).
    private def extract_simple_destructure_params(destructure : String) : Array(String)
      return [] of String if destructure.includes?("{") || destructure.includes?("(") ||
                             destructure.includes?("<") || destructure.includes?("=") ||
                             destructure.includes?(":")
      destructure.split(",").map(&.strip).select(&.match(/^\w+$/))
    end

    private def extract_path_params(url : String, endpoint : Endpoint)
      url.scan(/\{(\w+)\}/) do |m|
        add_param(endpoint, m[1], "path")
      end
    end

    private def add_param(endpoint : Endpoint, name : String, type : String)
      return if name.empty?
      endpoint.push_param(Param.new(name, "", type))
    end

    private def add_unresolved_param(endpoint : Endpoint, name : String, type : String)
      return if name.empty?
      param = Param.new(name, "", type)
      param.add_tag(Tag.new("unresolved", "Key is a variable/constant identifier, not a string literal", "analyzer"))
      endpoint.push_param(param)
    end

    private def strip_extension(path : String) : String
      EXTENSIONS.each do |ext|
        return path[0..(path.size - ext.size - 1)] if path.ends_with?(ext)
      end
      path
    end

    private def convert_segments(relative : String) : String
      segments = relative.split("/").reject(&.empty?)
      segments.map { |seg| convert_segment(seg) }.join("/")
    end

    private def convert_segment(seg : String) : String
      # Optional catch-all: [[...slug]]
      if m = seg.match(/^\[\[\.\.\.(\w+)\]\]$/)
        return "{#{m[1]}}"
      end
      # Catch-all: [...slug]
      if m = seg.match(/^\[\.\.\.(\w+)\]$/)
        return "{#{m[1]}}"
      end
      # Dynamic: [id]
      if m = seg.match(/^\[(\w+)\]$/)
        return "{#{m[1]}}"
      end
      seg
    end

    private def has_use_server_directive?(content : String) : Bool
      stripped = content.lstrip
      # Skip leading comments
      while stripped.starts_with?("//") || stripped.starts_with?("/*")
        if stripped.starts_with?("//")
          newline = stripped.index('\n')
          return false if newline.nil?
          stripped = stripped[(newline + 1)..].lstrip
        else
          close = stripped.index("*/")
          return false if close.nil?
          stripped = stripped[(close + 2)..].lstrip
        end
      end
      stripped.starts_with?(%("use server")) || stripped.starts_with?(%('use server'))
    end

    private def normalize_url(url : String) : String
      url = url.gsub(/\/+/, "/")
      url = url.sub(/\/index$/, "")
      url = url.sub(/\/+$/, "") unless url == "/"
      url = "/" if url.empty?
      url
    end
  end
end
