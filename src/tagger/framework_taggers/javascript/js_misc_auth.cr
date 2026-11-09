require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/js_handler_resolver"
require "../../../miniparsers/js_route_extractor"
require "../../../utils/js_literal_scanner"
require "../../../utils/top_level_split"
require "./js_object_literal"

@[Noir::TaggerFor(key: "js_misc_auth", name: "JS Misc Auth Tagger", desc: "Identifies Fastify/Koa/Restify authentication patterns", order: 160)]
class JsMiscAuthTagger < FrameworkTagger
  MAX_ROUTE_SCOPE_LINES = 12

  # Fastify auth patterns
  FASTIFY_PATTERNS = [
    {/onRequest.*authenticate/, "Fastify onRequest authenticate hook"},
    {/preHandler.*authenticate/, "Fastify preHandler authenticate"},
    {/fastify\.authenticate/, "Fastify authenticate decorator"},
    {/preValidation.*auth/i, "Fastify preValidation auth"},
    {/@fastify\/jwt/, "Fastify JWT plugin"},
    {/fastify-auth/, "Fastify auth plugin"},
    {/fastify\.auth\s*\(/, "Fastify auth"},
  ]

  # Koa auth patterns
  KOA_PATTERNS = [
    {/koa-passport/, "Koa Passport middleware"},
    {/koa-jwt/, "Koa JWT middleware"},
    {/koa-session/, "Koa session middleware"},
    {/passport\.authenticate\s*\(/, "Koa Passport authenticate"},
    {/ctx\.isAuthenticated\s*\(\)/, "Koa isAuthenticated check"},
  ]

  # Restify auth patterns
  RESTIFY_PATTERNS = [
    {/authorizationParser/, "Restify authorizationParser"},
    {/req\.authorization/, "Restify req.authorization check"},
    {/req\.username/, "Restify req.username check"},
  ]

  # `reply.code(401)` / `reply.status(401)` inside a hook or preHandler.
  FASTIFY_REPLY_401 = /reply\s*\.\s*(?:code|status)\s*\(\s*401\b|\.statusCode\s*=\s*401\b/
  # `if (!req.auth) throw new UnauthorizedError(...)`: Fastify answers a hook's
  # thrown error through the error handler, a 401 for these.
  FASTIFY_THROW_REFUSAL = /\bthrow\s+(?:new\s+)?\w*(?:Unauthori[sz]ed|Unauthenticated)\w*\s*\(/
  # `fastify.post<{ Body: T }>(`: TypeScript type arguments may sit before the `(`.
  FASTIFY_ROUTE  = /\.\s*(get|post|put|patch|delete|del|head|options|all|route)\s*(?:<[\s\S]*?>\s*)?\(/
  FASTIFY_EXEMPT = /if\s*\(\s*(?:request|req)\s*\.\s*(?:url|routerPath)\s*===?\s*['"]([^'"]+)['"]\s*\)\s*return\b/
  HOOK_KINDS     = %w[onRequest preHandler]

  # `exempt_keys`: route config keys whose routes the hook lets through
  # (`if (request.routeOptions.config.public) return`).
  record FastifyHook, file : String, start_line : Int32, end_line : Int32, kind : String, exempt : Array(String), exempt_keys : Array(String)

  # `request.jwtVerify()` (@fastify/jwt) throws a 401 for a missing or bad
  # token; a `catch` that neither replies nor rethrows lets the caller in.
  FASTIFY_JWT_VERIFY = /\.\s*jwtVerify\s*\(/
  FASTIFY_CATCH      = /\bcatch\b/
  FASTIFY_RETHROW    = /\breply\s*\.\s*(?:send|code|status)\s*\(|\bthrow\b/
  # `if (request.headers.authorization) await request.jwtVerify()`: verified
  # only when a credential is sent, so anonymous callers get through.
  FASTIFY_OPTIONAL_VERIFY = /\bif\s*\([^)]*(?:authorization|headers|token|cookie)/i
  # `!req.auth`, `!request.user`, `!token`: one negated read of a credential.
  FASTIFY_ABSENCE_TEST = /\A\s*!\s*[A-Za-z_$][\w$]*(?:\s*\??\.\s*[A-Za-z_$][\w$]*)*\s*\z/
  # The member the absence test reads last: `!req.auth`, `!req.session.user`.
  # A bare `!req.session` is not one: @fastify/session always sets it.
  FASTIFY_CREDENTIAL = /(?:\A\s*!\s*|\.)\s*(?:auth|user|userId|token|authorization|apiKey|apikey|identity|principal|jwt|credentials?)\s*\z/i
  # Any way out of the hook before the check: an anonymous caller may leave there.
  FASTIFY_EARLY_EXIT = /\breturn\b|\bdone\s*\(|\bnext\s*\(/
  # A request-flag early return: no credential word, no request target.
  # `req.shouldForwardWritesToPrimaryInstance && req.method !== "GET"`: one
  # app-declared request flag, optionally narrowed by the method, either order.
  FASTIFY_FLAG_BYPASS              = /\A\s*(req|request)\s*\.\s*([A-Za-z_$][\w$]*)\s*(?:&&\s*\1\s*\.\s*method\s*(===|!==|==|!=)\s*['"]([A-Za-z]+)['"]\s*)?\z/
  FASTIFY_FLAG_BYPASS_METHOD_FIRST = /\A\s*(req|request)\s*\.\s*method\s*(===|!==|==|!=)\s*['"]([A-Za-z]+)['"]\s*&&\s*\1\s*\.\s*([A-Za-z_$][\w$]*)\s*\z/
  # `decorateRequest("flag", false)`: a plain value, not a getter, a method
  # or an arrow, each of which computes the flag per request.
  FASTIFY_DECORATE_REQUEST    = /\.\s*decorateRequest\s*\(\s*['"]([A-Za-z_$][\w$]*)['"]\s*,\s*/
  FASTIFY_COMPUTED_DECORATION = /\A(?:\{\s*get(?:ter)?\b|(?:async\s+)?function\b|(?:async\s+)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>)/
  # Anything that can set a flag at request time makes it request input:
  # `x.flag = …` on any receiver, `setDecorator("flag", …)`, `r["flag"] = …`,
  # `Object.assign(r, { flag })`; `req[name] = …` could set any flag.
  FASTIFY_MEMBER_ASSIGN   = /\.\s*([A-Za-z_$][\w$]*)\s*(?:=(?![=>])|\|\|=|\?\?=|&&=)/
  FASTIFY_SET_DECORATOR   = /\bsetDecorator\s*\(\s*['"]([A-Za-z_$][\w$]*)['"]/
  FASTIFY_BRACKET_ASSIGN  = /\[\s*['"]([A-Za-z_$][\w$]*)['"]\s*\]\s*(?:=(?![=>])|\|\|=|\?\?=|&&=)/
  FASTIFY_COMPUTED_ASSIGN = /(?<![\w$.])(?:req|request)\s*\[\s*([A-Za-z_$][\w$.]*)\s*\]\s*(?:=(?![=>])|\|\|=|\?\?=|&&=)/
  FASTIFY_OBJECT_ASSIGN   = /\bObject\s*\.\s*assign\s*\(/
  # `key: value` or a shorthand `key` of the object literals assigned.
  OBJECT_ASSIGN_KEY   = /(?<![\w$.])([A-Za-z_$][\w$]*)\s*:(?!:)|[{,]\s*([A-Za-z_$][\w$]*)\s*(?=[,}])/
  FASTIFY_THROW_FIRST = /\Athrow\s+(?:new\s+)?\w*(?:Unauthori[sz]ed|Unauthenticated)\w*\s*\(/
  # `verifyAuth({ optional: true })`, `verifyModes(["anonymous", "jwt"])`: an
  # argument that can let a caller through.
  FASTIFY_OPENING_ARG = /\b(?:optional|anonymous|allowAnonymous|allowUnauthenticated|public|guest|skipAuth|bypass)\b/i
  # `fastify.auth([a, b])` is `relation: 'or'` unless it says `'and'`.
  FASTIFY_AUTH_STRATEGIES = /\.\s*auth\s*\(\s*\[/
  FASTIFY_RELATION_AND    = /\brelation\s*:\s*['"`]and['"`]/
  # `fastify.decorate('checkToken', async (request, reply) => { … })`.
  FASTIFY_DECORATE = /\.\s*decorate\s*\(\s*['"]([A-Za-z_$][\w$]*)['"]\s*,/

  # A hook that reads a key of the route's own config and refuses the routes
  # that set it: `if (req.routeOptions.config?.permissions?.length) { …
  # throw httpErrors.unauthorized() }`. Wiki.js gates its API this way.
  FASTIFY_GATE_HOOK    = /\.addHook\s*\(\s*['"](onRequest|preParsing|preValidation|preHandler)['"]/
  FASTIFY_CONFIG_READ  = /\b(?:routeOptions\s*\.\s*config|routeConfig|context\s*\.\s*config)\s*\??\.\s*([A-Za-z_$][\w$]*)/
  FASTIFY_GATE_REFUSAL = /\bunauthorized\s*\(|\b(?:code|status)\s*\(\s*401\b|\bstatusCode\s*=\s*401\b/
  # A config value that sets nothing.
  FASTIFY_EMPTY_VALUE = /\A(?:\[\s*\]|false|null|undefined|0|''|""|``)\z/

  # `key` of the route config, read by a refusing hook in the project at
  # `root`. A hook inside a `register` callback covers only the routes of
  # that callback: `file` and its line range.
  record FastifyConfigGate, root : String, key : String, kind : String, file : String?, start_line : Int32, end_line : Int32
  # `if (perms === 0)`, `if (perms.length < 1)`: a test of the key's absence.
  # `typeof perms === 'undefined'`, `Array.isArray(perms) === false` too.
  FASTIFY_ABSENT_TEST = /\A[\w$?.]*\s*\)?\s*(?:===?\s*(?:(?:0|null|undefined|false)\b|['"]undefined['"])|<\s*1\b)/
  # A file that makes the root instance (`Fastify()`, `require('fastify')()`):
  # its hooks reach past the file. Matched on comment-stripped text.
  FASTIFY_ROOT_FILE = /\bFastify\s*\(|\bfastify\s*\(\s*[{)]|require\s*\(\s*['"]fastify['"]\s*\)\s*\(/
  # `fp(async (app) => …)`, `fastifyPlugin(plugin)`: a plugin whose hooks
  # reach its parent. Group 1 the wrapped function's name, when named.
  FASTIFY_PLUGIN_WRAP = /\b(?:fp|fastifyPlugin)\s*\(\s*(?:([A-Za-z_$][\w$]*)\s*[,)])?/
  # Lines a route call is read across before it is given up on.
  MAX_FASTIFY_ROUTE_LINES = 1280

  # Generic Node.js auth middleware (shared across frameworks)
  GENERIC_NODE_AUTH = [
    {/\brequireAuth\b/, "requireAuth middleware"},
    {/\bisAuthenticated\b/, "isAuthenticated middleware"},
    {/\bensureLoggedIn\b/, "ensureLoggedIn middleware"},
    {/\bverifyToken\b/, "verifyToken middleware"},
    {/\bcheckAuth\b/, "checkAuth middleware"},
    {/\bauthMiddleware\b/, "authMiddleware"},
  ]

  def self.target_techs : Array(String)
    ["js_fastify", "js_koa", "js_restify", "js_nuxtjs"]
  end

  def initialize(options : Hash(String, YAML::Any))
    super
    @fastify_hooks = [] of FastifyHook
    @fastify_decorators = {} of {String?, String} => Array(Bool)
    @fastify_config_gates = [] of FastifyConfigGate
    @package_roots = {} of String => String?
    @fastify_bypassed = false
    @fastify_method = ""
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @fastify_decorators = scan_fastify_decorators
    @fastify_hooks = scan_fastify_hooks
    @fastify_config_gates = scan_fastify_config_gates
    super
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      line_idx = line_num - 1

      # Check the route statement/block itself so nearby auth hooks from
      # previous routes do not bleed into public handlers.
      description = check_route_scope(route_scope(lines, line_idx))
      if description.nil? && endpoint.details.technology == "js_fastify"
        description = fastify_route_guard(path_info.path, line_idx, endpoint.method, endpoint.url) ||
                      fastify_plugin_hook(path_info.path, line_num, endpoint.method, endpoint.url) ||
                      fastify_config_gate(path_info.path, line_idx, endpoint.method, endpoint.url)
      end
      description ||= koa_guard(path_info.path, line_idx) if endpoint.details.technology == "js_koa"
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "js_misc_auth"))
        return
      end
    end
  end

  # What a Koa middleware's definition does to refuse a caller: throw
  # (`ctx.throw(401)`, `throw AuthenticationError(…)`), assert, or set 401/403.
  KOA_REFUSAL    = /\bctx\.throw\s*\(\s*40[13]\b|\bctx\.status\s*=\s*40[13]\b|\bctx\.assert\s*\([^;]*?,\s*40[13]\b|\bthrow\s+(?:new\s+)?\w*(?:Unauthori[sz]ed|Forbidden|Authentication|Authorization)\w*\s*\(/
  KOA_ROUTE_CALL = /\.\s*(?:get|post|put|patch|delete|del|all|head|options)\s*\(/
  # `auth`, `auth()`, `mw.requireUser({ … })`: the reference and its arguments.
  KOA_MIDDLEWARE_CALL = /\A((?:[A-Za-z_$][\w$]*\s*\.\s*)?[A-Za-z_$][\w$]*)\s*(?:\((.*)\))?\z/m
  # An option that can switch a check off: `optional: true`, `skip: (ctx) => …`.
  KOA_DISABLING_OPTION = /\b([A-Za-z_$][\w$]*)\s*:\s*(?:true\b|(?:async\s+)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>|function\b)/
  KOA_CALLEE           = /\b([A-Za-z_$][\w$]*)\s*\(/
  KOA_NOT_CALLEES      = Set{"if", "for", "while", "switch", "catch", "function", "return", "await", "typeof", "next"}
  MAX_KOA_ARG_LINES    = 80
  MAX_KOA_HELPERS      = 12

  # A middleware argument of the Koa route at `line_idx` whose definition
  # refuses the caller (itself, or one same-module helper it calls), unless
  # the call passes an option the definition branches on to let the caller
  # through (`auth({ optional: true })`). The last argument is the handler.
  # Middleware a `router.use(...)` earlier in the file adds to the same
  # router counts too: koa-router runs it before each later route of that
  # router, or of those under its path when it names one.
  private def koa_guard(path : String, line_idx : Int32) : String?
    lines = read_file_lines(path) || return
    route = route_call(lines, line_idx, KOA_ROUTE_CALL) || return
    receiver, args = route
    content = read_file(path) || return
    if args.size >= 3
      args[1...-1].each do |arg|
        desc = koa_middleware_guard(arg, content, path)
        return desc if desc
      end
    end
    return unless receiver
    route_path = args[0]?.try(&.strip.match(/\A['"`]([^'"`]*)['"`]\z/).try(&.[1]))
    use_call = /(?<![\w$.])#{Regex.escape(receiver)}\s*\.\s*use\s*\(/
    # Back to where this router is declared: a same-named router in another
    # function is a different one.
    declared = /\b(?:const|let|var)\s+#{Regex.escape(receiver)}\s*=/
    (line_idx - 1).downto(0) do |idx|
      break if lines[idx].matches?(declared)
      next unless lines[idx].matches?(use_call)
      use = route_call(lines, idx, use_call) || next
      middleware = use[1]
      first = middleware.first?.try(&.strip) || ""
      # A path, or a list of them (`['/admin', '/ops']`), scopes the use.
      if first.matches?(/\A(?:['"`]|\[)/)
        scopes = first.scan(/['"`]([^'"`]*)['"`]/).map(&.[1].rchop('/'))
        next unless route_path && scopes.any? { |prefix| prefix.empty? || route_path == prefix || route_path.starts_with?("#{prefix}/") }
        middleware = middleware[1..]
      end
      middleware.each do |arg|
        desc = koa_middleware_guard(arg, content, path)
        return desc if desc
      end
    end
    nil
  rescue
    nil
  end

  # The receiver and top-level arguments of the call `call_re` matches on
  # line `line_idx`, read to its closing paren however long the handler
  # runs: a cut-off slice used to lose the whole call.
  private def route_call(lines : Array(String), line_idx : Int32, call_re : Regex) : {String?, Array(String)}?
    span = MAX_KOA_ARG_LINES
    loop do
      statement = Noir::CComments.strip(lines[line_idx, span].join("\n"), quotes: %("'`))
      head = statement.match(call_re) || return
      # A call commented out on this line must not borrow a later one.
      return if statement[0, head.begin(0)].includes?('\n')
      open_paren = head.end(0) - 1
      if close_paren = Noir::JSLiteralScanner.find_matching_paren(statement, open_paren)
        receiver = statement[0...head.begin(0)].match(/([A-Za-z_$][\w$]*)\s*\z/).try(&.[1])
        args = Noir::TopLevelSplit.split(statement[open_paren + 1...close_paren], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
        return {receiver, args}
      end
      return if line_idx + span >= lines.size
      span *= 4
    end
  end

  private def koa_middleware_guard(arg : String, content : String, path : String) : String?
    call = arg.strip.match(KOA_MIDDLEWARE_CALL) || return
    handler = Noir::JSHandlerResolver.resolve(call[1], content, path) || return
    evidence = refusal_in_definition(handler) || return
    options = call[2]? || ""
    body = koa_definition_body(handler) || return
    return if options.scan(KOA_DISABLING_OPTION).any? { |m| body.matches?(/\bif\s*\([^)]*\b#{Regex.escape(m[1])}\b/) }
    evidence = evidence.gsub(/\s+/, " ").chomp('(')
    evidence += ")" * (evidence.count('(') - evidence.count(')')).clamp(0, 3)
    "Koa #{call[1].gsub(/\s+/, "")} middleware (#{evidence})"
  end

  private def koa_definition_body(handler : Handler) : String?
    path = handler.path || return
    line = handler.line || return
    content = read_file(path) || return
    Noir::JSRouteExtractor.definition_body(Noir::JSRouteExtractor.strip_js_comments(content), line)
  end

  private def refusal_in_definition(handler : Handler) : String?
    body = koa_definition_body(handler) || return
    if refusal = body.match(KOA_REFUSAL)
      return refusal[0]
    end
    path = handler.path || return
    content = read_file(path) || return
    body.scan(KOA_CALLEE).map(&.[1]).uniq!.reject { |n| KOA_NOT_CALLEES.includes?(n) }.first(MAX_KOA_HELPERS).each do |name|
      helper = Noir::JSHandlerResolver.resolve(name, content, path) || next
      next unless helper.path == path
      helper_body = koa_definition_body(helper) || next
      if refusal = helper_body.match(KOA_REFUSAL)
        return refusal[0]
      end
    end
    nil
  end

  private def check_route_scope(scope : Array(String)) : String?
    # Reading `ctx.state.user` is no check; refusing when it is missing is.
    text = scope.join('\n')
    return "Koa ctx.state.user check" if text.matches?(/\bctx\.state\.user\b/) && text.matches?(KOA_REFUSAL)
    all_patterns = FASTIFY_PATTERNS + KOA_PATTERNS + RESTIFY_PATTERNS + GENERIC_NODE_AUTH
    scope.each do |current|
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
    end
    nil
  end

  private def route_scope(lines : Array(String), line_idx : Int32) : Array(String)
    return [] of String if line_idx < 0 || line_idx >= lines.size

    selected = [] of String
    brace_depth = 0
    paren_balance = 0
    seen_block = false

    line_idx.upto(Math.min(line_idx + MAX_ROUTE_SCOPE_LINES - 1, lines.size - 1)) do |idx|
      raw_line = lines[idx]
      selected << raw_line

      sanitized = raw_line.gsub(/(['"]).*?\1/, "\"\"")
      opens = sanitized.count('{')
      closes = sanitized.count('}')
      brace_depth += opens - closes
      paren_balance += sanitized.count('(') - sanitized.count(')')
      seen_block ||= opens > 0

      if seen_block
        break if brace_depth <= 0
      else
        stripped = sanitized.strip
        statement_done = stripped.ends_with?(";") || stripped.ends_with?(")")
        break if statement_done && paren_balance <= 0
      end
    end

    selected
  end

  # `addHook('onRequest'|'preHandler', ...)` inside a `register` callback
  # guards the routes registered in that callback. A hook that returns
  # early for one URL leaves that URL alone. The body has to refuse;
  # the name `authenticate` is not enough here (the route-scope pass
  # above already keeps that name).
  private def scan_fastify_hooks : Array(FastifyHook)
    rules = [] of FastifyHook
    %w[.js .mjs .cjs .ts .mts .cts].each do |ext|
      collect_files_by_extension(ext).each do |file|
        raw = read_file(file) || next
        next unless raw.includes?("addHook")
        text = Noir::CComments.strip(raw, quotes: %("'`))
        registers = fastify_register_ranges(text)
        text.scan(/\.addHook\s*\(\s*['"](onRequest|preHandler)['"]/) do |m|
          next unless HOOK_KINDS.includes?(m[1])
          open = text.index('(', m.begin(0)) || next
          close = Noir::JSLiteralScanner.find_matching_paren(text, open) || next
          args = Noir::TopLevelSplit.split(text[open + 1...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
          callback = args[1]? || next
          # Refusing by what the route's config sets is per route, not every
          # route in range: `scan_fastify_config_gates` reads those.
          # Its gated `if`s are left out: what is left refuses every route.
          gate_keys, exempt_keys, rest = fastify_config_keys(callback)
          next unless fastify_refuses?(gate_keys.empty? ? callback : rest, text, file)
          hook_line = text[0...m.begin(0)].count('\n') + 1
          range = fastify_innermost(registers, hook_line) || {1, text.count('\n') + 1}
          exempt = callback.scan(FASTIFY_EXEMPT).map(&.[1])
          rules << FastifyHook.new(Noir::PathScope.expand(file), range[0], range[1], m[1], exempt, exempt_keys)
        end
      end
    end
    rules
  end

  # Every `decorate('name', fn)` in the scan, keyed by its package: whether
  # each definition of `name` refuses a caller. A name decorated by two
  # services is a guard only when every definition refuses.
  private def scan_fastify_decorators : Hash({String?, String}, Array(Bool))
    found = {} of {String?, String} => Array(Bool)
    %w[.js .mjs .cjs .ts .mts .cts].each do |ext|
      collect_files_by_extension(ext).each do |file|
        raw = read_file(file) || next
        next unless raw.includes?("decorate")
        text = Noir::CComments.strip(raw, quotes: %("'`))
        text.scan(FASTIFY_DECORATE) do |m|
          open = text.index('(', m.begin(0)) || next
          close = Noir::JSLiteralScanner.find_matching_paren(text, open) || next
          args = Noir::TopLevelSplit.split(text[open + 1...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
          value = args[1]? || next
          (found[{package_root(file), m[1]}] ||= [] of Bool) << fastify_refuses?(value, text, file, decorators: false)
        end
      end
    end
    found
  end

  private def fastify_register_ranges(text : String) : Array({Int32, Int32})
    ranges = [] of {Int32, Int32}
    text.scan(/\.register\s*\(/) do |m|
      open = m.end(0) - 1
      close = Noir::JSLiteralScanner.find_matching_paren(text, open) || next
      spans = Noir::TopLevelSplit.split_spans(text, ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS, open + 1, close)
      callback, pos = spans.find { |part, _| !part.blank? } || next
      brace = callback.index('{') || next
      abs = pos + brace
      end_brace = Noir::JSLiteralScanner.find_matching_brace(text, abs) || next
      ranges << {text[0...abs].count('\n') + 1, text[0..end_brace].count('\n') + 1}
    end
    ranges
  end

  private def fastify_innermost(ranges : Array({Int32, Int32}), line : Int32) : {Int32, Int32}?
    ranges.select { |span| span[0] <= line && line <= span[1] }.min_by? { |span| span[1] - span[0] }
  end

  private def fastify_refuses?(expr : String, content : String, file : String, decorators : Bool = true, throws : Bool = false) : Bool
    return true if fastify_refusal_body?(expr)
    # `fastify.checkToken`: a decorated function, judged by its definition.
    if member = expr.strip.match(/\A[A-Za-z_$][\w$]*\s*\.\s*([A-Za-z_$][\w$]*)\z/)
      if decorators && (verdicts = @fastify_decorators[{package_root(file), member[1]}]?)
        return verdicts.all?
      end
      expr = member[1]
    end
    name = expr.strip.match(/\A([A-Za-z_$][\w$]*)\z/).try(&.[1]) || return false
    handler = Noir::JSHandlerResolver.resolve(name, content, file) || return false
    path = handler.path || return false
    line = handler.line || return false
    source = read_file(path) || return false
    body = Noir::JSRouteExtractor.definition_body(Noir::CComments.strip(source, quotes: %("'`)), line)
    return true if fastify_refusal_body?(body)
    return false unless throws
    case fastify_throw_guard?(body)
    when :guard  then true
    when :bypass then @fastify_bypassed = true
    else              false
    end
  end

  # A route hook that refuses by throwing, in exactly this shape: at the top
  # level of the hook's body, `if (!req.auth) throw new UnauthorizedError(…)`
  # (or the throw alone in that `if`'s block), the condition one negated
  # credential read with no `&&`/`||`, and no `return`, `done()` or
  # `next()` anywhere before it. Optional-identity hooks (`if (!token)
  # return done()` first), presence tests and guest-only checks do not
  # match, and fall back to the reply/jwtVerify reading. Plugin `addHook`s
  # never take this path.
  # Verdict for `@fastify_method`: :guard, :bypass (guarded, but a declared
  # request flag can wave the caller through) or nil.
  private def fastify_throw_guard?(body : String) : Symbol?
    raw = body
    # Literals blanked byte for byte, so offsets index `raw` too.
    body = Noir::JSLiteralScanner.blank_literals(body)
    return unless body.matches?(FASTIFY_THROW_REFUSAL)
    bytes = body.to_slice
    # Top-level `if`s before the check whose early exits are flag bypasses:
    # byte span, and whether the bypass can apply to this route's method.
    bypasses = [] of {Int32, Int32, Bool}
    depth = 0
    idx = 0
    while idx < bytes.size
      case bytes[idx]
      when '{'.ord, '('.ord, '['.ord then depth += 1
      when '}'.ord, ')'.ord, ']'.ord then depth -= 1
      when 'i'.ord
        if depth == 0 && (head = body.byte_slice(idx, {body.bytesize - idx, 8}.min).match(/\Aif\s*\(/)) &&
           (idx == 0 || !identifier_byte?(bytes[idx - 1]))
          open = idx + head.byte_end(0) - 1
          close = Noir::JSLiteralScanner.find_matching_paren_at_byte(body, open) || return
          cond = body.byte_slice(open + 1, close - open - 1)
          if cond.matches?(FASTIFY_ABSENCE_TEST) && cond.matches?(FASTIFY_CREDENTIAL)
            consequent = body.byte_slice(close + 1, {body.bytesize - close - 1, 400}.min).lstrip
            consequent = consequent.lchop('{').lstrip if consequent.starts_with?('{')
            if consequent.matches?(FASTIFY_THROW_FIRST)
              exits = [] of Int32
              body.byte_slice(0, idx).scan(FASTIFY_EARLY_EXIT) { |m| exits << m.byte_begin(0) }
              return :guard if exits.empty?
              spans = exits.map { |at| bypasses.find { |from, to, _| from <= at < to } }
              return if spans.any?(Nil)
              return spans.any? { |span| span.try(&.[2]) } ? :bypass : :guard
            end
          end
          if applies = flag_bypass_applies(raw.byte_slice(open + 1, close - open - 1))
            bypasses << {close + 1, consequent_end(body, close + 1), applies == :yes}
          end
          idx = close
        end
      end
      idx += 1
    end
    nil
  end

  # An early-return condition reading one request flag the app declares
  # (`decorateRequest("name", …)`) and nothing assigns (`req.name = …`),
  # optionally `&& req.method !== "GET"`. :yes when it can apply to the
  # route's method, :no when the method rules it out, nil for any other
  # condition (the check then counts as not reached).
  private def flag_bypass_applies(raw_cond : String) : Symbol?
    if m = raw_cond.match(FASTIFY_FLAG_BYPASS)
      flag, op, verb = m[2], m[3]?, m[4]?
    elsif m = raw_cond.match(FASTIFY_FLAG_BYPASS_METHOD_FIRST)
      flag, op, verb = m[4], m[2], m[3]
    else
      return
    end
    return if flag == "method"
    declared, assigned = fastify_request_flags
    return if !declared.includes?(flag) || assigned.includes?(flag) || assigned.includes?("*")
    return :yes unless op && verb
    same = @fastify_method == verb.upcase
    applies = op.starts_with?('!') ? !same : same
    applies ? :yes : :no
  end

  # Request decorations declared in the project, and request members any
  # code assigns. Read once per run, on first need.
  @fastify_request_flags : {Set(String), Set(String)}?

  private def fastify_request_flags : {Set(String), Set(String)}
    @fastify_request_flags ||= begin
      declared = Set(String).new
      assigned = Set(String).new
      %w[.js .mjs .cjs .ts .mts .cts].each do |ext|
        collect_files_by_extension(ext).each do |file|
          text = read_file(file) || next
          if text.includes?("decorateRequest")
            text.scan(FASTIFY_DECORATE_REQUEST) do |m|
              value = text.byte_slice(m.byte_end(0), {text.bytesize - m.byte_end(0), 64}.min)
              declared << m[1] unless value.matches?(FASTIFY_COMPUTED_DECORATION)
            end
          end
          text.scan(FASTIFY_MEMBER_ASSIGN) { |m| assigned << m[1] }
          text.scan(FASTIFY_SET_DECORATOR) { |m| assigned << m[1] } if text.includes?("setDecorator")
          if text.includes?('[')
            text.scan(FASTIFY_BRACKET_ASSIGN) { |m| assigned << m[1] }
            # `const name = "skipC"; request[name] = …` sets that flag; a key
            # this file does not spell out could be any flag.
            text.scan(FASTIFY_COMPUTED_ASSIGN) do |m|
              key = text.match(/\b(?:const|let|var)\s+#{Regex.escape(m[1])}\s*=\s*['"]([A-Za-z_$][\w$]*)['"]/).try(&.[1])
              assigned << (key || "*")
            end
          end
          if text.includes?("assign")
            text.scan(FASTIFY_OBJECT_ASSIGN) do |m|
              args = Noir::JSLiteralScanner.extract_paren_content_at_byte(text, m.byte_end(0)).try(&.content) || next
              args.scan(OBJECT_ASSIGN_KEY) { |k| assigned << (k[1]? || k[2]) }
            end
          end
        end
      end
      {declared, assigned}
    end
  end

  # End (exclusive) of the statement or block that starts at `from`.
  private def consequent_end(body : String, from : Int32) : Int32
    bytes = body.to_slice
    pos = from
    while pos < bytes.size && bytes[pos].unsafe_chr.ascii_whitespace?
      pos += 1
    end
    if pos < bytes.size && bytes[pos] == '{'.ord
      close = Noir::JSLiteralScanner.find_matching_brace_at_byte(body, pos)
      return close ? close + 1 : body.bytesize
    end
    body.byte_index(';', pos).try(&.+(1)) || body.byte_index('\n', pos) || body.bytesize
  end

  # Set by `fastify_refuses?` when the check it credited sits behind a
  # request-flag early return.
  private def bypass_note : String
    @fastify_bypassed ? " (a request-flag early return can bypass it)" : ""
  end

  private def identifier_byte?(byte : UInt8) : Bool
    byte.unsafe_chr.ascii_alphanumeric? || byte == '_'.ord || byte == '$'.ord
  end

  private def fastify_refusal_body?(body : String) : Bool
    body = code_only(body)
    return true if body.matches?(FASTIFY_REPLY_401)
    return false unless at = body.index(FASTIFY_JWT_VERIFY)
    return false if body[0...at].matches?(FASTIFY_OPTIONAL_VERIFY)
    caught = body.index(FASTIFY_CATCH, at) || return true
    open = body.index('{', caught) || return false
    close = Noir::JSLiteralScanner.find_matching_brace(body, open) || return false
    body[open..close].matches?(FASTIFY_RETHROW)
  end

  private def fastify_plugin_hook(path : String, line : Int32, method : String, url : String) : String?
    expanded = Noir::PathScope.expand(path)
    @fastify_hooks.each do |hook|
      next unless hook.file == expanded && hook.start_line <= line && line <= hook.end_line
      next if hook.exempt.any? { |exempt| exempt == url || exempt.rstrip('/') == url.rstrip('/') }
      next if hook.exempt_keys.any? { |key| fastify_route_config(path, line - 1, method, url, key) }
      return "Fastify #{hook.kind} hook"
    end
    nil
  end

  # A route option `preHandler: requireUser` or an inline preHandler that
  # replies 401. A preHandler that does not refuse (an admin check that
  # only calls `next`) is not a guard.
  private def fastify_route_guard(path : String, line_idx : Int32, method : String, url : String) : String?
    args = fastify_route_args(path, line_idx, method, url) || return
    @fastify_method = method.upcase
    content = read_file(path) || return
    HOOK_KINDS.each do |key|
      args.each do |arg|
        next unless arg.lstrip.starts_with?('{')
        expr = Noir::JSObjectLiteral.property(arg, key) || next
        if fastify_refusal_body?(expr)
          return "Fastify #{key}"
        end
        # A throw counts only from a hook called with nothing that opens it.
        throws = !code_only(expr).matches?(FASTIFY_OPENING_ARG) && !expr.matches?(FASTIFY_OPENING_ARG)
        if expr.matches?(FASTIFY_AUTH_STRATEGIES) && !expr.matches?(FASTIFY_RELATION_AND)
          # Every strategy has to refuse, or one of them lets the caller in.
          strategies = expr.match(/\[([^\[\]]*)\]/).try(&.[1].split(',').map(&.strip).reject(&.empty?)) || next
          next if strategies.empty?
          @fastify_bypassed = false
          next unless strategies.all? { |strategy| fastify_refuses?(strategy, content, path, throws: throws) }
          return "Fastify #{key} #{strategies.join(", ")}#{bypass_note}"
        end
        expr.scan(/(?:\b[A-Za-z_$][\w$]*\s*\.\s*)?\b([A-Za-z_$][\w$]*)\b/) do |ident|
          name = ident[1]
          next if {"async", "await", "function", "return", "request", "reply", "req", "res", "true", "false", "null"}.includes?(name)
          @fastify_bypassed = false
          next unless fastify_refuses?(ident[0], content, path, throws: throws)
          return "Fastify #{key} #{name}#{bypass_note}"
        end
      end
    end
    nil
  end

  # The arguments of the route call on line `line_idx`, read to its closing
  # paren however long its schema runs. With several calls on that line
  # (`a.get('/a', h); a.post('/a', {…}, h)`), the best match wins: verb
  # first, then a path literal equal to `url`, then one `url` ends with
  # (under a prefix), then the first call.
  @fastify_route_args = {} of {String, Int32, String, String} => Array(String)?

  private def fastify_route_args(path : String, line_idx : Int32, method : String, url : String) : Array(String)?
    key = {path, line_idx, method, url}
    return @fastify_route_args[key] if @fastify_route_args.has_key?(key)
    @fastify_route_args[key] = read_fastify_route_args(path, line_idx, method, url)
  end

  private def read_fastify_route_args(path : String, line_idx : Int32, method : String, url : String) : Array(String)?
    lines = read_file_lines(path) || return
    return if line_idx < 0 || line_idx >= lines.size
    span = MAX_KOA_ARG_LINES
    loop do
      text = Noir::CComments.strip(lines[line_idx, span].join('\n'), quotes: %("'`))
      first_line_end = text.index('\n') || text.size
      # Byte for byte, so a head inside a string (`log('.get(')`) is told apart.
      code = Noir::JSLiteralScanner.blank_literals(text[0, first_line_end]).to_slice
      best = nil
      best_score = -1
      cut = false
      pos = 0
      while (head = text.match(FASTIFY_ROUTE, pos)) && head.begin(0) < first_line_end
        open = head.end(0) - 1
        # A head inside a string is skipped, past its own `(`.
        if code[head.byte_begin(0)]? == 0x20_u8
          pos = head.end(0)
        else
          unless close = Noir::JSLiteralScanner.find_matching_paren(text, open)
            cut = true
            break
          end
          args = Noir::TopLevelSplit.split(text[open + 1...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
          verb = head[1].downcase
          score = verb == "all" || verb == method.downcase || (verb == "del" && method == "DELETE") ? 4 : 0
          literal = args.first?.try(&.strip)
          # `route({ method: ["GET", "POST"], url: "/x", onRequest })`.
          if verb == "route" && literal
            score = 4 if Noir::JSObjectLiteral.property(literal, "method").try(&.scan(/['"`]([A-Za-z]+)['"`]/).any? { |m| m[1].upcase == method })
            literal = Noir::JSObjectLiteral.property(literal, "url") || Noir::JSObjectLiteral.property(literal, "path")
          end
          if literal && literal.size >= 2 && {'\'', '"', '`'}.includes?(literal[0]) && literal[-1] == literal[0]
            route = literal[1...-1]
            score += route == url ? 2 : (url.ends_with?(route) ? 1 : 0)
          end
          best, best_score = args, score if score > best_score
          pos = close + 1
        end
      end
      return best if best || !cut || line_idx + span >= lines.size || span >= MAX_FASTIFY_ROUTE_LINES
      span *= 4
    end
  end

  # Hooks whose refusal sits in a block entered only when the route's config
  # sets a key: `if (perms && perms.length > 0) { … unauthorized() }` after
  # `const perms = req.routeOptions.config?.permissions`. A test of the key's
  # absence (`if (!config.public)`) opens the routes that set it instead, so
  # it is not read as a gate.
  private def scan_fastify_config_gates : Array(FastifyConfigGate)
    gates = [] of FastifyConfigGate
    %w[.js .mjs .cjs .ts .mts .cts].each do |ext|
      collect_files_by_extension(ext).each do |file|
        raw = read_file(file) || next
        next unless raw.includes?("addHook") && raw.includes?("config")
        root = package_root(file) || next
        text = Noir::CComments.strip(raw, quotes: %("'`))
        registers = fastify_register_ranges(text)
        # Outside a `register` callback, a hook reaches past its file only from
        # the root instance or a fastify-plugin; any other plugin is encapsulated.
        file_wide = text.matches?(FASTIFY_ROOT_FILE) ? nil : {1, text.count('\n') + 1}
        wrapped = fastify_plugin_spans(text)
        text.scan(FASTIFY_GATE_HOOK) do |m|
          open = text.index('(', m.begin(0)) || next
          close = Noir::JSLiteralScanner.find_matching_paren(text, open) || next
          callback = Noir::TopLevelSplit.split(text[open + 1...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)[1]? || next
          fastify_config_keys(callback)[0].each do |key|
            range = fastify_innermost(registers, text[0...m.begin(0)].count('\n') + 1)
            range ||= file_wide unless wrapped.any?(&.includes?(m.begin(0)))
            if range
              gates << FastifyConfigGate.new(root, key, m[1], Noir::PathScope.expand(file), range[0], range[1])
            elsif gates.none? { |g| g.file.nil? && g.root == root && g.key == key }
              gates << FastifyConfigGate.new(root, key, m[1], nil, 0, 0)
            end
          end
        end
      end
    end
    gates
  end

  # The spans of `text` a fastify-plugin wraps: the function handed to
  # `fp(…)`, inline or named and defined in the file.
  private def fastify_plugin_spans(text : String) : Array(Range(Int32, Int32))
    spans = [] of Range(Int32, Int32)
    return spans unless text.includes?("fp") || text.includes?("fastifyPlugin")
    text.scan(FASTIFY_PLUGIN_WRAP) do |m|
      if name = m[1]?
        definition = text.match(/\bfunction\s+#{Regex.escape(name)}\b|\b#{Regex.escape(name)}\s*(?::[^=;]*)?=[^=]/) || next
        open = text.index('{', definition.end(0)) || next
        close = Noir::JSLiteralScanner.find_matching_brace(text, open) || next
        spans << (open..close)
      else
        open = text.index('(', m.begin(0)) || next
        close = Noir::JSLiteralScanner.find_matching_paren(text, open) || next
        spans << (open..close)
      end
    end
    spans
  end

  # The route config keys a hook callback reads, as {gates, exempt}: a key
  # whose `if` refuses inside its block gates the routes that set it; one
  # whose `if` tests its absence and refuses there (`if (!config.public) {
  # … 401 }`), or returns at once when set (`if (config.public) return`),
  # lets those routes through.
  #
  # The third value is `callback` with the gating `if`s blanked: what the
  # hook still refuses for every route.
  private def fastify_config_keys(callback : String) : {Array(String), Array(String), String}
    gates = [] of String
    exempt = [] of String
    return {gates, exempt, callback} unless callback.matches?(FASTIFY_CONFIG_READ)
    ifs = [] of {String, String, Range(Int32, Int32)}
    gated = [] of Range(Int32, Int32)
    callback.scan(/\bif\s*\(/) do |m|
      cond_open = m.end(0) - 1
      cond_close = Noir::JSLiteralScanner.find_matching_paren(callback, cond_open) || next
      block_open = callback.index(/\S/, cond_close + 1) || next
      block_end = if callback[block_open] == '{'
                    (Noir::JSLiteralScanner.find_matching_brace(callback, block_open) || next) + 1
                  else
                    callback.index(/[;\n]/, block_open) || callback.size
                  end
      ifs << {callback[cond_open + 1...cond_close], callback[block_open...block_end], m.begin(0)...block_end}
    end
    callback.scan(FASTIFY_CONFIG_READ) do |read|
      key = read[1]
      alias_name = callback[0...read.begin(0)].match(/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*[^;=]*\z/).try(&.[1])
      value = alias_name ? /\b#{Regex.escape(alias_name)}\b/ : /(?:[A-Za-z_$][\w$]*\s*\.\s*)?#{Regex.escape(read[0])}/
      ifs.each do |condition, block, span|
        found = condition.match(value) || next
        absent = condition[0...found.begin(0)].rstrip.rstrip('(').rstrip.ends_with?('!') ||
                 condition[found.end(0)..].matches?(FASTIFY_ABSENT_TEST)
        refuses = block.matches?(FASTIFY_GATE_REFUSAL) || fastify_refusal_body?(block)
        # An exemption must hold for every route that sets the key: not when
        # another test joins the key's (`!x || !user`, `x && GET`).
        if absent
          exempt << key if refuses && !condition.includes?("||")
        elsif refuses
          # Only a test of the key alone (`perms && perms.length > 0`) gates:
          # in `!user || config.admin` the refusal reaches routes without it.
          next if condition.includes?("||") || condition.split("&&").any? { |part| !part.matches?(value) }
          gates << key
          gated << span
        elsif block.lstrip('{').lstrip.starts_with?("return") && !condition.includes?("&&")
          exempt << key
        end
      end
    end
    rest = callback
    gated.each { |span| rest = rest.sub(span, " " * span.size) }
    {gates.uniq!, exempt.uniq!, rest}
  end

  # Whether the route on line `line_idx` sets config `key` to a value.
  private def fastify_route_config(path : String, line_idx : Int32, method : String, url : String, key : String) : Bool
    args = fastify_route_args(path, line_idx, method, url) || return false
    args.any? do |arg|
      next false unless arg.lstrip.starts_with?('{')
      config = Noir::JSObjectLiteral.property(arg, "config") || next false
      value = Noir::JSObjectLiteral.property(config, key) || next false
      !value.matches?(FASTIFY_EMPTY_VALUE)
    end
  end

  # The route on line `line_idx` sets a key a gate hook of its project refuses on.
  private def fastify_config_gate(path : String, line_idx : Int32, method : String, url : String) : String?
    return if @fastify_config_gates.empty?
    root = package_root(path) || return
    expanded = Noir::PathScope.expand(path)
    gates = @fastify_config_gates.select do |gate|
      gate.root == root && (gate.file.nil? || (gate.file == expanded && gate.start_line <= line_idx + 1 && line_idx + 1 <= gate.end_line))
    end
    return if gates.empty?
    gate = gates.find { |g| fastify_route_config(path, line_idx, method, url, g.key) } || return
    "Fastify #{gate.kind} hook on config.#{gate.key}"
  end

  # The nearest directory holding a package.json.
  # ponytail: a gate is scoped to its package, not to the register tree.
  private def package_root(file : String) : String?
    dir = File.dirname(Noir::PathScope.expand(file))
    @package_roots.fetch(dir) do
      found = nil.as(String?)
      probe = dir
      loop do
        if File.exists?(File.join(probe, "package.json"))
          found = probe
          break
        end
        parent = File.dirname(probe)
        break if parent == probe
        probe = parent
      end
      @package_roots[dir] = found
    end
  end
end
