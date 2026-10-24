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
  HANDLER_RESPONSE = /\b(?:res|response)\s*\.\s*(?:json|send|render|redirect|sendFile|end|status)\s*\(/

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

          if match = stripped.match(MOUNTED_USE)
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
      args = call_args(route_text)
      (args || [route_text]).each_with_index do |arg, idx|
        last = !args.nil? && idx == args.size - 1
        description = guard_description(arg, path_info.path, handler_position: last) || next
        endpoint.add_tag(Tag.new("auth", description, "express_auth"))
        # `app.get('/api/Users', security.isAuthorized())`: the guard is the
        # only callable, so the analyzer reported it as the handler. It is
        # not one — the request falls through to the next match.
        endpoint.handler = nil if args && idx == args.size - 1
        return endpoint
      end

      receiver_description ||= check_receiver_use_auth(path_info.path, lines, line_num - 1)
    end

    # Check app.use() level auth: the router this route was registered on
    # first, then a path-scoped mount.
    description = receiver_description || check_mounted_use_auth(endpoint)
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
    AUTH_MIDDLEWARE_NAMES.each do |pattern|
      if match = code.match(pattern)
        return "Protected by Express #{match[0]} middleware"
      end
    end

    if resolved = refusing_definition(arg, file, handler_position)
      name, evidence = resolved
      "Protected by Express #{name} (#{evidence}) middleware"
    end
  end

  # `arg` resolved to its definition (same file or a relative import) and
  # the marker there that lets it refuse a request; nil for an inline
  # closure, a package import, a body that only decodes and continues, or
  # — in the handler position — one that serves the request itself.
  private def refusing_definition(arg : String, file : String, handler_position : Bool, depth : Int32 = 0) : {String, String}?
    content = read_file(file) || return
    handler = Noir::JSHandlerResolver.resolve(arg, content, file) || return
    path, line = handler.path, handler.line
    return if path.nil? || line.nil?
    lines = read_file_lines(path) || return
    if elements = middleware_array(lines, line - 1)
      return if depth >= MAX_ARRAY_DEPTH
      elements.each do |element|
        found = refusing_definition(element, path, false, depth + 1)
        return {"#{handler.name.gsub(/\s+/, "")} > #{found[0]}", found[1]} if found
      end
      return
    end
    body = definition_extent(lines, line - 1)
    return if body.first?.try(&.matches?(ERROR_HANDLER_SIGNATURE))
    code = code_only(body.join("\n"))
    evidence = anonymous_refusal(code) || return
    return if handler_position && code.gsub(REFUSING_DEFINITION, "").matches?(HANDLER_RESPONSE)
    {handler.name.gsub(/\s+/, ""), evidence.gsub(/\bnew\s+/, "new ").gsub(/(?<!\bnew)\s+/, "").chomp('(')}
  rescue
    nil
  end

  MAX_ARRAY_DEPTH = 4

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
  private def anonymous_refusal(code : String) : String?
    code.scan(REFUSING_DEFINITION) do |m|
      at = m.begin(0)
      return if code[0...at].matches?(ANONYMOUS_PASS_THROUGH)
      next if presence_gated?(code, at)
      return m[0]
    end
    nil
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
      break if depth <= 0
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
    Noir::TopLevelSplit.split(statement[open_paren + 1...close_paren], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
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
