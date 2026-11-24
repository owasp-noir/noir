require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/js_handler_resolver"
require "../../../utils/js_literal_scanner"
require "../../../utils/top_level_split"
require "./js_object_literal"
require "./js_middleware_access"
require "../../../miniparsers/js_mount_prefix"
require "../../../models/code_locator"

@[Noir::TaggerFor(key: "express_auth", name: "Express Auth Tagger", desc: "Identifies Express.js authentication patterns (Passport, JWT, auth middleware)", order: 40)]
class ExpressAuthTagger < FrameworkTagger
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
  #
  # `sendError(res, 401, …)` hands the response and a 401 to a reply helper
  # (a helper's 403 is as often about the payload as the caller). An
  # express-basic-auth middleware refuses where it is run,
  # not where it is built: see `basic_auth_runs`.
  REFUSING_DEFINITION = /\bexpress[jJ]wt\s*\(|\bpassport\.authenticate\s*\(|\b[A-Za-z_$][\w$]*\s*\(\s*(?:res|response)\s*,\s*401\b|(?:\b\w+\.)?(?:status|sendStatus|send)\s*\(\s*40[13]\s*\)?|\bnext\s*\(\s*(?:new\s+)?(?:[\w$]+\.)*\w*(?:Unauthori[sz]ed|Forbidden|NoPermission|PermissionDenied)\w*|\bcreateError\s*\(\s*40[13]\b|\bnext\s*\(\s*\{[^}]*\b40[13]\b/

  # `(err, req, res, next)`: an error handler answers 401 *for* a guard;
  # it is not one.
  ERROR_HANDLER_SIGNATURE = /\(\s*err\w*\s*[,:]/

  # A definition that answers the request itself, refusals aside: in the
  # handler position that is the handler (`login()` answers 401 to a wrong
  # password), not a guard in front of one.
  HANDLER_RESPONSE = /\b(?:res|response)\s*\.\s*(?:json|send|sendStatus|render|redirect|sendFile|download|attachment|end|status)\s*\(|\.pipe\s*\(\s*(?:res|response)\s*\)/

  @method : String?
  @url : String?

  def self.target_techs : Array(String)
    ["js_express"]
  end

  private record GuardEvidence, description : String, followed : Bool

  @guard_followed = false
  @last_refusal_followed = false

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    endpoints.map! do |endpoint|
      @guard_followed = false
      endpoint = check_endpoint(endpoint)
      if !@guard_followed && endpoint.tags.any? { |tag| tag.tagger == "express_auth" && tag.name.in?("auth", "authz") }
        # ponytail: per endpoint, not per guard; add a field on ai_context.guards if readers need to distinguish individual guards.
        endpoint.resolution = (endpoint.resolution || {} of String => String).merge({"guard" => Endpoint::RESOLUTION_HEURISTIC})
      end
      endpoint
    end
  end

  private def check_endpoint(endpoint : Endpoint) : Endpoint
    @method = endpoint.method
    @url = endpoint.url
    check_route(endpoint)
  ensure
    @method = nil
    @url = nil
  end

  # Whether every auth-name mention in `code` is a non-negated part of an
  # `if` condition whose branch refuses nobody.
  private def feature_tests_only?(code : String) : Bool
    ifs = [] of {Int32, Int32}
    code.scan(IF_HEAD) do |m|
      open = m.end(0) - 1
      close = Noir::JSLiteralScanner.find_matching_paren(code, open) || next
      ifs << {open, close}
    end
    AUTH_MIDDLEWARE_NAMES.all? do |pattern|
      code.scan(pattern).all? do |hit|
        at = hit.begin(0)
        range = ifs.reverse.find { |r| r[0] < at && at < r[1] }
        next false unless range
        open, close = range
        part = code[open + 1...at].split(/&&|\|\|/).last
        next false if part.includes?('!')
        rest = code[close + 1..]
        branch = if rest.lstrip.starts_with?('{')
                   brace = close + 1 + (rest.size - rest.lstrip.size)
                   code[brace..(Noir::JSLiteralScanner.find_matching_brace(code, brace) || code.size - 1)]
                 else
                   rest[0, rest.index(/[;\n]/) || rest.size]
                 end
        BRANCH_REFUSALS.keys.none? { |re| branch.matches?(re) }
      end
    end
  end

  private def check_route(endpoint : Endpoint) : Endpoint
    scoped_description = nil
    scoped_steps = nil.as(Array({RouteMiddleware, GuardEvidence?})?)
    handler_inline = false
    handler_direct = false

    endpoint.details.code_paths.each do |location|
      chain = location.route_middleware || next
      direct = nil.as(String?)
      judged = [] of {RouteMiddleware, GuardEvidence?}
      chain.each do |step|
        local = step.origin.in?(:route, :helper)
        inline = step.source.matches?(Noir::JSRouteExtractor::INLINE_FUNCTION_RE)
        handler_direct ||= step.origin == :route
        handler_inline ||= step.origin == :route && step.handler_position && inline
        evidence = judge_step(step)
        judged << {step, evidence}
        next unless evidence
        if local
          @guard_followed ||= evidence.followed && step.origin == :route
          next if direct
          direct = evidence.description
          if step.handler_position && !inline && wrapper_guard(step.source, step.file).nil?
            endpoint.handler = nil
          end
        elsif scoped_description.nil?
          via = step.prefix && step.verb == "use" ? "app.use()" : "#{step.receiver}.#{step.verb}()"
          scoped_description = "#{evidence.description} via #{via}"
          scoped_description += " on #{step.prefix}" if step.prefix
          scoped_steps = judged
        end
      end
      if direct
        endpoint.add_tag(Tag.new("auth", direct, "express_auth", requires: chain_requires(endpoint, judged)))
        return endpoint
      end
    end

    if scoped_description
      endpoint.add_tag(Tag.new("auth", scoped_description, "express_auth", requires: scoped_steps.try { |steps| chain_requires(endpoint, steps) }))
    elsif evidence = handler_caller_check(endpoint)
      endpoint.add_tag(Tag.new("auth", evidence.description, "express_auth"))
      handler = endpoint.handler
      bound = handler && endpoint.details.code_paths.any? do |path|
        source = read_file(path.path) || next false
        target = read_file(handler.path || "") || next false
        declaration = read_file_lines(handler.path || "").try { |lines| lines[(handler.line || 1) - 1]? } || ""
        guard_definition_followed?(handler.name, path.path, source, target, declaration, handler.path || "")
      end
      @guard_followed ||= evidence.followed && handler_direct && (bound || handler_inline) && endpoint.resolution.try(&.["handler"]?) != Endpoint::RESOLUTION_HEURISTIC
    end
    endpoint
  end

  private def judge_step(step : RouteMiddleware) : GuardEvidence?
    method, url = @method, @url
    # The unresolved-prefix fallback was judged before any endpoint was
    # known. A route-specific branch cannot strengthen that evidence.
    @method = @url = nil if step.origin == :fallback
    guard_description(step.source, step.file, handler_position: step.handler_position)
  ensure
    @method, @url = method, url
  end

  # What every step of the route's chain asks of a caller, joined with AND.
  # A guard step whose package call is not read keeps the default reading;
  # a scope or claim check from a known package adds its own. Nil when no
  # step reads more exactly than the default, when the endpoint has another
  # registration (another chain may serve it), or when a step's scope was
  # guessed for an unread mount prefix.
  private def chain_requires(endpoint : Endpoint, judged : Array({RouteMiddleware, GuardEvidence?})) : Array(Access::Clause)?
    return if endpoint.details.code_paths.count(&.route_middleware) > 1
    return if endpoint.url.includes?(Noir::JSMountPrefix::UNREAD)
    return if endpoint.resolution.try { |found| found.values.includes?(Endpoint::RESOLUTION_UNRESOLVED) }
    return if judged.any? { |step, _| step.origin == :fallback }
    exact = false
    clauses = [] of Access::Clause
    judged.each do |step, evidence|
      reading = step_reading(step)
      text = step_text(step.source)
      cnf = if evidence
              reading || JsMiddlewareAccess.fallback(text)
            elsif reading && reading.none? { |clause| clause.any?(&.kind.authenticated?) }
              reading
            end
      next unless cnf
      exact ||= !reading.nil?
      clauses.concat(Access.clauses(cnf, text, step.file))
    end
    return unless exact
    clauses.uniq!(&.any_of)
    clauses unless clauses.size > Access::MAX_CLAUSES
  end

  # An inline function step is its whole body.
  private def step_text(source : String) : String
    text = source.gsub(/\s+/, " ").strip
    text.size > 120 ? "#{text[0, 117]}..." : text
  end

  # The step as a call of a known package's middleware: written at the step,
  # or through a name the step's module binds once, and to nothing more, to
  # such a call (`const auth = basicAuth({ … });`).
  private def step_reading(step : RouteMiddleware) : Access::CNF?
    content = read_file(step.file) || return
    imports = Noir::JSHandlerResolver.imports_of(content, step.file)
    text = step.source.strip
    if text.matches?(BARE_IDENT) && !imports.has_key?(text)
      return unless guard_binding_followed?(text, step.file)
      code = Noir::CComments.strip(content, quotes: %("'`))
      decl = code.match(/\b(?:const|let|var)\s+#{Regex.escape(text)}\s*=\s*/) || return
      text = local_binding_expr(code, text) || return
      return unless code.index(text, decl.end(0)) == decl.end(0)
      return unless code[decl.end(0) + text.size..].matches?(/\A[ \t]*(?:;|\n|\z)/)
      return if code[decl.end(0) + text.size..].lstrip.starts_with?('.')
    end
    JsMiddlewareAccess.parse(text, imports).try { |call| JsMiddlewareAccess.read(call) }
  end

  # Why `arg` (one argument of a registration, as written) guards the
  # route, or nil. Passport needs its strategy string; the inline and named
  # markers are identifiers, so they match the code alone; anything else is
  # followed to its definition.
  private def guard_description(arg : String, file : String, handler_position : Bool = false) : GuardEvidence?
    if arg.matches?(PASSPORT_PATTERN)
      strategies = arg.scan(/passport\.authenticate\s*\(\s*['"]([^'"]+)['"]/).map(&.[1])
      strategy = strategies.empty? ? "unknown" : strategies.find { |name| !name.matches?(PASSPORT_LOGIN_STRATEGY) }
      return strategy ? GuardEvidence.new("Protected by Passport.js #{strategy} strategy", false) : nil
    end

    code = code_only(arg)
    if JWT_MIDDLEWARE_PATTERNS.any? { |pattern| code.matches?(pattern) }
      # `credentialsRequired: false` is express-jwt's optional mode: the
      # request continues with no user, so the call is not a guard.
      return if credentials_optional?(code)
      return GuardEvidence.new("Protected by Express JWT middleware", false)
    end
    alias_desc, jwt_handled = judge_jwt_alias(arg, file)
    return alias_desc.try { |description| GuardEvidence.new(description, false) } if jwt_handled
    # `app.get("/x", basicAuth({ users }), h)`: the express-basic-auth
    # middleware mounted as built.
    if (factory = code.match(/\A\s*([A-Za-z_$][\w$]*)\s*\(/)) && basic_auth_factories(read_file(file) || "").includes?(factory[1])
      return GuardEvidence.new("Protected by Express #{factory[1]} (express-basic-auth) middleware", false)
    end
    # `[...middlewares, middleware.assert.post]`: Express flattens an array
    # of handlers into the chain, so each element is a step of its own.
    if elements = array_elements(code)
      first = nil.as(GuardEvidence?)
      followed = false
      elements.each do |element|
        found = guard_description(element.strip.lchop("...").strip, file) || next
        first ||= found
        followed ||= found.followed
      end
      return first.try { |found| GuardEvidence.new(found.description, followed) }
    end
    # `asyncHandler(adminOnly)`, `withAuth(list)`: the wrapper is judged by
    # its own definition, and what it wraps keeps its position's judgement.
    if wrapped = unwrapped_arg(arg, file)
      if found = wrapper_guard(arg, file)
        return found
      end
      # A forwarding shape (or wrapper name) does not prove the inner step runs.
      return guard_description(wrapped, file, handler_position).try { |inner| GuardEvidence.new(inner.description, false) }
    end
    # A name inside the handler closure is a call or a read, not a step.
    # It still stands in for a check `handler_caller_check` cannot read
    # (one inside a `.then` callback), but not when every mention is a
    # plain test whose branch refuses nobody (`if (config.debug &&
    # req.isAuthenticated()) log()`).
    if (named = name_guard(code)) && !(handler_position && arg.matches?(Noir::JSRouteExtractor::INLINE_FUNCTION_RE) && feature_tests_only?(code))
      return GuardEvidence.new(named, false)
    end

    if resolved = refusing_definition(arg, file, handler_position)
      name, evidence, followed = resolved
      GuardEvidence.new("Protected by Express #{name} (#{evidence}) middleware", followed)
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

  private def unwrapped_arg(arg : String, file : String) : String?
    content = read_file(file) || return
    Noir::JSHandlerResolver.unwrap(code_only(arg).strip, content, file, guards: true).try(&.[0])
  end

  # The guard a wrapper call (`withAuth(list)`, `asyncHandler(withAuth(list))`)
  # itself is: a wrapper whose definition refuses the caller before handing
  # the request on.
  private def wrapper_guard(arg : String, file : String, depth : Int32 = 0) : GuardEvidence?
    return if depth > 3
    content = read_file(file) || return
    wrapped = Noir::JSHandlerResolver.unwrap(code_only(arg).strip, content, file, guards: true) || return
    if found = refusing_definition(wrapped[2], file, false)
      return GuardEvidence.new("Protected by Express #{found[0]} (#{found[1]}) wrapper", false)
    end
    wrapper_guard(wrapped[0], file, depth + 1).try { |inner| GuardEvidence.new(inner.description, false) }
  end

  # `arg` resolved to its definition (same file or a relative import) and
  # the marker there that lets it refuse a request; nil for an inline
  # closure, a package import, a body that only decodes and continues, or
  # — in the handler position — one that serves the request itself.
  # Judged once per step: a shared middleware array is spread into hundreds
  # of routes.
  @refusals = Hash(Tuple(String, String, Bool, Int32, String?, String?), {String, String, Bool}?).new

  @unique_guard_bindings = Hash(String, Set(String)).new

  # A single module binding is followed; nested or shadowed declarations
  # stay matched until the resolver carries lexical scopes.
  private def guard_binding_followed?(arg : String, file : String) : Bool
    ref = arg.strip.match(Noir::JSHandlerResolver::REFERENCE_RE) || return false
    names = @unique_guard_bindings.put_if_absent(file) do
      source = read_file(file) || ""
      counts = Hash(String, Int32).new(0)
      module_names = Set(String).new
      Noir::TreeSitter.parse_js_family(source, file) do |root|
        Noir::TreeSitter.walk(root) do |node|
          pattern = case Noir::TreeSitter.node_type(node)
                    when "variable_declarator", "function_declaration", "function_expression", "class_declaration"
                      Noir::TreeSitter.field(node, "name")
                    when "assignment_expression", "augmented_assignment_expression", "for_in_statement"
                      Noir::TreeSitter.field(node, "left")
                    when "update_expression"
                      Noir::TreeSitter.field(node, "argument")
                    when "arrow_function", "catch_clause"
                      Noir::TreeSitter.field(node, "parameter")
                    when "formal_parameters", "import_clause"
                      node
                    end
          next unless pattern
          identifiers = Noir::TreeSitter.node_text(pattern, source).scan(/[A-Za-z_$][\w$]*/).map(&.[0])
          identifiers.each { |name| counts[name] += 1 }
          owner = node
          while parent = Noir::TreeSitter.parent(owner)
            kind = Noir::TreeSitter.node_type(parent)
            if kind == "program"
              identifiers.each { |name| module_names << name }
              break
            end
            break unless kind.in?("lexical_declaration", "variable_declaration", "export_statement", "import_statement")
            owner = parent
          end
        end
      end
      module_names.select { |name| counts[name] == 1 }.to_set
    end
    names.includes?(ref[1])
  end

  @guard_links = Hash({String, String, String}, Bool).new
  @guard_exports = Hash(String, {String, Bool}).new

  private def guard_definition_followed?(arg : String, file : String, source : String, target : String, declaration : String, target_file : String) : Bool
    @guard_links.put_if_absent({arg, file, target_file}) do
      next false unless guard_binding_followed?(arg, file)
      ref = arg.strip.match(Noir::JSHandlerResolver::REFERENCE_RE) || next false
      member = ref[2].split('.').map(&.strip).reject(&.empty?).last?
      imported = Noir::JSHandlerResolver.imports_of(source, file)[ref[1]]?
      # The resolver also falls back to a module's default export for a named
      # member it cannot find; that is a match, not an export link.
      if imported && member.nil? && imported[1].nil?
        next false unless declaration.matches?(Noir::JSHandlerResolver::DEFAULT_EXPORT_RE)
        next !declaration.matches?(/\bmodule\s*\.\s*exports\b/) || guard_binding_followed?("module", target_file)
      end
      wanted = member || imported.try(&.[1]) || ref[1]
      name = Regex.escape(wanted)
      next declaration.matches?(/(?<![\w$])#{name}(?![\w$])/) unless imported || member
      next false if declaration.matches?(Noir::JSHandlerResolver::DEFAULT_EXPORT_RE)
      next false unless guard_binding_followed?(wanted, target_file)
      exports, module_written = @guard_exports.put_if_absent(target_file) do
        {Noir::JSHandlerResolver.export_aliases(target), target.matches?(/\bmodule\s*\.\s*exports\s*=/)}
      end
      next false if module_written
      declaration.matches?(/\bexport\s+(?:async\s+)?(?:function|const|let|var|class)\s+#{name}\b|(?:#{exports})\s*\.\s*#{name}\s*=/)
    end
  end

  FACTORY_CALL = /\A\s*((?:[A-Za-z_$][\w$]*\s*\.\s*)*[A-Za-z_$][\w$]*)\s*\(/

  # `auth('manageUsers')` as `auth()`: the middleware a factory builds is
  # judged by the factory's definition, whatever it was handed.
  private def factory_call(arg : String) : String?
    head = arg.match(FACTORY_CALL) || return
    open = head.end(0) - 1
    close = Noir::JSLiteralScanner.find_matching_paren(arg, open) || return
    return if arg[open + 1...close].blank? || !arg[close + 1..].blank?
    "#{head[1]}()"
  end

  private def refusing_definition(arg : String, file : String, handler_position : Bool, depth : Int32 = 0) : {String, String, Bool}?
    key = {arg, file, handler_position, depth, @method, @url}
    return @refusals[key] if @refusals.has_key?(key)
    @refusals[key] = judge_definition(arg, file, handler_position, depth)
  end

  private def judge_definition(arg : String, file : String, handler_position : Bool, depth : Int32) : {String, String, Bool}?
    content = read_file(file) || return
    handler = Noir::JSHandlerResolver.resolve(arg, content, file) ||
              factory_call(arg).try { |call| Noir::JSHandlerResolver.resolve(call, content, file) } || return
    path, line = handler.path, handler.line
    return if path.nil? || line.nil?
    lines = read_file_lines(path) || return
    # `const auth = basicAuth({…})`, `module.exports = basicAuth({…})`: the
    # name is the express-basic-auth middleware itself.
    if (built = code_only(lines[line - 1]).match(/(?:=|\bexport\s+default)\s*([A-Za-z_$][\w$]*)\s*\(/)) &&
       basic_auth_factories(read_file(path) || "").includes?(built[1])
      return {handler.name.gsub(/\s+/, ""), built[1], false}
    end
    if elements = middleware_array(lines, line - 1)
      return if depth >= MAX_ARRAY_DEPTH
      # `open.splice(0, 1)`: what the array holds at the route is not its literal.
      return if (read_file(path) || "").matches?(/(?<![\w$.])#{Regex.escape(handler.name.split('.').last)}\s*\.\s*(?:splice|push|pop|shift|unshift|length\s*=)/)
      first = nil.as({String, String, Bool}?)
      followed = false
      elements.each do |element|
        element = element.strip.lchop("...").strip
        if found = refusing_definition(element, path, false, depth + 1)
          first ||= {"#{handler.name.gsub(/\s+/, "")} > #{found[0]}", found[1], found[2]}
          followed ||= found[2]
        elsif named = name_guard(element)
          first ||= {"#{handler.name.gsub(/\s+/, "")} > #{element.gsub(/\s+/, "")}", named, false}
        end
      end
      return first.try { |found| {found[0], found[1], followed && guard_definition_followed?(arg, file, content, read_file(path) || "", lines[line - 1], path)} }
    end
    # `export default asyncHandler(handler)`: the definition is the wrapped one.
    if depth < MAX_ARRAY_DEPTH && (call = code_only(lines[line - 1]).match(WRAPPED_EXPORT))
      found = refusing_definition(call[1], path, handler_position, depth + 1) || return
      return {handler.name.gsub(/\s+/, ""), found[1], false}
    end
    body = definition_extent(lines, line - 1)
    return if body.first?.try(&.matches?(ERROR_HANDLER_SIGNATURE))
    code = code_with_words(body.join("\n"))
    # A router factory (`app.use('/things', makeRouter(db))`) is a mount: a
    # refusal inside one of its routes guards that route, not the mount.
    return if code.matches?(Noir::JSRouteExtractor::ROUTER_BODY_RE)
    evidence = (anonymous_refusal(code, read_file(path)) || identity_throw(code)).try do |found|
      found, note = found.partition(SETTING_NOTE)
      found.gsub(/\bnew\s+/, "new ").gsub(/(?<!\bnew)\s+/, "").chomp('(').sub(/\Athrownew\b/, "throw new") + note
    end
    first = caller_stop(path, line)
    followed = !first.nil? && @last_refusal_followed
    evidence ||= first
    unless evidence
      evidence = delegated_stop(path, line) || return
      followed = @last_refusal_followed
    end
    # In the handler position a definition that answers the request is the
    # handler; one that calls `next()` on success is middleware all the same
    # (`app.use('/private', auth)`).
    return if handler_position && !code.matches?(BARE_NEXT) && code.gsub(REFUSING_DEFINITION, "").matches?(HANDLER_RESPONSE)
    {handler.name.gsub(/\s+/, ""), evidence, followed && !evidence.ends_with?(SETTING_NOTE) && guard_definition_followed?(arg, file, content, read_file(path) || "", lines[line - 1], path)}
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

  # `const session = await validateSession(req, res); if (!session) return;`:
  # the middleware hands the request and the response to a helper, and stops
  # without `next` when it gets nothing back. It is a guard when the helper's
  # own definition refuses an anonymous caller (answers 401/403) and every
  # `return` but its last hands back nothing: a helper that returns the
  # response it refused on (`return res.status(401).send()`), or an object,
  # gives a truthy value, and the middleware goes on to `next()`.
  private def delegated_stop(path : String, line : Int32) : String?
    content = read_file(path) || return
    request = request_param(content, line) || return
    body = code_with_words(Noir::JSRouteExtractor.definition_body(content, line))
    body.scan(/(?<![\w$.])(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*(?::[^=;]+)?=\s*(await\s+)?([A-Za-z_$][\w$]*)\s*\(\s*#{Regex.escape(request)}\s*,\s*[A-Za-z_$][\w$]*\s*\)/) do |call|
      return if earlier_exit?(body, call.begin(0), nil)
      next unless top_level?(body, call.begin(0))
      found = delegated_check(body, call, content, path)
      return found if found
    end
    nil
  end

  DELEGATED_FALSY_RETURN = /\Areturn\s*(?:;|\}|\z|null\b|undefined\b|false\b)/

  private def delegated_check(body : String, call : Regex::MatchData, content : String, path : String) : String?
    test = body.match(/(?<![\w$.])if\s*\(\s*!\s*#{Regex.escape(call[1])}\s*\)/, call.end(0)) || return
    between = body[call.end(0)...test.begin(0)]
    return if !top_level?(body, test.begin(0)) || earlier_exit?(between, between.size, nil)
    rest = body[test.end(0)..]
    stripped = rest.lstrip
    branch = if stripped.starts_with?('{')
               brace = test.end(0) + (rest.size - stripped.size)
               body[brace + 1...(Noir::JSLiteralScanner.find_matching_brace(body, brace) || return)]
             else
               stripped[0, stripped.index(/[;\n]/) || stripped.size]
             end
    return unless unconditional_return?(branch)
    helper = Noir::JSHandlerResolver.resolve(call[3], content, path) || return
    helper_path, helper_line = helper.path, helper.line
    return if helper_path.nil? || helper_line.nil?
    text = read_file(helper_path) || return
    # An `async` helper called without `await` hands back a Promise, never falsy.
    return if call[2]?.nil? && code_only(text.lines[helper_line - 1]? || "").matches?(/\basync\b/)
    reply = Noir::JSRouteExtractor.definition_params(text, helper_line).try(&.[1]?).presence || return
    helper_body = code_only(Noir::JSRouteExtractor.definition_body(text, helper_line))
    return if helper_body.matches?(/\breturn\s+(?:await\s+)?#{Regex.escape(reply)}\b/)
    returns = [] of Int32
    helper_body.scan(/\breturn\b/) { |m| returns << m.begin(0) }
    return if returns.size < 2 || returns[0...-1].any? { |at| !helper_body[at..].matches?(DELEGATED_FALSY_RETURN) }
    refusal = anonymous_refusal(helper_body, text) || return
    first = caller_stop(helper_path, helper_line)
    @last_refusal_followed = !first.nil? && @last_refusal_followed && guard_definition_followed?(call[3], path, content, text, text.lines[helper_line - 1], helper_path)
    "#{call[3]}() #{refusal}"
  end

  # Whether `branch` (a block's inside, or one statement) leaves the
  # middleware without `next`: a `return` of its own, not one under a
  # further `if (...)` / `else` or inside a callback.
  private def unconditional_return?(branch : String) : Bool
    return false if branch.matches?(/\bnext\b/)
    branch.scan(/\breturn\b/) do |m|
      next unless top_level?(branch, m.begin(0))
      before = branch[0...m.begin(0)].rstrip
      return true unless before.ends_with?(')') || before.ends_with?("else")
    end
    false
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
    refusal = anonymous_refusal(body, caller_checked: true)
    redirects = body.matches?(/\b(?:res|response)\s*\.\s*redirect\s*\(/)
    return unless refusal || redirects
    @last_refusal_followed = !top_refusal(body, nil, nil).nil? if redirects && refusal.nil?
    @last_refusal_followed = false if body.matches?(BARE_NEXT)
    # `showPublic` redirects one caller and renders the page for the rest.
    return if success_response?(body)
    @last_refusal_followed &&= reach != :setting && first_refusal?(branch, call.begin(0)) && guard_definition_followed?(call[1].gsub(/\s+/, ""), file, content, text, text.lines[line - 1], path)
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
    text = lines[idx..].join("\n")
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
  FOLLOWED_RESPONSE = /\A(?:res|response)\s*\.\s*(?:sendStatus\s*\(\s*40[13]\b|status\s*\(\s*40[13]\s*\)\s*\.\s*(?:json|send|end|render)\s*\()/

  private def followed_absence?(condition : String) : Bool
    condition.strip.matches?(MISSING_CALLER_FACTORY) &&
      condition.matches?(/\A\s*!\s*(?:req|request)(?:\s*\??\.\s*[A-Za-z_$][\w$]*)+(?:\s*\(\s*\))?\s*\z/)
  end

  private def anonymous_refusal(code : String, source : String? = nil, caller_checked : Bool = false) : String?
    @last_refusal_followed = false
    by_setting = nil.as(String?)
    hits = [] of Tuple(Int32, String, Bool)
    code.scan(REFUSING_DEFINITION) do |m|
      label = m[0]
      # `sendTextMessage(response, 401`: close the call it names.
      label += ")" * (label.count('(') - label.count(')')) if label.count('(') > label.count(')') && !label.ends_with?('(')
      conditions = enclosing_conditions(code, m.begin(0))
      followed = code[m.begin(0)..].matches?(FOLLOWED_RESPONSE) &&
                 conditions.all? { |test| followed_absence?(test) || test.strip.matches?(METHOD_TEST) } &&
                 (caller_checked || conditions.any? { |test| followed_absence?(test) }) && guard_prefix_read?(code[0...m.begin(0)])
      hits << {m.begin(0), label, followed}
    end
    hits.concat(basic_auth_runs(code, source).map { |at, label| {at, label, false} }) if source
    # `if (!req.session.userId) return sendError(res, 403, …)`: a helper's
    # 403 counts when the branch it is in is about a missing caller.
    code.scan(HELPER_FORBIDDEN) do |m|
      if enclosing_conditions(code, m.begin(0)).any?(&.matches?(MISSING_CALLER))
        hits << {m.begin(0), "#{m[0]})", false}
      end
    end
    # `if (!req.auth.isMaster) throw createSanitizedHttpError(403, …)`: an
    # HTTP-error factory handed a literal 401/403, in a missing-caller branch
    # that leaves the request: the factory call itself is thrown, returned or
    # passed to `next`, or the branch returns/throws. `req.authError =
    # createHttpError(401)` followed by `next()` is optional auth.
    code.scan(ERROR_FACTORY_FORBIDDEN) do |m|
      at = m.begin(0)
      refuses = enclosing_branches(code, at).any? do |condition, branch|
        condition.matches?(MISSING_CALLER_FACTORY) && !branch.matches?(/\bnext\s*\(\s*\)/) && factory_refused?(code[0...at], branch)
      end
      hits << {at, "#{m[0]})", false} if refuses
    end
    hits.sort_by!(&.[0]).each do |at, label, followed|
      return by_setting if code[0...at].matches?(ANONYMOUS_PASS_THROUGH)
      next if presence_gated?(code, at)
      case refusal_reach(code, at, source)
      when :always
        @last_refusal_followed = followed
        return label
      when :setting then by_setting ||= "#{label}#{SETTING_NOTE}"
      end
    end
    by_setting
  end

  # The name an express-basic-auth import is bound to in a file.
  BASIC_AUTH_IMPORT = /(?:\bimport\s+([A-Za-z_$][\w$]*)\s+from|\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*require\s*\()\s*['"]express-basic-auth['"]/

  # Where `code` runs an express-basic-auth middleware: the factory (as the
  # file imports it) called and the result called on the request
  # (`basicAuth({…})(req, res, next)`) or returned, or the variable it is
  # assigned to called on the request or returned. Each is a 401 for a
  # caller without credentials, under the conditions around the *run*:
  # one built and never run, or a local `basicAuth({ user, pass })` that
  # builds an outbound header, refuses nothing.
  HELPER_FORBIDDEN        = /\b[A-Za-z_$][\w$]*\s*\(\s*(?:res|response)\s*,\s*403\b/
  ERROR_FACTORY_FORBIDDEN = /\b(?:create\w*Error|\w*HttpError)\s*\(\s*40[13]\s*[,)]/
  FACTORY_APPLIED         = /(?:\bthrow\s+(?:new\s+)?|\breturn\s+(?:next\s*\(\s*)?|\bnext\s*\(\s*)\z/
  # `!req.user`, `!req.session.userId`, `!req.session`: no caller. Not
  # `!req.session.cart`, a session without a cart.
  MISSING_CALLER = /!\s*(?:req|request)\s*\.\s*(?:(?:session\s*\??\.\s*)?(?:user\w*|uid|account\w*|auth\w*|token\w*|logged\w*|isAuthenticated|passport|identity|principal)\b|session\s*(?:\)|\|\||&&))/
  # The factory rule's own test: also rejects `!!req.user` and `req.userAgent`.
  MISSING_CALLER_FACTORY = /(?<!!)!\s*(?:req|request)\s*\.\s*(?:(?:session\s*\??\.\s*)?(?:user(?:_?(?:id|ID|Id)|Info|name|Name|Data|Obj|Session)?\b|uid|account\w*|auth\w*|token\w*|logged\w*|isAuthenticated|passport|identity|principal)\b|session\s*(?:\)|\|\||&&))/

  # The names `source` binds the express-basic-auth factory to.
  private def basic_auth_factories(source : String) : Array(String)
    return [] of String unless source.includes?("express-basic-auth")
    source.scan(BASIC_AUTH_IMPORT).compact_map { |im| im[1]? || im[2]? }
  end

  private def basic_auth_runs(code : String, source : String) : Array(Tuple(Int32, String))
    runs = [] of Tuple(Int32, String)
    basic_auth_factories(source).each do |factory|
      name = Regex.escape(factory)
      code.scan(/(?<![\w$.])#{name}\s*\(/) do |call|
        open = call.end(0) - 1
        close = Noir::JSLiteralScanner.find_matching_paren(code, open) || next
        before = code[0...call.begin(0)]
        after = code[(close + 1)..]
        if after.matches?(/\A\s*\(\s*(?:req|request)\b/) || before.matches?(/\breturn\s*\z/)
          runs << {call.begin(0), factory}
        elsif bound = before.match(/(?<![\w$.])([A-Za-z_$][\w$]*)\s*=\s*\z/)
          variable = Regex.escape(bound[1])
          code.scan(/(?<![\w$.])#{variable}\s*\(\s*(?:req|request)\b|\breturn\s+#{variable}\b/) do |run|
            runs << {run.begin(0), factory} if run.begin(0) > close
          end
        end
      end
    end
    runs.uniq!
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
  # A read of configuration: `Settings.get("disableAuth")`, `config.x`,
  # `getSetting("y")`, `process.env.Z`.
  SETTING_READ = /\A(?:[\w$]+\s*\.\s*)*\w*(?:[sS]ettings?|[cC]onfig)\w*\s*[.(]|\Aprocess\s*\.\s*env\b/

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

  # Whether the error built right after `head` is what refuses: thrown,
  # returned or handed to `next(...)` as written, or kept in a local that
  # `branch` throws, returns, passes to `next`, or answers with
  # (`res.status(error.status)`). Stashing it (`req.authError = …`) is not.
  private def factory_refused?(head : String, branch : String) : Bool
    return true if head.matches?(FACTORY_APPLIED)
    name = head.match(/\b(?:const|let|var)\s+(\w+)\s*(?::[^=\n]+)?=\s*\z/).try(&.[1]) || return false
    branch.matches?(/\b(?:throw|return)\s+#{Regex.escape(name)}\b|\bnext\s*\(\s*#{Regex.escape(name)}\b|\bstatus\s*\(\s*#{Regex.escape(name)}\s*\.\s*status\b/)
  end

  # The conditions of every `if` whose block (or single statement) holds `at`.
  private def enclosing_conditions(code : String, at : Int32) : Array(String)
    enclosing_branches(code, at).map(&.[0])
  end

  # Those `if`s as {condition, branch text}.
  private def enclosing_branches(code : String, at : Int32) : Array(Tuple(String, String))
    branches = [] of Tuple(String, String)
    code[0...at].scan(IF_HEAD) do |m|
      open = m.end(0) - 1
      close = Noir::JSLiteralScanner.find_matching_paren(code, open) || next
      next if close >= at
      between = code[close + 1...at]
      branch = if between.lstrip.starts_with?('{')
                 brace = close + 1 + (between.size - between.lstrip.size)
                 block_end = Noir::JSLiteralScanner.find_matching_brace(code, brace) || code.size
                 block_end > at ? code[brace...Math.min(block_end + 1, code.size)] : nil
               elsif !between.includes?(';') && !between.includes?('}')
                 code[close + 1..].partition(';')[0]
               end
      branches << {code[open + 1...close], branch} if branch
    end
    branches
  end

  # A condition whose every root is module-level in `source` (an import or a
  # top-level `const`) or `process`: configuration, not the request.
  private def module_state?(condition : String, source : String) : Bool
    text = condition.gsub(/(['"`])(?:(?!\1)[^\\]|\\.)*\1/, "")
    # `await Settings.get("x")` waits on a setting; `await currentUser()`
    # on the request's caller, which keeps its `await` root and so is no
    # setting.
    text = text.gsub(/\bawait\s+(?=[\w$.\s]*?(?:[sS]ettings?|[cC]onfig)\w*\s*[.(])/, "")
    roots = text.scan(/(?<![\w$.])([A-Za-z_$][\w$]*)/).map(&.[1]).reject(&.matches?(JS_WORDS)).uniq!
    return false if roots.empty?
    roots.all? do |root|
      # A `let`/`var` is state only when it is a `require`: `let hits = 0`
      # is a counter the app changes, not a setting.
      name = Regex.escape(root)
      root == "process" || source.matches?(/^(?:const\s+(?:#{name}\b|\{[^}]*\b#{name}\b[^}]*\})|(?:let|var)\s+(?:#{name}|\{[^}]*\b#{name}\b[^}]*\})\s*=\s*require\s*\()|^import\b[^\n]*\b#{name}\b/m) ||
        setting_local?(name, source)
    end
  end

  # `const disabledAuth = await Settings.get("disableAuth")`: a local
  # holding a setting read.
  private def setting_local?(name : String, source : String) : Bool
    source.scan(/\b(?:const|let|var)\s+#{name}\s*=\s*(?:await\s+)?([^;\n]+)/) do |m|
      return true if m[1].strip.matches?(SETTING_READ)
    end
    false
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
    while i < lines.size
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
    /\bnext\s*\(\s*[^)\s'"`]/                                                                                                                       => "next(err)",
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
  private def handler_caller_check(endpoint : Endpoint) : GuardEvidence?
    handler = endpoint.handler || return
    path = handler.path || return
    line = handler.line || return
    content = read_file(path) || return
    request = request_param(content, line) || return
    definition = Noir::JSRouteExtractor.definition_body(content, line)
    body = code_only(definition)
    # Path literals stay: `if (req.path === '/health')` is judged against
    # the route.
    judged = Noir::CComments.strip(definition, quotes: %("'`)).gsub(STRING_LITERAL) { |lit| lit.matches?(PATH_LITERAL) ? lit : %("") }
    if check = caller_absence_refusal(judged, Regex.escape(request), stop_file: path)
      return GuardEvidence.new("Protected by Express handler check #{check}", @last_refusal_followed)
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
      return GuardEvidence.new("Protected by Express handler call #{klass}.#{m[2]} (#{check})", @last_refusal_followed && guard_binding_followed?(klass, path) && guard_binding_followed?(m[1], path))
    end
    nil
  rescue
    nil
  end

  # The name the handler defined at `line` gives the request: the first
  # parameter of the last function on that line (`asyncHandler(async (req,
  # res) => {`, `function show(request, response) {`), or of one whose
  # parameter list opens there and wraps (`async (\n  req: Request,`).
  private def request_param(content : String, line : Int32) : String?
    lines = content.lines
    text = lines[line - 1]? || return
    code = code_only(text)
    if code.matches?(/(?:\bfunction\b\s*\*?\s*[\w$]*|[\w$\]]\s*(?::[^=]+)?=\s*(?:async\s*)?)\(\s*\z/)
      return code_only(lines[line]? || "").match(/\A\s*([A-Za-z_$][\w$]*)\s*[:,)]/).try(&.[1])
    end
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
    source = stop_file.try { |file| read_file(file) }
    # Whether an earlier branch of the current `if`/`else if` chain can let
    # a caller through: `if (x) { … } else if (!req.user) …` is never met by
    # a caller taking the first branch, unless that branch refuses too.
    chain_passes = false
    body.scan(TOP_LEVEL_IF) do |m|
      at = m.begin(0)
      return if earlier_exit?(body, at, stop_file)
      next unless top_level?(body, at)
      in_chain = body[0...at].rstrip.ends_with?("else")
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
      prior_passes = in_chain && chain_passes
      chain_passes = prior_passes || (route_branch_taken?(condition) != false && top_refusal(branch, source, stop_file).nil?)
      next if prior_passes
      tested = Noir::TopLevelSplit.split(condition, '|', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).reject(&.blank?).find do |part|
        next false unless hit = part.strip.match(absent)
        caller_fields?(hit[1]? || hit[2], receiver)
      end
      if tested
        refusal = branch_refusal(branch, source, stop_file) || next
        @last_refusal_followed &&= !tested.includes?('(') && guard_prefix_read?(body[0...at])
        return "#{tested.gsub(/\s+/, "")} #{refusal}"
      end
      # `if (req.isAuthenticated()) { … } else { return errorForbidden(req, res) }`:
      # the caller's presence opens the route, and the `else` an anonymous
      # caller takes refuses it.
      next unless block_end
      hit = condition.strip.match(/\A(?:#{receiver})((?:\s*\??\.\s*[A-Za-z_$][\w$]*)+)\s*(?:\(\s*\))?\z/) || next
      next unless caller_fields?(hit[1], receiver)
      refusal = else_refusal(body[block_end + 1..], source, stop_file) || next
      @last_refusal_followed &&= !condition.includes?('(') && guard_prefix_read?(body[0...at])
      return "#{condition.strip.gsub(/\s+/, "")} else #{refusal}"
    end
    nil
  end

  PATH_LITERAL = /\A(['"])\/[^'"]*\1\z/
  PATH_FIELD   = /(?<![\w$.])(?:req|request)\s*\.\s*(?:path|url|originalUrl|baseUrl|route\s*\.\s*path)\b/
  PATH_EQUALS  = /\A\(*\s*(?:req|request)\s*\.\s*(?:path|url|originalUrl|baseUrl)\s*===?\s*(['"])(\/[^'"]*)\1\s*\)*\z/

  # Whether a caller can take the branch of an `if` on `condition`, when
  # the request path alone decides it (`req.path === '/health'`): the
  # caller cannot choose the path of the route it calls. True only for an
  # equality with the endpoint's own literal URL; false for any other path
  # test (a parameterized route, a mount-relative path, `startsWith`);
  # nil when the condition reads anything else.
  private def route_branch_taken?(condition : String) : Bool?
    return unless condition.matches?(PATH_FIELD)
    rest = condition.gsub(PATH_FIELD, "").gsub(STRING_LITERAL, "")
    return if rest.scan(/(?<![\w$.])[A-Za-z_$][\w$]*/).any? { |m| !m[0].matches?(JS_WORDS) }
    test = condition.strip.match(PATH_EQUALS) || return false
    url = @url || return false
    !url.matches?(/[:*{(]/) && test[2] == url
  end

  # Whether code before `at` can answer or pass the request on, leaving
  # out a top-level `if` whose branch only refuses bad input (`if
  # (req.body.length > max) { return errorTooLong(req, res) }`, the helper
  # answering 4xx): that branch lets no caller through.
  private def earlier_exit?(body : String, at : Int32, stop_file : String?) : Bool
    # `const note = await Note.findOne({ id: req.params.id })`: a lookup
    # handed neither the response nor `next` cannot answer the request.
    prefix = body[0...at].gsub(QUIET_AWAIT) { |call| call.matches?(/(?<![\w$.])(?:res|response|next)(?![\w$])/) ? call : " " * call.size }
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

  QUIET_AWAIT        = /\bawait\s+[A-Za-z_$][\w$]*(?:\s*\.\s*[A-Za-z_$][\w$]*)*\s*\((?:[^()]|\([^()]*\))*\)/
  INPUT_REFUSAL_CALL = /\A\{\s*return\s+([A-Za-z_$][\w$]*(?:\s*\.\s*[A-Za-z_$][\w$]*)*)\s*\([^;{}]*\)\s*;?\s*\}\z/
  # A 4xx answer as a definition writes it: `res.status(413)`,
  # `res.sendStatus(400)`, or a reply helper handed the response and the
  # code (`responseError(res, '413', …)`).
  STATUS_4XX = /\b(?:res|response)\s*\.\s*(?:status|sendStatus)\s*\(\s*['"]?4\d\d\b|\b[A-Za-z_$][\w$.]*\s*\(\s*(?:res|response)\s*,\s*['"]?4\d\d['"]?\s*[,)]/
  # A response that is not a refusal: anything sent without a 4xx status
  # chained before it.
  STATUS_4XX_CHAIN = /\b(?:res|response)\s*\.\s*status\s*\(\s*['"]?4\d\d['"]?\s*\)\s*\.\s*[A-Za-z]+\s*\(/
  SUCCESS_RESPONSE = /\b(?:res|response)\s*\.\s*(?:json|jsonp|send|render|sendFile|download|end|write)\s*\(|\.pipe\s*\(\s*(?:res|response)\s*\)/

  # Whether `code` answers anything but a refusal.
  private def success_response?(code : String) : Bool
    code.gsub(STATUS_4XX_CHAIN, "").matches?(SUCCESS_RESPONSE)
  end

  # A block that is only `return f(…)` through a function whose every
  # answer is a 4xx (`res.status(413).send(…)`, `responseError(res, '413',
  # …)`): whoever takes it, on whatever input, is refused.
  private def input_refusal?(block : String, file : String) : Bool
    call = block.match(INPUT_REFUSAL_CALL) || return false
    content = read_file(file) || return false
    target = Noir::JSHandlerResolver.resolve(call[1].gsub(/\s+/, ""), content, file) || return false
    path, line = target.path, target.line
    return false if path.nil? || line.nil?
    text = read_file(path) || return false
    definition = Noir::CComments.strip(Noir::JSRouteExtractor.definition_body(text, line), quotes: %("'`))
    definition.matches?(STATUS_4XX) && !success_response?(definition) && !definition.matches?(/\bnext\b/)
  end

  # The last field names the caller and the first is not request data
  # (`!req.params.userId` refuses a bad URL, not an anonymous caller).
  private def caller_fields?(chain : String, receiver : String) : Bool
    fields = chain.split('.').map(&.strip.lchop('?').strip).reject(&.empty?)
    fields.last.matches?(CALLER_FIELD) && (receiver == "this" || !fields.first.matches?(DATA_ROOTS))
  end

  private def guard_prefix_read?(prefix : String) : Bool
    !prefix.matches?(PATH_FIELD) && !prefix.matches?(/(?<![\w$])(?!(?:if|typeof)\b)[A-Za-z_$][\w$]*\s*\(|\+\+|--|(?<![=!<>])=(?![=>])/)
  end

  private def first_refusal?(code : String, at : Int32) : Bool
    prefix = code[0...at].lstrip
    prefix = prefix[1..] if prefix.starts_with?('{')
    top_level?(prefix, prefix.size) && !prefix.sub(/\breturn\s*\z/, "").matches?(EARLIER_EXIT) &&
      guard_prefix_read?(prefix) && enclosing_conditions(code, at).all?(&.strip.matches?(METHOD_TEST))
  end

  # An unread value can be falsy: Express's next(err) then passes on.
  private def literal_refusal?(code : String, kind : String) : Bool
    return code.matches?(/\Athrow\s+new\b/) if kind == "throws"
    return code.matches?(/\Anext\s*\(\s*(?:new\b|\{)/) if kind == "next(err)"
    true
  end

  # How `branch` stops the caller that takes it, or nil.
  private def branch_refusal(branch : String, source : String?, stop_file : String?) : String?
    @last_refusal_followed = false
    BRANCH_REFUSALS.each do |re, label|
      hit = branch.match(re) || next
      # `if (!req.user) { if (req.method !== 'GET') return res.sendStatus(401) }`
      reach = refusal_reach(branch, hit.begin(0), source) || next
      @last_refusal_followed = reach == :always && first_refusal?(branch, hit.begin(0)) && literal_refusal?(branch[hit.begin(0)..], label)
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
      found = top_refusal(inner[0..inner_close], source, stop_file) || return
      @last_refusal_followed = false
      return found.ends_with?(SETTING_NOTE) ? found : "#{found}#{SETTING_NOTE}"
    end
    return unless branch.starts_with?('{')
    close = Noir::JSLiteralScanner.find_matching_brace(branch, 0) || return
    top_refusal(branch[0..close], source, stop_file)
  end

  # The refusal a block makes on its own top level, for every caller that
  # enters it: not one under a nested `if` or inside a callback (`if (err)
  # return next(err)`), and nil when the block also answers the request
  # (`res.json(publicFeed)`).
  private def top_refusal(block : String, source : String?, stop_file : String?) : String?
    @last_refusal_followed = false
    inner = block.strip
    inner = inner[1...-1] if inner.starts_with?('{') && inner.ends_with?('}')
    return if success_response?(inner)
    BRANCH_REFUSALS.each do |re, label|
      inner.scan(re) do |hit|
        at = hit.begin(0)
        if first_refusal?(inner, at) && enclosing_conditions(inner, at).empty?
          @last_refusal_followed = literal_refusal?(inner[at..], label)
          return label
        end
      end
    end
    file = stop_file || return
    inner.scan(STOP_CALL) do |hit|
      at = hit.begin(0)
      next unless top_level?(inner, at) && enclosing_conditions(inner, at).empty?
      return stop_refusal(inner[at..], file)
    end
    nil
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

  BARE_IDENT           = /\A[A-Za-z_$][\w$]*\z/
  CREDENTIALS_OPTIONAL = /credentialsRequired\s*:\s*false\b/
  JWT_FACTORY          = /\Aexpress[jJ]wt\z/

  private def credentials_optional?(text : String) : Bool
    text.matches?(CREDENTIALS_OPTIONAL)
  end

  # `{description, true}` when `arg` is an express-jwt alias (`import {
  # expressjwt as jwt }`) or `auth.required` where `required: jwt({...})`.
  # Optional mode (`credentialsRequired: false`) is handled and not a guard.
  # `{nil, false}` leaves the literal `expressjwt(` path alone so its
  # evidence stays `(expressjwt)`.
  private def judge_jwt_alias(arg : String, file : String) : {String?, Bool}
    content = read_file(file) || return {nil, false}
    code = code_only(arg).strip
    if call = code.match(/\A([A-Za-z_$][\w$]*)\s*\(/)
      return {nil, false} if call[1].matches?(JWT_FACTORY)
      return {nil, false} unless jwt_alias?(content, call[1])
      return {nil, true} if credentials_optional?(code)
      return {"Protected by Express #{call[1]} (express-jwt) middleware", true}
    end
    ref = code.match(Noir::JSHandlerResolver::REFERENCE_RE) || return {nil, false}
    if ref[2].blank?
      expr = local_binding_expr(content, ref[1]) || return {nil, false}
      return jwt_expr_guard(expr, content, ref[1])
    end
    members = ref[2].split('.').map(&.strip).reject(&.empty?)
    return {nil, false} unless members.size == 1
    handler = Noir::JSHandlerResolver.resolve(ref[1], content, file) || return {nil, false}
    def_path = handler.path || return {nil, false}
    source = read_file(def_path) || return {nil, false}
    object = object_literal_at(source, handler.line) || return {nil, false}
    expr = Noir::JSObjectLiteral.property(object, members[0]) || return {nil, false}
    jwt_expr_guard(expr, source, "#{ref[1]}.#{members[0]}")
  end

  private def jwt_expr_guard(expr : String, content : String, display : String) : {String?, Bool}
    call = expr.strip.match(/\A([A-Za-z_$][\w$]*)\s*\(/) || return {nil, false}
    # A literal `expressjwt(` keeps the existing `(expressjwt)` evidence.
    return {nil, false} if call[1].matches?(JWT_FACTORY)
    return {nil, false} unless jwt_alias?(content, call[1])
    return {nil, true} if credentials_optional?(expr)
    {"Protected by Express #{display} (express-jwt) middleware", true}
  end

  private def jwt_alias?(content : String, name : String) : Bool
    jwt_aliases(content).includes?(name)
  end

  private def jwt_aliases(content : String) : Set(String)
    names = Set(String).new
    content.scan(/import\s*(?:type\s*)?\{([^}]*)\}\s*from\s*['"]express-jwt['"]/m) do |m|
      push_jwt_locals(names, m[1])
    end
    content.scan(/(?:const|let|var)\s*\{([^}]*)\}\s*=\s*require\s*\(\s*['"]express-jwt['"]\s*\)/m) do |m|
      push_jwt_locals(names, m[1])
    end
    content.scan(/\bimport\s+([A-Za-z_$][\w$]*)\s+from\s*['"]express-jwt['"]/) do |m|
      names << m[1]
    end
    content.scan(/\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*require\s*\(\s*['"]express-jwt['"]\s*\)/) do |m|
      names << m[1]
    end
    names
  end

  private def push_jwt_locals(names : Set(String), list : String)
    list.split(',').each do |entry|
      parts = entry.split(/\s+as\s+|\s*:\s*/, 2).map(&.strip)
      exported = parts[0]
      local = parts[1]? || exported
      names << local if exported.matches?(JWT_FACTORY) && !local.empty?
    end
  end

  private def local_binding_expr(content : String, name : String) : String?
    decl = content.match(/\b(?:const|let|var)\s+#{Regex.escape(name)}\s*=\s*/) || return
    start = decl.end(0)
    call = content.match(/\G[A-Za-z_$][\w$]*\s*\(/, start) || return
    close = Noir::JSLiteralScanner.find_matching_paren(content, call.end(0) - 1) || return
    content[start..close]
  end

  private def object_literal_at(content : String, line : Int32?) : String?
    return if line.nil? || line < 1
    idx = 0
    (line - 1).times do
      nl = content.index('\n', idx) || return
      idx = nl + 1
    end
    abs = content.index(/[;{]/, idx) || return
    return unless content[abs] == '{'
    close = Noir::JSLiteralScanner.find_matching_brace(content, abs) || return
    content[abs..close]
  end
end
