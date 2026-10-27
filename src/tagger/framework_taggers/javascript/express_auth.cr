require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/js_handler_resolver"
require "../../../utils/js_literal_scanner"
require "../../../utils/top_level_split"
require "../prefix_scope"

@[Noir::TaggerFor(key: "express_auth", name: "Express Auth Tagger", desc: "Identifies Express.js authentication patterns (Passport, JWT, auth middleware)", order: 40)]
class ExpressAuthTagger < FrameworkTagger
  include PrefixScope

  PASSPORT_PATTERN = /passport\.authenticate\s*\(/

  # Passport strategies that *are* the login flow — `local` checks the
  # submitted password on `POST /login`, the OAuth/OIDC/SAML ones start or
  # finish a provider redirect. The route they sit on is the anonymous entry
  # point, not a protected resource.
  PASSPORT_LOGIN_STRATEGY = /\A(?:local\w*|google\w*|github|gitlab|facebook|twitter|linkedin\w*|microsoft|azuread-openidconnect|apple|discord|slack|auth0|okta|oauth2?|openidconnect|oidc|saml)\z/i

  JWT_MIDDLEWARE_PATTERNS = [
    /expressjwt\s*\(/,
    /expressJwt\s*\(/,
  ]

  AUTH_MIDDLEWARE_NAMES = [
    /\brequireAuth\b/,
    /\bisAuth\b/,
    /\bisAuthenticated\b/,
    /\bensureLoggedIn\b/,
    /\bensureAuthenticated\b/,
    /\bauthorize\b/,
    /\brequireLogin\b/,
    /\bauthMiddleware\b/,
    /\bverifyToken\b/,
    /\bcheckAuth\b/,
  ]

  # What a middleware's *definition* must be able to do to count as a guard
  # whatever it is called: refuse the request. `jwt.verify(` alone is
  # deliberately absent — a function that verifies a token and then calls
  # `next()` unconditionally (juice-shop's `updateAuthenticatedUsers`) is
  # not a guard, and it is `app.use()`d over every route.
  REFUSING_DEFINITION = /\bexpress[jJ]wt\s*\(|\bpassport\.authenticate\s*\(|(?:\b\w+\.)?(?:status|sendStatus|send)\s*\(\s*40[13]\s*\)?|\bnext\s*\(\s*(?:new\s+)?(?:[\w$]+\.)*\w*(?:Unauthori[sz]ed|Forbidden|NoPermission|PermissionDenied)\w*|\bcreateError\s*\(\s*40[13]\b|\bnext\s*\(\s*\{[^}]*\b40[13]\b/

  # `(err, req, res, next)`: an error handler answers 401 *for* a guard;
  # it is not one.
  ERROR_HANDLER_SIGNATURE = /\(\s*err\w*\s*[,:]/

  # A definition that answers the request itself, refusals aside: in the
  # handler position that is the handler (`login()` answers 401 to a wrong
  # password), not a guard in front of one.
  HANDLER_RESPONSE = /\b(?:res|response)\s*\.\s*(?:json|send|sendStatus|render|redirect|sendFile|download|attachment|end|status)\s*\(|\.pipe\s*\(\s*(?:res|response)\s*\)/

  # ponytail: brace/paren-counted spans; a registration whose closure runs
  # past 60 lines or a definition past 40 is read truncated, not re-parsed.
  MAX_STATEMENT_LINES  = 60
  MAX_DEFINITION_LINES = 40

  # `app.use('/prefix', authMiddleware)` — the guarded path is spelled out, so
  # the rule can be matched against endpoint URLs anywhere in the scan (the
  # routes it guards are usually mounted from another file).
  MOUNTED_USE = /(?:app|router)\.use\s*\(\s*['"]([^'"]+)['"]/

  # `x.use(authMiddleware)` — no path argument. Which routes this guards is a
  # property of the *object* `x`, not of any URL, so the receiver is captured.
  BARE_USE = /\b(\w+)\.use\s*\(/

  # A route registration, and who it was registered on: `app.get('/x', …)`,
  # `router.post(…)`, `app.route('/x')`.
  ROUTE_RECEIVER = /\b(\w+)\s*\.\s*(?:get|post|put|patch|delete|options|head|all|use|route)\s*\(/

  # The start of a route registration, used as a statement boundary so a
  # window around one route never reads the next one's middleware.
  ROUTE_DECLARATION = /\.\s*(?:get|post|put|patch|delete|options|head|all|use|route)\s*\(/

  def initialize(options : Hash(String, YAML::Any))
    super
    @mounted_auth_rules = [] of {prefix: String, description: String}
    @receiver_auth_rules = [] of {file: String, receiver: String, line: Int32, description: String}
    # The method of the endpoint being judged, for `req.method` tests; nil
    # while mounts are pre-scanned.
    @method = nil.as(String?)
  end

  def self.target_techs : Array(String)
    ["js_express"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Pre-scan: Find app.use() level auth middleware
    pre_scan_app_use_auth
    # Endpoint is a struct: a cleared `handler` lives on the copy.
    endpoints.each_with_index do |endpoint, idx|
      endpoints[idx] = check_endpoint(endpoint)
    end
    endpoints
  end

  private def pre_scan_app_use_auth
    @mounted_auth_rules.clear
    @receiver_auth_rules.clear

    extensions = [".js", ".ts", ".mjs", ".cjs"]
    extensions.each do |ext|
      files = collect_files_by_extension(ext)
      files.each do |file|
        lines = read_file_lines(file)
        next if lines.nil?
        expanded = Noir::PathScope.expand(file)

        lines.each_with_index do |line, idx|
          stripped = line.strip
          next unless stripped.includes?(".use")
          next unless stripped.matches?(ROUTE_DECLARATION)
          statement = Noir::CComments.strip(get_route_statement(lines, idx).join("\n"), quotes: %("'`))
          args = call_args(statement) || [statement]
          # The last argument of `app.use('/ftp/:file', serveFiles())` is the
          # mount's handler when its definition serves the request: it
          # answers 403 to a bad name, which no more makes it a guard than
          # `login()` answering 401 does.
          guard = args.each_with_index do |arg, arg_idx|
            found = guard_description(arg, file, handler_position: arg_idx == args.size - 1)
            break found if found
          end
          next unless guard

          # `app.use(\n  '/private',\n  auth,\n)`: the path is on a later line.
          if match = statement.match(MOUNTED_USE)
            prefix = match[1]
            @mounted_auth_rules << {prefix: prefix, description: "#{guard} via app.use() on #{prefix}"}
          elsif match = stripped.match(BARE_USE)
            # A path-less `use(auth)` guards the routes registered on THIS
            # object, below THIS line — nothing else. Registering it as a
            # global `prefix: "/"` rule (what this used to do) meant one
            # `router.use(requireAuth)` in `routes/admin.js` reported every
            # endpoint in the project as protected, including `/login`.
            receiver = match[1]
            @receiver_auth_rules << {
              file:        expanded,
              receiver:    receiver,
              line:        idx + 1,
              description: "#{guard} via #{receiver}.use()",
            }
          end
        end
      end
    end
  end

  private def check_endpoint(endpoint : Endpoint) : Endpoint
    @method = endpoint.method
    check_route(endpoint)
  ensure
    @method = nil
  end

  private def check_route(endpoint : Endpoint) : Endpoint
    receiver_description = nil

    # Check route definition line for auth patterns
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?

      # The whole registration statement, argument by argument: any
      # argument may be the guard, so each is read on its own.
      route_lines = get_route_statement(lines, line_num - 1) # 0-indexed
      route_text = Noir::CComments.strip(route_lines.join("\n"), quotes: %("'`))
      args = helper_call_args(route_text) || call_args(route_text)
      (args || [route_text]).each_with_index do |arg, idx|
        last = !args.nil? && idx == args.size - 1
        description = guard_description(arg, path_info.path, handler_position: last) || next
        endpoint.add_tag(Tag.new("auth", description, "express_auth"))
        # `app.get('/api/Users', security.isAuthorized())`: the guard is the
        # only callable, so the analyzer reported it as the handler. It is
        # not one — the request falls through to the next match. A refusing
        # wrapper (`withAuth(list)`) is the guard around a handler that stays.
        # An inline closure that checks the caller itself is still the handler.
        if args && idx == args.size - 1 && !arg.matches?(Noir::JSRouteExtractor::INLINE_FUNCTION_RE) && wrapper_guard(arg, path_info.path).nil?
          endpoint.handler = nil
        end
        return endpoint
      end

      receiver_description ||= check_receiver_use_auth(path_info.path, lines, line_num - 1)
    end

    # Check app.use() level auth: the router this route was registered on
    # first, then a path-scoped mount.
    description = receiver_description || check_mounted_use_auth(endpoint) || handler_caller_check(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "express_auth"))
    end
    endpoint
  end

  # Why `arg` (one argument of a registration, as written) guards the
  # route, or nil. Passport needs its strategy string; the inline and named
  # markers are identifiers, so they match the code alone; anything else is
  # followed to its definition.
  private def guard_description(arg : String, file : String, handler_position : Bool = false) : String?
    if arg.matches?(PASSPORT_PATTERN)
      strategies = arg.scan(/passport\.authenticate\s*\(\s*['"]([^'"]+)['"]/).map(&.[1])
      strategy = strategies.empty? ? "unknown" : strategies.find { |name| !name.matches?(PASSPORT_LOGIN_STRATEGY) }
      return strategy ? "Protected by Passport.js #{strategy} strategy" : nil
    end

    code = code_only(arg)
    return "Protected by Express JWT middleware" if JWT_MIDDLEWARE_PATTERNS.any? { |pattern| code.matches?(pattern) }
    # `[...middlewares, middleware.assert.post]`: Express flattens an array
    # of handlers into the chain, so each element is a step of its own.
    if elements = array_elements(code)
      elements.each do |element|
        found = guard_description(element.strip.lchop("...").strip, file)
        return found if found
      end
      return
    end
    # `asyncHandler(adminOnly)`, `withAuth(list)`: the wrapper is judged by
    # its own definition, and what it wraps keeps its position's judgement.
    if wrapped = unwrapped_arg(arg, file)
      return wrapper_guard(arg, file) || guard_description(wrapped, file, handler_position)
    end
    # A name inside the handler closure is a call or a read
    # (`if (config.debug && req.isAuthenticated()) log()`), not a step:
    # `handler_caller_check` judges that body by what it does.
    if !(handler_position && arg.matches?(Noir::JSRouteExtractor::INLINE_FUNCTION_RE)) && (named = name_guard(code))
      return named
    end

    if resolved = refusing_definition(arg, file, handler_position)
      name, evidence = resolved
      "Protected by Express #{name} (#{evidence}) middleware"
    end
  end

  # The fallback for a step whose definition is not in the scan.
  private def name_guard(code : String) : String?
    AUTH_MIDDLEWARE_NAMES.each do |pattern|
      if match = code.match(pattern)
        return "Protected by Express #{match[0]} middleware"
      end
    end
    nil
  end

  private def array_elements(code : String) : Array(String)?
    text = code.strip
    return unless text.starts_with?('[')
    close = Noir::JSLiteralScanner.find_matching_bracket(text, 0) || return
    return unless close == text.size - 1
    Noir::TopLevelSplit.split(text[1...close], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).reject(&.blank?)
  end

  HELPER_CALL = /\A\s*(?:await\s+)?((?:[A-Za-z_$][\w$]*\s*\.\s*)*([A-Za-z_$][\w$]*))\s*\(/
  PATH_ARG    = /\A\s*['"`]\//

  # The steps of a registration made through a route helper
  # (`setupApiRoute(router, 'put', '/:pid/vote', [...], controllers.vote)`):
  # the arguments the helper hands to the router as the route's middleware
  # and handler. Nil unless the statement opens with
  # such a call: a verb call is a registration of its own.
  private def helper_call_args(statement : String) : Array(String)?
    head = statement.match(HELPER_CALL) || return
    return if head[2].matches?(/\A(?:get|post|put|patch|delete|options|head|all|use|route)\z/)
    open_paren = head.end(0) - 1
    close_paren = Noir::JSLiteralScanner.find_matching_paren(statement, open_paren) || return
    args = Noir::TopLevelSplit.split(statement[open_paren + 1...close_paren], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).reject(&.blank?)
    return unless args.any?(&.matches?(PATH_ARG))
    # Every argument but the literals (verb, path) and the router may be a
    # step: `secured(ensureAuthenticated, router, 'get', '/x', h)` forwards
    # its guard from before the path. The handler stays the last.
    steps = args.reject { |arg| arg.matches?(LITERAL_ARG) || arg.strip.matches?(ROUTER_ARG) }
    steps unless steps.empty?
  end

  LITERAL_ARG = /\A\s*(?:'[^']*'|"[^"]*"|`[^`]*`)\s*\z/
  # The receiver a helper is handed, by the names the route-helper scanner
  # accepts for it.
  ROUTER_ARG = /\A_?(?:router|app|server|[A-Za-z_$][\w$]*(?:Router|App|Server))\z/

  private def unwrapped_arg(arg : String, file : String) : String?
    content = read_file(file) || return
    Noir::JSHandlerResolver.unwrap(code_only(arg).strip, content, file, guards: true).try(&.[0])
  end

  # The guard a wrapper call (`withAuth(list)`, `asyncHandler(withAuth(list))`)
  # itself is: a wrapper whose definition refuses the caller before handing
  # the request on.
  private def wrapper_guard(arg : String, file : String, depth : Int32 = 0) : String?
    return if depth > 3
    content = read_file(file) || return
    wrapped = Noir::JSHandlerResolver.unwrap(code_only(arg).strip, content, file, guards: true) || return
    if found = refusing_definition(wrapped[2], file, false)
      return "Protected by Express #{found[0]} (#{found[1]}) wrapper"
    end
    wrapper_guard(wrapped[0], file, depth + 1)
  end

  # `arg` resolved to its definition (same file or a relative import) and
  # the marker there that lets it refuse a request; nil for an inline
  # closure, a package import, a body that only decodes and continues, or
  # — in the handler position — one that serves the request itself.
  # Judged once per step: a shared middleware array is spread into hundreds
  # of routes.
  @refusals = Hash(Tuple(String, String, Bool, Int32, String?), {String, String}?).new

  private def refusing_definition(arg : String, file : String, handler_position : Bool, depth : Int32 = 0) : {String, String}?
    key = {arg, file, handler_position, depth, @method}
    return @refusals[key] if @refusals.has_key?(key)
    @refusals[key] = judge_definition(arg, file, handler_position, depth)
  end

  private def judge_definition(arg : String, file : String, handler_position : Bool, depth : Int32) : {String, String}?
    content = read_file(file) || return
    handler = Noir::JSHandlerResolver.resolve(arg, content, file) || return
    path, line = handler.path, handler.line
    return if path.nil? || line.nil?
    lines = read_file_lines(path) || return
    if elements = middleware_array(lines, line - 1)
      return if depth >= MAX_ARRAY_DEPTH
      # `open.splice(0, 1)`: what the array holds at the route is not its literal.
      return if (read_file(path) || "").matches?(/(?<![\w$.])#{Regex.escape(handler.name.split('.').last)}\s*\.\s*(?:splice|push|pop|shift|unshift|length\s*=)/)
      elements.each do |element|
        element = element.strip.lchop("...").strip
        found = refusing_definition(element, path, false, depth + 1)
        return {"#{handler.name.gsub(/\s+/, "")} > #{found[0]}", found[1]} if found
        if named = name_guard(element)
          return {"#{handler.name.gsub(/\s+/, "")} > #{element.gsub(/\s+/, "")}", named}
        end
      end
      return
    end
    # `export default asyncHandler(handler)`: the definition is the wrapped one.
    if depth < MAX_ARRAY_DEPTH && (call = code_only(lines[line - 1]).match(WRAPPED_EXPORT))
      found = refusing_definition(call[1], path, handler_position, depth + 1) || return
      return {handler.name.gsub(/\s+/, ""), found[1]}
    end
    body = definition_extent(lines, line - 1)
    return if body.first?.try(&.matches?(ERROR_HANDLER_SIGNATURE))
    code = code_with_words(body.join("\n"))
    evidence = (anonymous_refusal(code, read_file(path)) || identity_throw(code)).try do |found|
      found, note = found.partition(SETTING_NOTE)
      found.gsub(/\bnew\s+/, "new ").gsub(/(?<!\bnew)\s+/, "").chomp('(').sub(/\Athrownew\b/, "throw new") + note
    end
    evidence ||= caller_stop(path, line) || return
    # In the handler position a definition that answers the request is the
    # handler; one that calls `next()` on success is middleware all the same
    # (`app.use('/private', auth)`).
    return if handler_position && !code.matches?(BARE_NEXT) && code.gsub(REFUSING_DEFINITION, "").matches?(HANDLER_RESPONSE)
    {handler.name.gsub(/\s+/, ""), evidence}
  rescue
    nil
  end

  # A middleware whose first check stops a caller that is not there:
  # `if (!req.loggedIn) { return helpers.notAllowed(req, res); }`. The branch
  # returns without `next`, so an anonymous request never reaches the route,
  # whatever the function it returns through sends.
  private def caller_stop(path : String, line : Int32) : String?
    content = read_file(path) || return
    request = request_param(content, line) || return
    body = code_with_words(Noir::JSRouteExtractor.definition_body(content, line))
    caller_absence_refusal(body, Regex.escape(request), stop_file: path)
  end

  STOP_CALL = /\breturn\s+(?:await\s+)?([A-Za-z_$][\w$]*(?:\s*\.\s*[A-Za-z_$][\w$]*)*)\s*\(/

  # A branch that returns, without `next`, through a function whose own
  # definition refuses (`return helpers.notAllowed(req, res)`, which answers
  # 401/403 or redirects to the login page).
  private def stop_refusal(branch : String, file : String) : String?
    return if branch.matches?(/\bnext\b/)
    call = branch.match(STOP_CALL) || return
    content = read_file(file) || return
    # `if (!req.loggedIn) { if (meta.config.privateSite) return … }`: the
    # return sits under a further condition.
    reach = refusal_reach(branch, call.begin(0), content) || return
    target = Noir::JSHandlerResolver.resolve(call[1].gsub(/\s+/, ""), content, file) || return
    path, line = target.path, target.line
    return if path.nil? || line.nil?
    text = read_file(path) || return
    body = code_only(Noir::JSRouteExtractor.definition_body(text, line))
    return unless anonymous_refusal(body) || body.matches?(/\b(?:res|response)\s*\.\s*redirect\s*\(/)
    "returns #{call[1].gsub(/\s+/, "")}#{SETTING_NOTE if reach == :setting}"
  end

  MAX_ARRAY_DEPTH = 4
  WRAPPED_EXPORT  = /\A\s*(?:export\s+default|(?:export\s+)?(?:const|let|var)\s+[\w$]+\s*(?::[^=]*)?=|module\.exports\s*=)\s*([A-Za-z_$][\w$.]*\s*\(\s*[A-Za-z_$][\w$]*\s*\))\s*;?\s*\z/
  BARE_NEXT       = /\bnext\s*\(\s*\)/

  # Request fields that carry what the caller sent or what the app looked
  # up, not who the caller is: a check on them refuses bad input.
  DATA_ROOTS = /\A(?:params|query|body|headers?|cookies|signedCookies|files?|schema|method|path|url|originalUrl|baseUrl|ip|ips|hostname|protocol|get|is|accepts|collection|sanitizedQuery|route|app|res)\z/

  # `throw new ForbiddenError()` under an `if` that reads who the caller is
  # (`if (!isAdmin(req.accountability))`): every anonymous caller takes it.
  # A throw on request data (`req.params.collection in req.schema…`) is a
  # 4xx for bad input, not a guard.
  IDENTITY_THROW = /\bthrow\s+new\s+(?:[\w$]+\.)*\w*(?:Unauthori[sz]ed|Forbidden|InvalidCredentials|Unauthenticated|NotAuthenticated|PermissionDenied|NoPermission)\w*/

  private def identity_throw(code : String, receivers : String = "req|request") : String?
    code.scan(IDENTITY_THROW) do |m|
      at = m.begin(0)
      return if code[0...at].matches?(ANONYMOUS_PASS_THROUGH)
      condition = enclosing_condition(code, at) || next
      next if condition.matches?(PRESENCE_CONJUNCTION)
      # Only a negated test is one an absent caller fails:
      # `if (req.accountability?.share)` lets anonymous through.
      next unless condition.matches?(/\A\s*!|!==?/)
      return m[0] if reads_identity?(condition, receivers)
    end
    nil
  end

  # The condition of the `if` whose block (or single statement) holds `at`.
  private def enclosing_condition(code : String, at : Int32) : String?
    head = code[0...at]
    if_at = head.rindex(/\bif\s*\(/) || return
    open = code.index('(', if_at) || return
    close = Noir::JSLiteralScanner.find_matching_paren(code, open) || return
    return if close >= at
    between = code[close + 1...at]
    inside = if brace = between.index('{')
               between[0...brace].blank? && (Noir::JSLiteralScanner.find_matching_brace(code, close + 1 + brace) || code.size) > at
             else
               !between.includes?(';') && !between.includes?('}')
             end
    inside ? code[open + 1...close] : nil
  end

  private def reads_identity?(text : String, receivers : String) : Bool
    text.scan(/(?<![\w$.])(?:#{receivers})\s*\??\.\s*([A-Za-z_$][\w$]*)/).any? { |m| !m[1].matches?(DATA_ROOTS) }
  end

  # `authAdminApi = [authenticate, authorize, cors]`: Express flattens an
  # array of handlers into the chain, so each element is a middleware of the
  # route. Nil unless the definition at `idx` is an array literal.
  private def middleware_array(lines : Array(String), idx : Int32) : Array(String)?
    return if idx < 0 || idx >= lines.size
    head = lines[idx].match(/\A[^=:(]*(?:=|:)\s*\[/) || return
    text = lines[idx...Math.min(lines.size, idx + MAX_DEFINITION_LINES)].join("\n")
    open = head.end(0) - 1
    close = Noir::JSLiteralScanner.find_matching_bracket(text, open) || return
    Noir::TopLevelSplit.split(code_only(text[open + 1...close]), ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
  end

  # `if (!req.headers.authorization) { return next(); }`: a caller without
  # the credential is let through before anything can refuse it.
  ANONYMOUS_PASS_THROUGH = /\bif\s*\(\s*!\s*req\.[^)]*\)\s*\{?[^{}]*?\breturn\s+next\s*\(\s*\)/
  # `if (req.member && req.member.banned)`: the refusal needs something
  # present first, which an anonymous caller does not have.
  PRESENCE_CONJUNCTION = /\A\s*[\w$.?]+\s*&&/

  # The first refusal in `code` that an anonymous caller can reach: not after
  # a pass-through for a missing credential, nor inside an `if` that first
  # requires something to be present.
  # `source` is the file the code comes from, for telling a setting from a
  # request check (`refusal_reach`).
  private def anonymous_refusal(code : String, source : String? = nil) : String?
    by_setting = nil.as(String?)
    code.scan(REFUSING_DEFINITION) do |m|
      at = m.begin(0)
      return by_setting if code[0...at].matches?(ANONYMOUS_PASS_THROUGH)
      next if presence_gated?(code, at)
      case refusal_reach(code, at, source)
      when :always  then return m[0]
      when :setting then by_setting ||= "#{m[0]}#{SETTING_NOTE}"
      end
    end
    by_setting
  end

  # `code_only`, keeping word literals (`req.method !== 'GET'`) a
  # condition needs to be judged.
  private def code_with_words(text : String) : String
    Noir::CComments.strip(text, quotes: %("'`)).gsub(STRING_LITERAL) { |lit| lit.matches?(/\A['"][A-Za-z]{1,10}['"]\z/) ? lit : %("") }
  end

  SETTING_NOTE = " — a setting can lift it"
  METHOD_TEST  = /\A\(*\s*(?:req|request)\s*\.\s*method\s*(!==?|===?)\s*['"]([A-Za-z]+)['"]\s*\)*\z/
  IF_HEAD      = /(?<![\w$.])if\s*\(/
  JS_WORDS     = /\A(?:true|false|null|undefined|typeof|instanceof|in|new|void|this)\z/

  # Whether a refusal at `at` in `code` reaches an anonymous caller of the
  # route's method (`@method`), by the `if`s enclosing it: `:always`;
  # `:setting` when a condition reads only module-level state
  # (`if (meta.config.privateSite)`, a config flag decides it); nil when a
  # method test excludes this method. Other conditions keep the refusal, as
  # before. Without `source` or a method, a condition is not judged.
  private def refusal_reach(code : String, at : Int32, source : String?) : Symbol?
    reach = :always
    enclosing_conditions(code, at).each do |condition|
      text = condition.strip
      if method_test = text.match(METHOD_TEST)
        method = @method || next
        equal = method_test[1].starts_with?("==")
        return unless equal == (method.upcase == method_test[2].upcase)
      elsif source && module_state?(text, source)
        reach = :setting
      end
    end
    reach
  end

  # The conditions of every `if` whose block (or single statement) holds `at`.
  private def enclosing_conditions(code : String, at : Int32) : Array(String)
    conditions = [] of String
    code[0...at].scan(IF_HEAD) do |m|
      open = m.end(0) - 1
      close = Noir::JSLiteralScanner.find_matching_paren(code, open) || next
      next if close >= at
      between = code[close + 1...at]
      inside = if between.lstrip.starts_with?('{')
                 brace = close + 1 + (between.size - between.lstrip.size)
                 (Noir::JSLiteralScanner.find_matching_brace(code, brace) || code.size) > at
               else
                 !between.includes?(';') && !between.includes?('}')
               end
      conditions << code[open + 1...close] if inside
    end
    conditions
  end

  # A condition whose every root is module-level in `source` (an import or a
  # top-level `const`) or `process`: configuration, not the request.
  private def module_state?(condition : String, source : String) : Bool
    roots = condition.gsub(/(['"`])(?:(?!\1)[^\\]|\\.)*\1/, "").scan(/(?<![\w$.])([A-Za-z_$][\w$]*)/).map(&.[1]).reject(&.matches?(JS_WORDS)).uniq!
    return false if roots.empty?
    roots.all? do |root|
      root == "process" || source.matches?(/^(?:const|let|var)\s+(?:#{Regex.escape(root)}\b|\{[^}]*\b#{Regex.escape(root)}\b[^}]*\})|^import\b[^\n]*\b#{Regex.escape(root)}\b/m)
    end
  end

  private def presence_gated?(code : String, at : Int32) : Bool
    head = code[0...at]
    if_at = head.rindex(/\bif\s*\(/) || return false
    open = code.index('(', if_at) || return false
    close = Noir::JSLiteralScanner.find_matching_paren(code, open) || return false
    return false if close >= at
    between = code[close + 1...at]
    # The refusal belongs to this `if` only while its block (or single
    # statement) is still open; an `else` after it is the absent case.
    inside = if brace = between.index('{')
               between[0...brace].blank? &&
                 (Noir::JSLiteralScanner.find_matching_brace(code, close + 1 + brace) || code.size) > at
             else
               !between.includes?(';') && !between.includes?('}')
             end
    inside && code[open + 1...close].matches?(PRESENCE_CONJUNCTION)
  end

  # The lines of the definition starting at `idx`: a one-line arrow
  # (`isAuthorized = () => expressJwt(...)`) is one line; a braced body runs
  # to the brace that closes it.
  private def definition_extent(lines : Array(String), idx : Int32) : Array(String)
    result = [] of String
    return result if idx < 0 || idx >= lines.size
    depth = 0
    i = idx
    while i < lines.size && i < idx + MAX_DEFINITION_LINES
      result << lines[i]
      code = code_only(lines[i])
      depth += code.count('{') - code.count('}')
      # `(fn) => (req, res, next) =>\n  req.user ? fn(…) : res.sendStatus(401);`
      # continues on the next line.
      break if depth <= 0 && !code.rstrip.matches?(/(?:=>|[(,?:=]|&&|\|\|)\z/)
      i += 1
    end
    result
  end

  # The arguments of the registration `statement` opens with (the `(`…`)`
  # after its `.get(` / `.use(` / …), split at the top level so a closure
  # body or an object literal stays one argument. Nil when the statement
  # holds no registration.
  private def call_args(statement : String) : Array(String)?
    head = statement.match(ROUTE_DECLARATION) || return
    open_paren = statement.index('(', head.begin(0)) || return
    close_paren = Noir::JSLiteralScanner.find_matching_paren(statement, open_paren) || statement.size
    # A trailing comma leaves an empty last part; the last real argument is
    # the handler position.
    Noir::TopLevelSplit.split(statement[open_paren + 1...close_paren], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).reject(&.blank?)
  end

  # Get lines that make up a route statement (handles multi-line route definitions)
  private def get_route_statement(lines : Array(String), line_idx : Int32) : Array(String)
    return [] of String if line_idx < 0 || line_idx >= lines.size

    result = [lines[line_idx]]

    # Look at preceding lines that might be part of the same statement
    # (e.g., chained method calls). Skipped when the referenced line already
    # starts a route registration — walking back from there can only reach
    # the *previous* route, whose middleware is not this route's.
    unless lines[line_idx].matches?(ROUTE_DECLARATION)
      i = line_idx - 1
      while i >= 0 && i >= line_idx - 2
        stripped = lines[i].strip
        break if stripped.empty? || stripped.ends_with?(";")
        # Only include if this looks like part of the route definition
        if stripped.matches?(ROUTE_DECLARATION)
          result.unshift(lines[i])
          break
        elsif stripped.includes?("passport") || stripped.includes?("expressjwt")
          result.unshift(lines[i])
        else
          break
        end
        i -= 1
      end
    end

    # Look at following lines that might complete the statement — but only
    # while the statement is actually still open. The route line's own
    # parentheses say whether it is: `app.get('/x', (req, res) => { … });`
    # closes on itself, and reading one line past it attributed the NEXT
    # route's `requireAuth` to this one. Parentheses are counted on the
    # code alone, so a `(` in a path literal or a trailing comment cannot
    # hold the statement open.
    depth = paren_depth(code_only(lines[line_idx]))
    i = line_idx + 1
    while depth > 0 && i < lines.size && i < line_idx + MAX_STATEMENT_LINES
      break if lines[i].strip.matches?(ROUTE_DECLARATION)
      result << lines[i]
      depth += paren_depth(code_only(lines[i]))
      i += 1
    end

    result
  end

  private def paren_depth(line : String) : Int32
    line.count('(') - line.count(')')
  end

  # A path-less `x.use(auth)` guards the routes registered on `x`, in the same
  # file, after that line.
  private def check_receiver_use_auth(path : String, lines : Array(String), line_idx : Int32) : String?
    return if @receiver_auth_rules.empty?
    return if line_idx < 0 || line_idx >= lines.size

    # Which object the route was registered on. Unreadable (a multi-line
    # registration whose receiver sits above the referenced line) means we
    # cannot tell app from sub-router, so decline rather than guess: a false
    # "protected" is the failure that gets an endpoint skipped in review.
    # A `x.route('/p')` chain link (`  .post(...)`) reports its own line, which
    # names no receiver: the chain's `x.route(` line above does.
    line_idx = chain_start_line(lines, line_idx) if lines[line_idx].lstrip.starts_with?('.')
    receiver = lines[line_idx].match(ROUTE_RECEIVER).try &.[1]
    return if receiver.nil?

    expanded = Noir::PathScope.expand(path)
    line_num = line_idx + 1

    @receiver_auth_rules.each do |rule|
      next unless rule[:receiver] == receiver
      next unless rule[:file] == expanded
      next unless rule[:line] < line_num
      return rule[:description]
    end

    nil
  end

  ROUTE_CHAIN_START  = /\b\w+\s*\.\s*route\s*\(/
  MAX_CHAIN_LOOKBACK = 500

  # The `x.route(` line a chain link at `line_idx` belongs to: walk up over
  # earlier links and their (bracket-balanced) handler bodies to the first
  # line outside any bracket that does not continue the chain. Returns
  # `line_idx` itself when that line is not an `x.route(` head (`app` alone
  # on the line above `.get(`, say), so the receiver reads as unknown.
  private def chain_start_line(lines : Array(String), line_idx : Int32) : Int32
    depth = 0
    idx = line_idx - 1
    stop = Math.max(0, line_idx - MAX_CHAIN_LOOKBACK)
    while idx >= stop
      line = lines[idx]
      line.each_char do |char|
        case char
        when ')', '}', ']' then depth += 1
        when '(', '{', '[' then depth -= 1
        end
      end
      if depth <= 0 && !line.lstrip.starts_with?('.')
        return line.matches?(ROUTE_CHAIN_START) ? idx : line_idx
      end
      idx -= 1
    end
    line_idx
  end

  # The last field of a negated read that names who is calling:
  # `!req.user`, `!req.accountability?.user`, `!req.session.userId`,
  # `!req.isAuthenticated()`. The first field must not be request data
  # (`!req.params.userId` refuses a bad URL, not an anonymous caller).
  CALLER_FIELD = /\A(?:user|userId|user_id|uid|currentUser|account|accountId|principal|identity|isAuthenticated|isLoggedIn|loggedIn)\z/

  # What the guarded branch does to the caller it stops, and how that reads
  # in the tag: throws (the app's error handler answers), answers 401/403
  # (`res.status(401)` alone sends nothing), hands an error to `next(err)`,
  # or redirects to a login page.
  BRANCH_REFUSALS = {
    /\bthrow\b/                                                                                                                                     => "throws",
    /\b(?:res|response)\s*\.\s*sendStatus\s*\(\s*40[13]\b|\b(?:res|response)\s*\.\s*status\s*\(\s*40[13]\s*\)\s*\.\s*(?:json|send|end|render)\s*\(/ => "answers 401/403",
    /\bnext\s*\(\s*[^)\s]/                                                                                                                          => "next(err)",
    /\b(?:res|response)\s*\.\s*redirect\s*\(/                                                                                                       => "redirects",
  }

  # Anything that can answer, pass the request on or change state before a
  # later check runs; a check after one of these is not what every caller
  # meets first.
  EARLIER_EXIT = /\breturn\b|\bawait\b|\bnext\s*\(|\b(?:res|response)\s*\.\s*(?:json|send|sendStatus|status|render|redirect|end|sendFile|write)\s*\(/

  TOP_LEVEL_IF  = /(?<![\w$.])if\s*\(/
  SERVICE_NEW   = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*new\s+([A-Z][\w$]*)\s*\(/
  SERVICE_AWAIT = /\bawait\s+([A-Za-z_$][\w$]*)\s*\.\s*([A-Za-z_$][\w$]*)\s*\(/

  # A refusal the handler's own body runs for every anonymous caller before
  # it does anything else: `if (!req.accountability?.user) throw new
  # InvalidCredentialsError()` at its top, or one hop into a method it
  # awaits first on a service it constructs from the caller's identity
  # (`new PermissionsService({ accountability: req.accountability })`, then
  # `await service.getItemPermissions()` whose body opens with `if
  # (!this.accountability?.user) throw …`). Nil when the check sits behind
  # an earlier return/await/response/next, inside a branch or `try`, tests
  # request data, or the service was not handed the caller.
  private def handler_caller_check(endpoint : Endpoint) : String?
    handler = endpoint.handler || return
    path = handler.path || return
    line = handler.line || return
    content = read_file(path) || return
    request = request_param(content, line) || return
    body = code_only(Noir::JSRouteExtractor.definition_body(content, line))
    if check = caller_absence_refusal(body, Regex.escape(request), stop_file: path)
      return "Protected by Express handler check #{check}"
    end
    bindings = Hash(String, Tuple(String, String)).new
    body.scan(SERVICE_NEW) do |m|
      open = m.end(0) - 1
      close = Noir::JSLiteralScanner.find_matching_paren(body, open) || next
      bindings[m[1]] = {m[2], body[open + 1...close]}
    end
    return if bindings.empty?
    body.scan(SERVICE_AWAIT) do |m|
      at = m.begin(0)
      break if body[0...at].matches?(EARLIER_EXIT)
      break unless top_level?(body, at)
      klass, args = bindings[m[1]]? || break
      method_body = service_method_body(klass, m[2], content, path) || break
      check = caller_absence_refusal(method_body, "this") || break
      field = check.match(/\A!this\??\.([A-Za-z_$][\w$]*)/).try(&.[1]) || break
      # The service must have been handed the caller: `{ accountability:
      # req.accountability }`, not `{ userId: req.params.userId }` or a fixed
      # `{ accountability: { user: 'system' } }`.
      passed = args.match(/(?<![\w$])#{Regex.escape(field)}\s*:\s*(?:#{Regex.escape(request)})\s*\??\.\s*([A-Za-z_$][\w$]*)/)
      break if passed.nil? || passed[1].matches?(DATA_ROOTS)
      return "Protected by Express handler call #{klass}.#{m[2]} (#{check})"
    end
    nil
  rescue
    nil
  end

  # The name the handler defined at `line` gives the request: the first
  # parameter of the last function on that line (`asyncHandler(async (req,
  # res) => {`, `function show(request, response) {`).
  private def request_param(content : String, line : Int32) : String?
    text = content.lines[line - 1]? || return
    code = code_only(text)
    if arrow = code.rindex("=>")
      head = code[0...arrow].rstrip
      head = head.sub(/\)\s*:\s*[^()]*\z/, ")") # `): Promise<void>`
      return head.match(/([A-Za-z_$][\w$]*)\z/).try(&.[1]) unless head.ends_with?(')')
      close = head.size - 1
      depth = 0
      open = nil
      close.downto(0) do |idx|
        case head[idx]
        when ')' then depth += 1
        when '('
          depth -= 1
          if depth == 0
            open = idx
            break
          end
        end
      end
      return head[(open || return) + 1...close].match(/\A\s*([A-Za-z_$][\w$]*)/).try(&.[1])
    end
    code.match(/\bfunction\b[^(]*\(\s*([A-Za-z_$][\w$]*)/).try(&.[1])
  end

  # The first `if` at the top of `body` that tests the caller's absence on
  # `receiver` and refuses in its branch, as `<condition> (<refusal>)`; nil
  # once anything that can answer or pass the request on comes first.
  # `stop_file`: in a middleware defined there, a branch that returns
  # through a refusing function also refuses (`stop_refusal`).
  private def caller_absence_refusal(body : String, receiver : String, stop_file : String? = nil) : String?
    # `!req.user`, or no positive id: `req.uid <= 0`.
    absent = /\A(?:!\s*(?:#{receiver})((?:\s*\??\.\s*[A-Za-z_$][\w$]*)+)\s*(?:\(\s*\))?|(?:#{receiver})((?:\s*\??\.\s*[A-Za-z_$][\w$]*)+)\s*(?:<=\s*0|<\s*1))\z/
    body.scan(TOP_LEVEL_IF) do |m|
      at = m.begin(0)
      return if earlier_exit?(body, at, stop_file)
      next unless top_level?(body, at)
      # `if (x) { … } else if (!req.user) …`: a caller taking the first
      # branch never meets the check.
      next if body[0...at].rstrip.ends_with?("else")
      open = m.end(0) - 1
      close = Noir::JSLiteralScanner.find_matching_paren(body, open) || return
      condition = body[open + 1...close]
      rest = body[close + 1..]
      block_end = nil.as(Int32?)
      branch = if rest.lstrip.starts_with?('{')
                 brace = close + 1 + (rest.size - rest.lstrip.size)
                 block_end = Noir::JSLiteralScanner.find_matching_brace(body, brace) || return
                 body[brace..block_end]
               else
                 rest[0, rest.index(/[;\n]/) || rest.size]
               end
      tested = Noir::TopLevelSplit.split(condition, '|', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).reject(&.blank?).find do |part|
        next false unless hit = part.strip.match(absent)
        caller_fields?(hit[1]? || hit[2], receiver)
      end
      source = stop_file.try { |file| read_file(file) }
      if tested
        refusal = branch_refusal(branch, source, stop_file) || next
        return "#{tested.gsub(/\s+/, "")} #{refusal}"
      end
      # `if (req.isAuthenticated()) { … } else { return errorForbidden(req, res) }`:
      # the caller's presence opens the route, and the `else` an anonymous
      # caller takes refuses it.
      next unless block_end
      hit = condition.strip.match(/\A(?:#{receiver})((?:\s*\??\.\s*[A-Za-z_$][\w$]*)+)\s*(?:\(\s*\))?\z/) || next
      next unless caller_fields?(hit[1], receiver)
      refusal = else_refusal(body[block_end + 1..], source, stop_file) || next
      return "#{condition.strip.gsub(/\s+/, "")} else #{refusal}"
    end
    nil
  end

  # Whether code before `at` can answer or pass the request on, leaving
  # out a top-level `if` whose branch only refuses bad input (`if
  # (req.body.length > max) { return errorTooLong(req, res) }`, the helper
  # answering 4xx): that branch lets no caller through.
  private def earlier_exit?(body : String, at : Int32, stop_file : String?) : Bool
    prefix = body[0...at]
    return false unless prefix.matches?(EARLIER_EXIT)
    return true unless stop_file
    prefix.scan(TOP_LEVEL_IF) do |m|
      next unless top_level?(prefix, m.begin(0))
      close = Noir::JSLiteralScanner.find_matching_paren(prefix, m.end(0) - 1) || next
      rest = prefix[close + 1..]
      next unless rest.lstrip.starts_with?('{')
      brace = close + 1 + (rest.size - rest.lstrip.size)
      block_end = Noir::JSLiteralScanner.find_matching_brace(prefix, brace) || next
      next unless input_refusal?(prefix[brace..block_end], stop_file)
      prefix = prefix[0...brace] + " " * (block_end - brace + 1) + prefix[block_end + 1..]
    end
    prefix.matches?(EARLIER_EXIT)
  end

  INPUT_REFUSAL_CALL = /\A\{\s*return\s+([A-Za-z_$][\w$]*(?:\s*\.\s*[A-Za-z_$][\w$]*)*)\s*\([^;{}]*\)\s*;?\s*\}\z/
  STATUS_4XX         = /\(\s*(?:[\w$.]+\s*,\s*)*['"]?4\d\d['"]?\s*[,)]/

  # A block that is only `return f(…)` through a function whose definition
  # answers a 4xx status (`res.status(413)`, `responseError(res, '413', …)`).
  private def input_refusal?(block : String, file : String) : Bool
    call = block.match(INPUT_REFUSAL_CALL) || return false
    content = read_file(file) || return false
    target = Noir::JSHandlerResolver.resolve(call[1].gsub(/\s+/, ""), content, file) || return false
    path, line = target.path, target.line
    return false if path.nil? || line.nil?
    text = read_file(path) || return false
    Noir::CComments.strip(Noir::JSRouteExtractor.definition_body(text, line), quotes: %("'`)).matches?(STATUS_4XX)
  end

  # The last field names the caller and the first is not request data
  # (`!req.params.userId` refuses a bad URL, not an anonymous caller).
  private def caller_fields?(chain : String, receiver : String) : Bool
    fields = chain.split('.').map(&.strip.lchop('?').strip).reject(&.empty?)
    fields.last.matches?(CALLER_FIELD) && (receiver == "this" || !fields.first.matches?(DATA_ROOTS))
  end

  # How `branch` stops the caller that takes it, or nil.
  private def branch_refusal(branch : String, source : String?, stop_file : String?) : String?
    BRANCH_REFUSALS.each do |re, label|
      hit = branch.match(re) || next
      # `if (!req.user) { if (req.method !== 'GET') return res.sendStatus(401) }`
      reach = refusal_reach(branch, hit.begin(0), source) || next
      return reach == :setting ? "#{label}#{SETTING_NOTE}" : label
    end
    stop_file.try { |file| stop_refusal(branch, file) }
  end

  # The refusal in the `else` at the head of `rest` (the code after an `if`
  # block): a plain `else`, or an `else if` on a setting alone (`else if
  # (!config.allowAnonymous)`) that ends the chain. Nil for an `else if` on
  # anything else: a caller who sends the right input passes it.
  private def else_refusal(rest : String, source : String?, stop_file : String?) : String?
    head = rest.match(/\A\s*else\b\s*/) || return
    branch = rest[head.end(0)..]
    if cond = branch.match(/\Aif\s*\(/)
      source || return
      close = Noir::JSLiteralScanner.find_matching_paren(branch, cond.end(0) - 1) || return
      return unless module_state?(branch[cond.end(0)...close], source)
      inner = branch[close + 1..].lstrip
      return unless inner.starts_with?('{')
      inner_close = Noir::JSLiteralScanner.find_matching_brace(inner, 0) || return
      return if inner[inner_close + 1..].matches?(/\A\s*else\b/)
      found = branch_refusal(inner[0..inner_close], source, stop_file) || return
      return found.ends_with?(SETTING_NOTE) ? found : "#{found}#{SETTING_NOTE}"
    end
    return unless branch.starts_with?('{')
    close = Noir::JSLiteralScanner.find_matching_brace(branch, 0) || return
    branch_refusal(branch[0..close], source, stop_file)
  end

  private def top_level?(body : String, at : Int32) : Bool
    prefix = body[0...at]
    prefix.count("({[") == prefix.count(")}]")
  end

  # The body of method `name` in class `klass`, where `klass` is the class
  # `file` (whose text is `content`) imports or defines.
  private def service_method_body(klass : String, name : String, content : String, file : String) : String?
    definition = Noir::JSHandlerResolver.resolve(klass, content, file) || return
    path = definition.path || return
    line = definition.line || return
    text = read_file(path) || return
    lines = text.lines
    head = lines[line - 1]? || return
    return unless head.matches?(/\bclass\s+#{Regex.escape(klass)}\b/)
    class_start = lines[0...line - 1].sum { |row| row.size + 1 }
    open = text.index('{', class_start) || return
    close = Noir::JSLiteralScanner.find_matching_brace(text, open) || return
    method = text[open...close].match(/^[ \t]*(?:(?:public|private|protected|static|override|async|readonly)\s+)*#{Regex.escape(name)}\s*(?:<[^>\n]*>)?\s*\(/m) || return
    method_line = text[0, open + method.begin(0)].count('\n') + 1
    code_only(Noir::JSRouteExtractor.definition_body(text, method_line))
  end

  private def check_mounted_use_auth(endpoint : Endpoint) : String?
    url = endpoint.url

    @mounted_auth_rules.each do |rule|
      if prefix_covers?(rule[:prefix], url)
        return rule[:description]
      end
    end

    nil
  end
end
