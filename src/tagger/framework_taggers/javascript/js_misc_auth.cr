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
    {/ctx\.state\.user/, "Koa ctx.state.user check"},
    {/ctx\.isAuthenticated\s*\(\)/, "Koa isAuthenticated check"},
  ]

  # Restify auth patterns
  RESTIFY_PATTERNS = [
    {/authorizationParser/, "Restify authorizationParser"},
    {/req\.authorization/, "Restify req.authorization check"},
    {/req\.username/, "Restify req.username check"},
  ]

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
  private def koa_guard(path : String, line_idx : Int32) : String?
    lines = read_file_lines(path) || return
    statement = code_only(lines[line_idx, MAX_KOA_ARG_LINES].join("\n"))
    head = statement.match(KOA_ROUTE_CALL) || return
    open_paren = head.end(0) - 1
    close_paren = Noir::JSLiteralScanner.find_matching_paren(statement, open_paren) || return
    args = Noir::TopLevelSplit.split(statement[open_paren + 1...close_paren], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
    return if args.size < 3
    content = read_file(path) || return
    args[1...-1].each do |arg|
      call = arg.strip.match(KOA_MIDDLEWARE_CALL) || next
      handler = Noir::JSHandlerResolver.resolve(call[1], content, path) || next
      evidence = refusal_in_definition(handler) || next
      options = call[2]? || ""
      body = koa_definition_body(handler) || next
      next if options.scan(KOA_DISABLING_OPTION).any? { |m| body.matches?(/\bif\s*\([^)]*\b#{Regex.escape(m[1])}\b/) }
      return "Koa #{call[1].gsub(/\s+/, "")} middleware (#{evidence.gsub(/\s+/, " ").chomp('(')})"
    end
    nil
  rescue
    nil
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
end
