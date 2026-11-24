require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../utils/js_literal_scanner"
require "../../../utils/top_level_split"
require "../../../miniparsers/js_route_extractor"
require "../../../miniparsers/js_handler_resolver"
require "../prefix_scope"
require "./js_middleware_access"

@[Noir::TaggerFor(key: "hono_auth", name: "Hono Auth Tagger", desc: "Identifies Hono authentication patterns (bearerAuth, jwt, basicAuth, custom middleware)", order: 250)]
class HonoAuthTagger < FrameworkTagger
  include PrefixScope

  # Hono official auth middleware
  HONO_AUTH_MIDDLEWARE = [
    {/\bbearerAuth\s*\(/, "Hono bearerAuth middleware"},
    {/\bjwt\s*\(/, "Hono jwt middleware"},
    {/\bbasicAuth\s*\(/, "Hono basicAuth middleware"},
  ]

  # Custom or third-party auth middleware names commonly used with Hono
  CUSTOM_AUTH_NAMES = [
    /\bauthMiddleware\b/i,
    /\bauthGuard\b/i,
    /\brequireAuth\b/i,
    /\bverifyToken\b/i,
    /\bcheckAuth\b/i,
    /\bensureAuth\b/i,
    /\bwithAuth\b/i,
  ]

  # Context user extraction after auth (secondary signal)
  CONTEXT_USER_PATTERNS = [
    /c\.var\.(user|payload|auth|session)/,
    /c\.get\s*\(\s*['"](user|payload|auth|session)/,
  ]

  # The start of a route registration: a window around one route stops here
  # so it never reads the neighbouring route's middleware or handler.
  ROUTE_DECLARATION = /\.\s*(?:get|post|put|patch|delete|options|head|all|on|use|route)\s*\(/

  def initialize(options : Hash(String, YAML::Any))
    super
    @use_auth_scopes = [] of {prefix: String, description: String}
    @uses = [] of HonoUse
  end

  # A `.use(...)` call: its file, receiver (empty when not a name), line,
  # literal path (nil when it has none or it is not a literal), its
  # middleware, and whether the receiver is a Hono app of that file.
  record HonoUse, file : String, receiver : String, line : Int32, path : String?, middleware : Array(String), hono : Bool

  # The verb call of a route: receiver, literal path, line, middleware.
  record RouteCall, receiver : String?, path : String?, line : Int32, middleware : Array(String)

  USE_ANY     = /\.\s*use\s*\(/
  HONO_IMPORT = /['"](?:hono|hono\/[\w-]+|@hono\/[\w-]+)['"]/
  HONO_APPS   = /(?<![\w$.])(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*(?::[^=]+)?=\s*new\s+(?:Hono|OpenAPIHono)\b/

  private def collect_uses(file : String)
    raw = read_file(file) || return
    return unless raw.matches?(USE_ANY)
    code = Noir::CComments.strip(raw, quotes: %("'`))
    # Another file's `use()` can reach this route only from a Hono app.
    apps = raw.matches?(HONO_IMPORT) ? code.scan(HONO_APPS).map(&.[1]).to_set.concat(%w[app router hono]) : Set(String).new
    expanded = Noir::PathScope.expand(file)
    code.scan(USE_ANY) do |m|
      close = Noir::JSLiteralScanner.find_matching_paren(code, m.end(0) - 1) || next
      receiver = code[0...m.begin(0)].match(/([A-Za-z_$][\w$]*)\s*\z/).try(&.[1]) || ""
      args = Noir::TopLevelSplit.split(code[m.end(0)...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).map(&.strip).reject(&.empty?)
      path = args.first?.try { |first| first.match(/\A['"`]([^'"`$]*)['"`]\z/).try(&.[1]) }
      args = args[1..] if path
      @uses << HonoUse.new(expanded, receiver, code[0...m.begin(0)].count('\n') + 1, path, args, apps.includes?(receiver))
    end
  end

  def self.target_techs : Array(String)
    ["js_hono"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    pre_scan_use_auth
    super
  end

  private def pre_scan_use_auth
    @use_auth_scopes.clear
    @uses.clear

    extensions = [".ts", ".js", ".tsx", ".jsx", ".mjs", ".cjs"]
    extensions.each do |ext|
      files = collect_files_by_extension(ext)
      files.each do |file|
        lines = read_file_lines(file)
        next if lines.nil?
        collect_uses(file)
        lines.each_with_index do |line, idx|
          next unless line.matches?(USE_CALL)
          stripped = use_statement(lines, idx)

          # Match app.use('/prefix', authMiddleware), app.use('/prefix/*', …)
          # and the app-wide app.use('*', …)
          if stripped =~ /(?:app|router|hono)\.use\s*\(\s*['"]([^'"]+)['"]\s*,/
            prefix = $1
            if has_auth_middleware_in_line?(use_middleware(stripped))
              @use_auth_scopes << {prefix: prefix, description: "Protected by Hono app.use() auth on #{prefix}"}
            end
          end

          # Global app.use(auth)
          if stripped =~ /(?:app|router|hono)\.use\s*\(\s*(?![\s'"])/
            if has_auth_middleware_in_line?(use_middleware(stripped))
              @use_auth_scopes << {prefix: "/", description: "Protected by Hono global auth middleware"}
            end
          end
        end
      end
    end
  end

  USE_CALL           = /(?:app|router|hono)\.use\s*\(/
  MAX_USE_CALL_LINES = 40

  # The `use(...)` call opened on line `idx`, read to its closing paren and
  # joined onto one line: the path and the middleware may sit on later lines.
  private def use_statement(lines : Array(String), idx : Int32) : String
    text = lines[idx, MAX_USE_CALL_LINES].join(' ')
    head = text.match(USE_CALL) || return lines[idx].strip
    close = Noir::JSLiteralScanner.find_matching_paren(text, head.end(0) - 1) || return lines[idx].strip
    text[head.begin(0)..close]
  end

  # The middleware arguments of a `use(...)` call, without the inline
  # functions: their body is what they do, not a middleware name
  # (`async (c, next) => { if (token) c.set('user', await verifyToken(token)) … }`).
  private def use_middleware(statement : String) : String
    head = statement.match(USE_CALL) || return statement
    close = Noir::JSLiteralScanner.find_matching_paren(statement, head.end(0) - 1) || return statement
    args = Noir::TopLevelSplit.split(statement[head.end(0)...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
    args.reject(&.matches?(Noir::JSRouteExtractor::INLINE_FUNCTION_RE)).join(", ")
  end

  private def has_auth_middleware_in_line?(line : String) : Bool
    HONO_AUTH_MIDDLEWARE.each do |pattern, _|
      return true if line.matches?(pattern)
    end
    CUSTOM_AUTH_NAMES.each do |pattern|
      return true if line.matches?(pattern)
    end
    false
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      if middleware = path_info.route_middleware
        if step = middleware.find { |candidate| middleware_description(code_only(candidate.source)) }
          description = middleware_description(code_only(step.source))
          requires = middleware.size == 1 && (read_file(step.file) || "").includes?(step.source) ? route_requires(endpoint, middleware_elements(step.source), step.file, nil) : nil
          endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "hono_auth", requires: requires))
          return
        end
        next
      end
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError.
      next if line_num < 1 || line_num > lines.size
      line_idx = line_num - 1

      # Check route definition + small surrounding window for chained middleware
      description = check_route_and_nearby(lines, line_idx)
      if description
        requires = route_call(lines, line_idx).try { |call| route_requires(endpoint, call.middleware, path_info.path, call) }
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "hono_auth", requires: requires))
        return
      end
    end

    return if endpoint.resolution.try(&.["registration"]?) == Endpoint::RESOLUTION_UNRESOLVED

    # Check prefix-based use() scopes
    description = check_use_scopes(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "hono_auth"))
      return
    end

    # Check for context user extraction in handler body (secondary)
    endpoint.details.code_paths.each do |path_info|
      next if path_info.route_middleware
      lines = read_file_lines(path_info.path)
      line_num = path_info.line
      next if lines.nil? || line_num.nil? || line_num < 1 || line_num > lines.size
      description = check_context_user(lines, line_num - 1)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by Hono auth (#{description})", "hono_auth"))
        return
      end
    end
  end

  MAX_ROUTE_CALL_LINES = 400
  ROUTE_VERB_CALL      = /\.\s*(?:get|post|put|patch|delete|options|head|all)\s*\(/

  # What the route's middleware and every `use()` that may cover it ask of
  # a caller, joined with AND. A `hono/*` guard imported in the file reads
  # as signed in; an auth-named one keeps the default reading; a known
  # middleware that refuses nobody, or a function that provably always
  # calls `next()`, adds nothing; anything else is unresolved. A `use()`
  # counts exactly only on the route's own receiver, above it in its file,
  # on a path that covers it: elsewhere it may or may not run first, so
  # each of its middleware that may refuse is one unresolved clause. Nil
  # unless something reads more exactly than the default.
  private def route_requires(endpoint : Endpoint, args : Array(String), file : String, route : RouteCall?) : Array(Access::Clause)?
    return if endpoint.details.code_paths.size > 1
    return if endpoint.resolution.try { |found| found.values.includes?(Endpoint::RESOLUTION_UNRESOLVED) }
    expanded = Noir::PathScope.expand(file)
    exact = false
    clauses = [] of Access::Clause
    args.each do |arg|
      cnf, read = middleware_reading(arg, file)
      next if cnf.empty?
      exact ||= read
      clauses.concat(Access.clauses(cnf, compact(arg), file))
    end
    @uses.each do |use|
      next unless use_covers?(use, endpoint.url, expanded, route)
      use_path = use.path
      attributable = route && use.file == expanded && use.receiver == route.receiver && use.line < route.line &&
                     (use_path.nil? || route.path.try { |own| path_covers?(use_path, own) })
      use.middleware.each do |arg|
        cnf, read = middleware_reading(arg, use.file)
        next if cnf.empty?
        cnf, read = JsMiddlewareAccess.unresolved(compact(arg)), false unless attributable
        exact ||= read
        clauses.concat(Access.clauses(cnf, compact(arg), use.file))
      end
    end
    return unless exact
    clauses.uniq!(&.any_of)
    clauses unless clauses.size > Access::MAX_CLAUSES
  end

  private def compact(text : String) : String
    text = text.gsub(/\s+/, " ").strip
    text.size > 120 ? "#{text[0, 117]}..." : text
  end

  # A `use()` in the route's file on any receiver, or on a Hono app
  # elsewhere, whose path is absent, unread or covers the route.
  private def use_covers?(use : HonoUse, url : String, file : String, route : RouteCall?) : Bool
    path = use.path
    return false unless use.file == file || use.hono
    return true if path.nil? || path_covers?(path, url)
    own = route.try(&.path)
    use.file == file && !own.nil? && path_covers?(path, own)
  end

  # Whether a Hono `use()` path may match `path`: `*`, a `/x/*` prefix, the
  # path itself, or a pattern this does not read (taken to match).
  private def path_covers?(pattern : String, path : String) : Bool
    return true if pattern.matches?(/[:{(]/) || pattern.in?("", "*", "/*")
    stem = pattern.rchop('*').rstrip('/')
    stem.empty? || path.rstrip('/') == stem || path.starts_with?("#{stem}/")
  end

  # The CNF one middleware contributes, and whether it was read exactly.
  private def middleware_reading(arg : String, file : String) : {Access::CNF, Bool}
    if reading = package_imports(file).try { |imports| JsMiddlewareAccess.parse(arg, imports).try { |call| JsMiddlewareAccess.read(call) } }
      return {reading, !reading.empty?}
    end
    return {JsMiddlewareAccess.fallback(compact(arg)), false} if middleware_description(code_only(arg))
    return {JsMiddlewareAccess::PASSES, false} if passes_through?(arg.strip, file)
    {JsMiddlewareAccess.unresolved(compact(arg)), false}
  end

  @package_imports = {} of String => JsMiddlewareAccess::Imports?

  # `file`'s package imports, a commented-out import or a name the module
  # declares itself left out.
  private def package_imports(file : String) : JsMiddlewareAccess::Imports?
    @package_imports.fetch(file) do
      @package_imports[file] = read_file(file).try do |raw|
        code = Noir::CComments.strip(raw, quotes: %("'`))
        JsMiddlewareAccess.package_imports(Noir::JSHandlerResolver.imports_of(code, file), code)
      end
    end
  end

  # Whether `text` is a function (inline, or a name defined in the scan)
  # that always calls `next()` and answers nothing.
  private def passes_through?(text : String, file : String) : Bool
    found = if text.matches?(/\A[A-Za-z_$][\w$]*\z/)
              content = read_file(file) || return false
              handler = Noir::JSHandlerResolver.resolve(text, content, file) || return false
              path, line = handler.path, handler.line
              return false unless path && line
              lines = read_file_lines(path) || return false
              return false unless 1 <= line <= lines.size
              JsMiddlewareAccess.function_parts(lines[line - 1, MAX_ROUTE_CALL_LINES].join('\n'), whole: false)
            else
              JsMiddlewareAccess.function_parts(text)
            end
    found ? JsMiddlewareAccess.hono_passes?(*found) : false
  end

  # `[a, b]` as its elements; anything else is one middleware.
  private def middleware_elements(source : String) : Array(String)
    text = Noir::CComments.strip(source, quotes: %("'`)).strip
    return [text] unless text.starts_with?('[') && Noir::JSLiteralScanner.find_matching_bracket(text, 0) == text.size - 1
    Noir::TopLevelSplit.split(text[1...-1], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).map(&.strip).reject(&.empty?)
  end

  # The verb call that opens the route statement at `line_idx`, with the
  # arguments between its path and its handler; nil when it cannot be read,
  # or when its line opens another route outside that call: which one this
  # endpoint is is not read.
  private def route_call(lines : Array(String), line_idx : Int32) : RouteCall?
    start = statement_start(lines, line_idx)
    text = Noir::CComments.strip(lines[start, MAX_ROUTE_CALL_LINES].join('\n'), quotes: %("'`))
    head = text.match(ROUTE_VERB_CALL) || return
    return if text[0, head.begin(0)].includes?('\n')
    close = Noir::JSLiteralScanner.find_matching_paren(text, head.end(0) - 1) || return
    outside = Noir::JSLiteralScanner.blank_literals(text[0, head.begin(0)] + text[close + 1..]).partition('\n')[0]
    return if outside.matches?(ROUTE_DECLARATION)
    args = Noir::TopLevelSplit.split(text[head.end(0)...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).map(&.strip).reject(&.empty?)
    receiver = text[0, head.begin(0)].match(/([A-Za-z_$][\w$]*)\s*\z/).try(&.[1])
    path = args.first?.try { |first| first.match(/\A['"`]([^'"`$]*)['"`]\z/).try(&.[1]) }
    RouteCall.new(receiver, path, start + 1, args.size >= 3 ? args[1...-1] : [] of String)
  end

  private def check_route_and_nearby(lines : Array(String), line_idx : Int32) : String?
    (statement_start(lines, line_idx)..line_idx).each do |i|
      # Code only: `summary: `x middleware: [authMiddleware]`` names no middleware.
      if description = middleware_description(code_only(lines[i]))
        return description
      end
    end
    nil
  end

  private def middleware_description(text : String) : String?
    HONO_AUTH_MIDDLEWARE.each do |pattern, desc|
      return desc if text.matches?(pattern)
    end

    CUSTOM_AUTH_NAMES.each do |pattern|
      next unless text.matches?(pattern)
      # Try to extract a nice name
      if m = text.match(/\b([a-zA-Z_]*[Aa]uth[a-zA-Z_]*)\b/)
        return "Hono #{m[1]} middleware"
      end
      return "custom Hono auth middleware"
    end
    nil
  end

  private def check_context_user(lines : Array(String), line_idx : Int32) : String?
    (line_idx..statement_end(lines, line_idx)).each do |i|
      current = lines[i]
      CONTEXT_USER_PATTERNS.each do |pattern|
        if current.matches?(pattern)
          return "context user extraction"
        end
      end
    end
    nil
  end

  # The route line plus up to 2 lines above it that are still open into it
  # (`app.get(` with the path on the next line, an options object) — never a
  # line above a route registration, and never a complete statement above.
  private def statement_start(lines : Array(String), line_idx : Int32) : Int32
    start = line_idx
    return start if lines[line_idx].matches?(ROUTE_DECLARATION)
    {line_idx - 1, line_idx - 2}.each do |i|
      break if i < 0 || open_brackets(lines[i]) <= 0
      start = i
      break if lines[i].matches?(ROUTE_DECLARATION)
    end
    start
  end

  # The last line of the statement opened on `line_idx` (its brackets
  # closed), at most 8 lines on: a one-line route ends on its own line.
  private def statement_end(lines : Array(String), line_idx : Int32) : Int32
    last = {line_idx + 8, lines.size - 1}.min
    depth = 0
    (line_idx..last).each do |i|
      depth += open_brackets(lines[i])
      return i if depth <= 0
    end
    last
  end

  private def open_brackets(line : String) : Int32
    code = code_only(line)
    code.count("({[") - code.count(")}]")
  end

  private def check_use_scopes(endpoint : Endpoint) : String?
    url = endpoint.url
    @use_auth_scopes.each do |scope|
      # A trailing Hono wildcard (`/admin/*`, `*`) is the prefix itself;
      # `*` alone is the root.
      return scope[:description] if prefix_covers?(scope[:prefix].rchop('*'), url)
    end
    nil
  end
end
