require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/js_handler_resolver"
require "../../../miniparsers/js_route_extractor"
require "../../../utils/js_literal_scanner"
require "../../../utils/top_level_split"

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
  FASTIFY_ROUTE     = /\.\s*(?:get|post|put|patch|delete|del|head|options|all)\s*\(/
  FASTIFY_EXEMPT    = /if\s*\(\s*(?:request|req)\s*\.\s*(?:url|routerPath)\s*===?\s*['"]([^'"]+)['"]\s*\)\s*return\b/
  HOOK_KINDS        = %w[onRequest preHandler]

  record FastifyHook, file : String, start_line : Int32, end_line : Int32, kind : String, exempt : Array(String)

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
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @fastify_hooks = scan_fastify_hooks
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
        description = fastify_route_guard(path_info.path, line_idx) || fastify_plugin_hook(path_info.path, line_num, endpoint.url)
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
    route = koa_call(lines, line_idx, KOA_ROUTE_CALL) || return
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
      use = koa_call(lines, idx, use_call) || next
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
  private def koa_call(lines : Array(String), line_idx : Int32, call_re : Regex) : {String?, Array(String)}?
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
          next unless fastify_refuses?(callback, text, file)
          hook_line = text[0...m.begin(0)].count('\n') + 1
          range = fastify_innermost(registers, hook_line) || {1, text.count('\n') + 1}
          exempt = callback.scan(FASTIFY_EXEMPT).map(&.[1])
          rules << FastifyHook.new(Noir::PathScope.expand(file), range[0], range[1], m[1], exempt)
        end
      end
    end
    rules
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

  private def fastify_refuses?(expr : String, content : String, file : String) : Bool
    return true if expr.matches?(FASTIFY_REPLY_401)
    name = expr.strip.match(/\A([A-Za-z_$][\w$]*)\z/).try(&.[1]) || return false
    handler = Noir::JSHandlerResolver.resolve(name, content, file) || return false
    path = handler.path || return false
    line = handler.line || return false
    source = read_file(path) || return false
    body = Noir::JSRouteExtractor.definition_body(Noir::CComments.strip(source, quotes: %("'`)), line)
    body.matches?(FASTIFY_REPLY_401)
  end

  private def fastify_plugin_hook(path : String, line : Int32, url : String) : String?
    expanded = Noir::PathScope.expand(path)
    @fastify_hooks.each do |hook|
      next unless hook.file == expanded && hook.start_line <= line && line <= hook.end_line
      next if hook.exempt.any? { |exempt| exempt == url || exempt.rstrip('/') == url.rstrip('/') }
      return "Fastify #{hook.kind} hook"
    end
    nil
  end

  # A route option `preHandler: requireUser` or an inline preHandler that
  # replies 401. A preHandler that does not refuse (an admin check that
  # only calls `next`) is not a guard.
  private def fastify_route_guard(path : String, line_idx : Int32) : String?
    lines = read_file_lines(path) || return
    return if line_idx < 0 || line_idx >= lines.size
    text = Noir::CComments.strip(lines[line_idx, 40].join('\n'), quotes: %("'`))
    head = text.match(FASTIFY_ROUTE) || return
    return if text[0...head.begin(0)].includes?('\n')
    open = head.end(0) - 1
    close = Noir::JSLiteralScanner.find_matching_paren(text, open) || return
    args = Noir::TopLevelSplit.split(text[open + 1...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
    content = read_file(path) || return
    HOOK_KINDS.each do |key|
      args.each do |arg|
        next unless arg.lstrip.starts_with?('{')
        expr = fastify_property(arg, key) || next
        if expr.matches?(FASTIFY_REPLY_401)
          return "Fastify #{key}"
        end
        expr.scan(/\b([A-Za-z_$][\w$]*)\b/) do |ident|
          name = ident[1]
          next if {"async", "await", "function", "return", "request", "reply", "req", "res", "true", "false", "null"}.includes?(name)
          next unless fastify_refuses?(name, content, path)
          return "Fastify #{key} #{name}"
        end
      end
    end
    nil
  end

  private def fastify_property(object_text : String, prop : String) : String?
    text = object_text.strip
    return unless text.starts_with?('{') && text.ends_with?('}')
    Noir::TopLevelSplit.split(text[1...-1], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).each do |part|
      if found = part.match(/\A\s*['"]?#{Regex.escape(prop)}['"]?\s*:\s*(.*)\z/m)
        return found[1].strip
      end
    end
    nil
  end
end
