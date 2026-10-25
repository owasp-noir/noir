require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "./group_scope"
require "../../../miniparsers/go_callee_extractor"
require "../../../utils/top_level_split"

@[Noir::TaggerFor(key: "go_auth", name: "Go Auth Tagger", desc: "Identifies Go authentication patterns (middleware, JWT, session)", order: 50)]
class GoAuthTagger < FrameworkTagger
  include GoRouteGroupScope

  # JWT library patterns
  JWT_PATTERNS = [
    /echojwt\.\w+/,
    /jwtauth\.\w+/,
    /jwt\.New\s*\(/,
    /jwt\.Auth\s*\(/,
    /middleware\.JWT\s*\(/,
    /middleware\.JWTWithConfig\s*\(/,
  ]

  # Auth middleware in route definition (inline middleware)
  INLINE_AUTH_MIDDLEWARE = [
    /\b[Aa]uth(?:enticate|orize|Required|Middleware|Handler|Guard|Check)\b/,
    /\b[Rr]equire[Aa]uth\b/,
    /\b[Ii]s[Aa]uth(?:enticated)?\b/,
    /\b[Ll]ogin[Rr]equired\b/,
    /\b[Vv]erify[Tt]oken\b/,
    /\b[Cc]heck[Tt]oken\b/,
    /\b[Jj][Ww][Tt](?:Auth|Middleware|Verify|Check|Guard)?\b/,
    /\b[Aa]dmin[Oo]nly\b/,
    /\b[Rr]ole[Cc]heck\b/,
    /\b[Pp]ermission[Cc]heck\b/,
    # Hertz / Iris / GF specific
    /\bHertzAuth\b/,
    /\bIrisAuth\b/,
    /\bGF[Aa]uth\b/,
  ]

  # The route call's last argument when it is a bare handler reference
  # (`r.POST("/login", AuthHandler)`), plus any chained calls after it
  # (mux's `.Methods("GET")`). Only the arguments between path and handler
  # are middleware; a wrapped handler (`authMiddleware(h)`) is a call, so it
  # stays.
  HANDLER_ARG = /,\s*[\w.]+\s*\)((?:\s*\.\s*\w+\s*\([^()]*\))*)\s*;?\s*$/

  # A scope is only ever recorded for a line `resolve_use_scope` or
  # `resolve_group_middleware_scope` resolves: a `.Use(` / `.Pre(` call or a
  # `Group("/seg", mw...)` constructor — so a file with neither anywhere
  # registers nothing, and the pre-scan can skip its per-line group tracking
  # outright.
  USE_REGISTRATION = /\.\s*(?:Use|Pre)\s*\(|\.\s*(?:Group|Party)\s*\(\s*"[^"]*"\s*,/

  # Where the middleware arguments start on a `code_only` line (string
  # literals blanked to `""`): right after `.Use(` / `.Pre(`, or after the
  # path literal of a `Group("/seg", ...)` constructor or a route call.
  MIDDLEWARE_ARGS_START = /\.\s*(?:Use|Pre)\s*\(|\.\s*\w+\s*\(\s*""\s*,/

  # One middleware argument's head: `AuthMiddleWare()` -> {"", "AuthMiddleWare"},
  # `auth.Required()` -> {"auth", "Required"}, `gin.BasicAuth(gin.Accounts{` ->
  # {"gin", "BasicAuth"}. A closure (`func(c *gin.Context) {`) is excluded.
  MIDDLEWARE_REFERENCE = /\A((?:\w+\s*\.\s*)*)(?!func\b)(\w+)\s*(?:\(|\z)/

  # A name that reads as a guard, applied to a middleware argument
  # (`gin.BasicAuth`, `echojwt.WithConfig`) only when its definition is not in
  # the scan: a library constructor or an interface method. A definition that
  # is found decides on its body, so `LoginLogger()` / `TokenRefresher()` that
  # only pass the request on are not guards whatever they are called.
  # `sessions.Sessions(store)` is a session *store*, not a check.
  AUTHISH_NAME = /auth|jwt|token|permission|login|rbac|acl/i

  # A middleware body line that refuses the request: a 401/403 status handed
  # to a reply or abort call (`AbortWithStatus(http.StatusUnauthorized)`,
  # `c.JSON(403, ...)`, `http.Error(w, "", 401)`, `WriteHeader(403)`) or a
  # framework sentinel error (`echo.ErrUnauthorized`, `fiber.ErrForbidden`).
  # Matched on `code_only` source, so a 401 in a comment or log string does
  # not count, and `== http.StatusUnauthorized` (a comparison, as in a
  # logging middleware) does not either.
  REJECTS_REQUEST = /[(,]\s*(?:\w+\.)?Status(?:Unauthorized|Forbidden)\b|[(,]\s*40[13]\s*[,)]|\b(?:\w+\.)?Err(?:Unauthorized|Forbidden)\b/

  # A redirect to the login page (`ctx.RedirectForLogin(...)`,
  # `c.Redirect(302, "/login")`), matched with string literals kept.
  LOGIN_REDIRECT = /(?=.*\bRedirect\w*\s*\().*(?:[Ll]og_?[Ii]n|[Ss]ign_?[Ii]n)/

  # A refusal whose condition asks what the caller may do
  # (`!ctx.IsUserSiteAdmin()`, `!ctx.Repo.Permission.CanRead(...)`,
  # `!isMember`) is an authorization check; any other is an authentication
  # one.
  AUTHZ_CONDITION = /[Aa]dmin|[Rr]ole|[Pp]erm|[Oo]wner|[Mm]ember|[Cc]ollaborat|[Ss]cope|[Aa]ccess|[Pp]rivilege|[Vv]isib|[Pp]ublic|[Gg]rant|[Ww]riter|[Rr]eader|\b[Cc]an[A-Z]/

  # `if cond {` / `} else if x := f(); cond {` and `} else {` on their own line.
  IF_OPEN   = /\A(?:\}\s*)?(?:else\s+)?if\s+(?:[^;{]*;\s*)?(.+?)\s*\{\z/
  ELSE_OPEN = /\A\}?\s*else\s*\{\z/

  # An `if` block that only lets the request through: `return`, optionally
  # after handing it on (`c.Next()`, `next.ServeHTTP(w, r)`).
  PASS_STATEMENT = /\A(?:[\w.]+\.Next\(\)|next\.ServeHTTP\(.*\))\z/

  # A condition that a request-supplied value is absent (`!ok`, `token ==
  # ""`, `len(sudo) == 0`) or present (`token != ""`, `len(sudo) > 0`).
  ABSENCE_TEST  = /\A(?:!\s*(\w+)|(\w+)\s*==\s*""|len\(\s*(\w+)\s*\)\s*==\s*0)\z/
  PRESENCE_TEST = /\A(?:(\w+)\s*!=\s*""|len\(\s*(\w+)\s*\)\s*(?:>|!=)\s*0)\z/
  PRESENT       = "<present>"

  # `options.SignInRequired` / `!options.SignOutRequired` read off a parameter.
  OPTION_FIELD = /\A(!?)\s*(\w+)\.(\w+)\z/

  # `pkg.Var.Field` with no call: a package-level (configuration) value.
  PACKAGE_VALUE = /\A!?\s*(\w+)(?:\.\w+)+\z/

  # `Field: value` inside a call-site struct literal.
  LITERAL_FIELD = /(\w+)\s*:\s*([^,{}]+)/

  # The parameter list of a `func name(...)` / `func (r T) name(...)` head.
  FUNC_PARAMS = /\Afunc\s*(?:\([^)]*\)\s*)?\w+\s*\(([^)]*)\)/

  # `name := expr` / `name = expr`, for a middleware held in a variable
  # (`reqSignIn := verifyAuth(&Options{SignInRequired: true})`).
  LOCAL_BINDING = /\A\s*([\w.]+)\s*:?=\s*([\w.]+\s*\(.*)\z/

  # A closure handed to a call that is still open at the end of the line:
  # `m.Group("/user", func() {`, `r.Group(func(r chi.Router) {`.
  CLOSURE_ARG_OPEN = /\(.*\bfunc\s*\([^()]*\)\s*\{\s*\z/

  # Middleware handed to `r.With(mw...)` ahead of a route or group.
  WITH_CALL = /\.\s*With\s*\(/

  # A route call on a line: `m.Post(`, `.GET(`, or a chained `Delete(`.
  ROUTE_CALL = /(?:\A|\.)\s*([A-Za-z]+)\s*\(/

  MULTI_VERB_CALLS = %w[Any Match]

  # Lines worth walking for closure-scoped middleware.
  CLOSURE_REGISTRATION = /\.\s*(?:Use|With|Group|Route)\s*\(/

  # How sure a middleware definition makes us that it guards a route.
  enum Guard
    None
    Authz
    Authn
  end

  # An unqualified call inside a middleware body, for the one-hop lookup.
  BODY_CALL = /(?<![\w.])([A-Za-z_]\w*)\s*\(/

  # The group variable a registration line credits: `authV1` for both
  # `authV1.Use(auth)` and `authV1 := apiV1.Group("/", auth)`.
  REGISTRATION_RECEIVER = /\A(\w+)\s*(?::?=\s*\w+\s*\.\s*(?:Group|Party)|\.\s*(?:Use|Pre))\s*\(/

  # The variable a route line registers on: `authV1` for `authV1.POST(...)`.
  ROUTE_RECEIVER = /\A\s*(\w+)\s*\.\s*\w+\s*\(/

  # The routes a group's middleware reaches: those registered on `receiver`
  # (or a group derived from it, through `parents`) on `rows` of `file`.
  alias Gate = {file: String, receiver: String, rows: Range(Int32, Int32), parents: Hash(String, String)}

  # A statement that opens with an assignment (`authed := r.Group(...)`).
  ASSIGNMENT_HEAD = /\A\s*\w+(?:\s*,\s*\w+)*\s*:?=/

  # A local typed with a struct, so its methods resolve: `authentication :=
  # auth.Auth{`, `var mw = &middleware.JWT{`, `mw *auth.Middleware`.
  LOCAL_TYPE = /\b(\w+)\s*(?::?=\s*&?\s*|\s+\*?)(?:(\w+)\.)?([A-Z]\w*)\s*[{\n),]/

  # `func (a *Auth) Name(`: the receiver's name and type.
  METHOD_RECEIVER_NAME = /\Afunc\s*\(\s*(\w+)\s+\*?\s*(\w+)\s*\)/

  # A statement that calls a method on a value: `a.evaluateOr401(ctx, ...)`.
  RECEIVER_STATEMENT = /\A(\w+)\s*\.\s*(\w+)\s*\(/

  def initialize(options : Hash(String, YAML::Any))
    super
    @middleware_scopes = [] of {prefix: String, tag: Tag, root_group: Bool, gate: Gate?}
    @closure_scopes = [] of {file: String, from: Int32, to: Int32, tag: Tag}
    @current_gate = nil.as(Gate?)
    @bodies = Noir::GoCalleeExtractor::LazyPackageBodies.empty
    @dirs_by_base = Hash(String, Array(String)).new
    @guards = Hash({String, String, Bool, String?}, Tag?).new
    @helper_verdicts = Hash({String, Int32, Bool, Int32}, Guard).new
    @imports = Hash(String, Set(String)).new
    @bindings = Hash(String, Hash(String, String)).new
  end

  def self.target_techs : Array(String)
    [
      "go_echo", "go_gin", "go_chi", "go_fiber",
      "go_beego", "go_mux", "go_fasthttp",
      "go_gozero", "go_goyave",
      "go_hertz", "go_iris", "go_gf",
    ]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Phase 1: Pre-scan for group-level middleware
    pre_scan_middleware_scopes
    super
  end

  private def pre_scan_middleware_scopes
    @middleware_scopes.clear
    @closure_scopes.clear

    files = collect_files_by_extension(".go")
    contents = Hash(String, String).new
    files.each do |file|
      content = read_file(file)
      next if content.nil?
      # Test files are left out of the definition index: an external
      # `foo_test` package in the same directory may reuse a name.
      contents[file] = content unless file.ends_with?("_test.go")
    end

    # Middleware definitions, parsed per package only when a registration
    # names a function the name patterns do not recognise.
    @bodies = Noir::GoCalleeExtractor::LazyPackageBodies.new(contents)
    @dirs_by_base = contents.keys.map { |path| File.dirname(path) }.uniq!.group_by { |dir| File.basename(dir) }

    files.each do |file|
      content = read_file(file)
      scan_group_middleware(content, file) if content
    end
  end

  private def scan_group_middleware(content : String, file : String)
    uses = USE_REGISTRATION.matches?(content, options: Noir::TextFile::MATCH_OPTIONS)
    closures = CLOSURE_REGISTRATION.matches?(content, options: Noir::TextFile::MATCH_OPTIONS)
    return unless uses || closures

    # Closures handed to a call (`m.Group("/user", func() {`, chi's
    # `r.Group(func(r chi.Router) {`), with the middleware a `.With(...)` on
    # the opening line or a `.Use(...)` inside puts in front of their routes.
    lines = content.lines
    frames = [] of {line: Int32, depth: Int32, args: Array(String), uses: Array({Int32, Array(String)})}
    depth = 0
    index = 0
    each_group_scoped_line(content) do |stripped, scopes|
      index += 1
      in_closure = false
      if closures
        code = code_only(stripped).rstrip
        # A `.Use` on the closure's own router guards the routes after it
        # in that closure, not every route under the group's prefix.
        receiver = stripped.match(GoRouteGroupScope::USE_CALL).try &.[1]
        if (frame = frames.last?) && receiver && !scopes.groups.has_key?(receiver)
          frame[:uses] << {index, middleware_args(stripped)}
          in_closure = true
        end
        code.each_char_with_index do |char, pos|
          if char == '{'
            if pos == code.size - 1 && code.matches?(CLOSURE_ARG_OPEN)
              args = (with_call = code.match(WITH_CALL)) ? call_args(code[with_call.end..]) : [] of String
              frames << {line: index, depth: depth, args: args, uses: [] of {Int32, Array(String)}}
            end
            depth += 1
          elsif char == '}'
            depth -= 1
            next unless (top = frames.last?) && top[:depth] == depth
            frames.pop
            # `}, reqToken(), reqAdmin())`: middleware after the closure.
            (top[:args] + trailing_args(code[pos + 1..], lines, index)).each do |arg|
              add_closure_scope(file, top[:line], index, arg)
            end
            top[:uses].each do |(line, args)|
              args.each { |arg| add_closure_scope(file, line, index, arg) }
            end
          end
        end
      end
      register_auth_scopes(stripped, scopes, file, lines, index) if uses && !in_closure
    end
  end

  private def add_closure_scope(file : String, from : Int32, to : Int32, arg : String)
    tag = guard_by_definition(arg, file, authish_name: true)
    @closure_scopes << {file: file, from: from, to: to, tag: tag} if tag
  end

  # The arguments after a closure's closing brace (`, reqToken())`), read on
  # into the following lines when the call continues there (`},` then
  # `reqSignIn, ctx.RepoAssignment,` then `)`).
  private def trailing_args(rest : String, lines : Array(String), index : Int32) : Array(String)
    text = rest
    extra = index
    while text.count('(') >= text.count(')') && !text.rstrip.ends_with?('{') && extra < lines.size && extra < index + 5
      text += " " + code_only(lines[extra])
      extra += 1
    end
    call_args(text.lstrip.lchop(','))
  end

  private def register_auth_scopes(stripped : String, scopes : GoRouteGroupScope::Scopes, file : String, lines : Array(String), index : Int32)
    scope = resolve_use_scope(stripped, scopes) || resolve_group_middleware_scope(stripped, scopes)
    return if scope.nil?
    # The middleware guards a route group whose URL prefix we could not read
    # (`r.Group(cfg.APIBase + "/v1")`). Recording it as global would claim
    # every endpoint in the app is protected — including the ones registered on
    # the app's explicitly public groups. Decline instead.
    return if scope[:kind] == GoRouteGroupScope::ScopeKind::Unknown

    # A group that adds no path segment (`authV1 := apiV1.Group("/", auth)`)
    # shares its parent's prefix, so the prefix alone would also claim the
    # parent's own `apiV1.GET("users")`. Its middleware is credited only to
    # routes registered on that variable in this file, inside the block that
    # declares it: a sibling block's `g := e.Group("")` is another variable.
    # ponytail: routes such a group hands to a helper in another file
    # (`registerAuth(authV1)`) resolve by name only.
    receiver = stripped.match(REGISTRATION_RECEIVER).try &.[1]
    @current_gate = receiver && scopes.aliases.includes?(receiver) ? {file: file, receiver: receiver, rows: index..enclosing_block_end(lines, index), parents: scopes.parents} : nil
    # `r.Group("/").Use(auth).POST("/x", h)` with the group kept nowhere:
    # the middleware reaches only the routes chained in that statement.
    # (Handed to a helper instead, `register(r.Group("/").Use(auth))`, it
    # still reaches every route under the prefix.)
    if chain = ephemeral_group_use(stripped)
      @current_gate = {file: file, receiver: chain, rows: index..statement_end(lines, index), parents: {} of String => String}
    end

    before = @middleware_scopes.size

    # Check for JWT library middleware
    JWT_PATTERNS.each do |pattern|
      if stripped.matches?(pattern) && stripped.includes?(".Use")
        jwt_match = stripped.match(pattern)
        jwt_name = jwt_match ? jwt_match[0] : "JWT"
        add_middleware_scope(scope, Tag.new("auth", "Protected by Go JWT middleware (#{jwt_name})", "go_auth"))
      end
    end
    return unless before == @middleware_scopes.size

    # Read each middleware argument's definition; its name counts only when
    # the definition is not in the scan.
    middleware_args(stripped).each do |arg|
      tag = guard_by_definition(arg, file, authish_name: true)
      add_middleware_scope(scope, tag) if tag
    end
  end

  # The head variable of a statement that builds a group, adds middleware
  # and registers a route on it in one chain, keeping the group nowhere
  # (`g.Group("/").Use(auth).POST("/message", h)`); nil for any other line.
  private def ephemeral_group_use(stripped : String) : String?
    chain = stripped.match(GoRouteGroupScope::CHAINED_GROUP_USE) || return
    return unless chain.begin.zero?
    code = code_only(stripped)
    use = code.match(/\.\s*(?:Use|Pre)\s*\(/) || return
    depth = 0
    (use.end...code.size).each do |pos|
      case code[pos]
      when '(' then depth += 1
      when ')'
        if depth.zero?
          return code[pos + 1..].matches?(/\A\s*\.\s*[A-Za-z]+\s*\(/) ? chain[1] : nil
        end
        depth -= 1
      end
    end
  end

  # The 1-based last line of the statement starting on line `index`
  # (1-based): where its parentheses balance.
  private def statement_end(lines : Array(String), index : Int32) : Int32
    depth = 0
    (index - 1).upto(lines.size - 1) do |row|
      code = code_only(lines[row])
      depth += code.count('(') - code.count(')')
      return row + 1 if depth <= 0
    end
    lines.size
  end

  # The middleware arguments of a registration line: everything after
  # `.Use(` or after the path literal.
  private def middleware_args(line : String) : Array(String)
    code = code_only(line)
    start = code.match(MIDDLEWARE_ARGS_START)
    return [] of String unless start
    call_args(code[start.end..])
  end

  # The arguments of a call whose opening paren is already consumed, split
  # at the top level and cut at the paren that closes the call, so a chained
  # `.GET(...)` after `.Use(a, b)` is not read as more middleware.
  private def call_args(inner : String) : Array(String)
    depth = 0
    inner.each_char_with_index do |ch, idx|
      depth += 1 if ch == '('
      next unless ch == ')'
      if depth.zero?
        inner = inner[0, idx]
        break
      end
      depth -= 1
    end
    Noir::TopLevelSplit.split(inner, ',', Noir::TopLevelSplit::Rules.new)
  end

  # The middleware of the route call at `lines[idx]`: the arguments between
  # the path and the handler of the call named for `method` (`m.Post("/merge",
  # reqToken(), bind(...), h)`, a combo's `Delete(reqToken(), h)`), read
  # across continuation lines, plus a `.With(mw...)` or a chain head in
  # front of it.
  private def route_middleware_args(lines : Array(String), idx : Int32, method : String) : Array(String)
    code = code_only(lines[idx])
    extra = idx + 1
    while code.count('(') > code.count(')') && !code.rstrip.ends_with?('{') && extra < lines.size && extra <= idx + 5
      code += " " + code_only(lines[extra])
      extra += 1
    end
    args = (with_call = code.match(WITH_CALL)) ? call_args(code[with_call.end..]) : [] of String
    # A registrar for several verbs (`r.Any("/x", h)`, `r.Match([]string{
    # "GET", "HEAD"}, "/x", mw, h)`) takes its path, then its handlers.
    if call = code.scan(ROUTE_CALL).find { |match| match[1].upcase == method || MULTI_VERB_CALLS.includes?(match[1]) }
      route_args = call_args(code[call.end..])
      route_args = route_args[(route_args.index(&.starts_with?('"')) || 0)..].skip_while(&.starts_with?('"'))
      args.concat(route_args[0...-1])
      # The head of a chain the verb hangs off (`m.Combo("/x", reqToken()).
      # Get(h)`, on this line or the ones ending in `.` above) runs in front
      # of every verb in it.
      head = idx
      while head > 0 && head > idx - 5 && code_only(lines[head - 1]).rstrip.ends_with?('.')
        head -= 1
      end
      args.concat(middleware_args(head == idx ? code[0, call.begin] : lines[head]))
    else
      args.concat(middleware_args(lines[idx])[0...-1])
    end
    args
  end

  # The tag middleware argument `arg` earns: `auth` when its definition
  # refuses anonymous callers, `authz` when it only refuses callers lacking a
  # permission, and (with `authish_name`) `auth` when the definition is not
  # in the scan and its name says so; nil when it is a closure or only passes
  # the request on. A variable or field (`reqSignIn`, `webAuth.AllowBasic`)
  # is read through its binding in `file` (`reqSignIn :=
  # verifyAuth(&Options{SignInRequired: true})`).
  private def guard_by_definition(arg : String, file : String, authish_name : Bool = false, display : String? = nil) : Tag?
    @guards.put_if_absent({arg, file, authish_name, display}) do
      ref = arg.match(MIDDLEWARE_REFERENCE)
      next unless ref
      qualifier = ref[1].gsub(/\s+/, "").rchop('.')
      name = ref[2]
      reference = qualifier.empty? ? name : "#{qualifier}.#{name}"
      shown = display || reference
      fields = arg.includes?('{') ? arg.scan(LITERAL_FIELD).to_h { |field| {field[1], field[2].strip} } : nil
      case definition_verdict(qualifier, name, file, fields)
      when Guard::Authn
        Tag.new("auth", "Protected by Go middleware #{shown} (verified from its body: refuses anonymous callers)", "go_auth")
      when Guard::Authz
        Tag.new("authz", "Protected by Go middleware #{shown} (verified from its body: permission check replies 403)", "go_auth")
      when nil
        if display.nil? && (bound = local_binding(file, shown))
          next guard_by_definition(bound, file, authish_name, shown)
        end
        Tag.new("auth", "Protected by Go middleware #{shown}", "go_auth") if authish_name && reference.matches?(AUTHISH_NAME)
      end
    end
  end

  # The expression first bound to `name` in `file`.
  # ponytail: file-wide, not per function; a name rebound in another
  # function of the same file reads the first binding.
  private def local_binding(file : String, name : String) : String?
    bindings = @bindings.put_if_absent(file) do
      map = Hash(String, String).new
      read_file_lines(file).try &.each do |line|
        next unless line.includes?('=')
        if match = code_only(line).match(LOCAL_BINDING)
          map.put_if_absent(match[1]) { match[2].strip }
        end
      end
      map
    end
    bindings[name]?
  end

  # The strongest verdict over the definitions of `qualifier.name`, resolved
  # from the package of `file`; nil when no definition is found. A method
  # value on a local typed with another package's struct (`authentication :=
  # auth.Auth{...}` then `authentication.RequireClient`) resolves to that
  # type's method.
  # ponytail: same package plus a sibling package directory named like the
  # qualifier (or the local's type package), one hop deep; a guard reached
  # through an interface or a third party module still resolves by name only.
  private def definition_verdict(qualifier : String, name : String, file : String, fields : Hash(String, String)?) : Guard?
    dir = File.dirname(file)
    bodies = [] of Noir::GoCalleeExtractor::FunctionBody
    if qualifier.empty?
      @bodies.functions_for(dir)[name]?.try { |body| bodies << body }
    else
      @bodies.methods_for(dir)[name]?.try { |list| bodies.concat(list) }
      @dirs_by_base[qualifier]?.try &.each do |pkg|
        @bodies.functions_for(pkg)[name]?.try { |body| bodies << body }
      end
      bodies.concat(local_type_methods(qualifier, name, file)) if bodies.empty? && !file_imports(file).includes?(qualifier)
    end
    bodies.max_of? { |body| body_verdict(body, fields) }
  end

  # The `name` methods of the struct type the local `qualifier` is declared
  # with in `file`, when that type lives in another package of the scan.
  private def local_type_methods(qualifier : String, name : String, file : String) : Array(Noir::GoCalleeExtractor::FunctionBody)
    found = [] of Noir::GoCalleeExtractor::FunctionBody
    source = read_file(file) || return found
    source.scan(LOCAL_TYPE) do |m|
      next unless m[1] == qualifier && (package = m[2]?)
      @dirs_by_base[package]?.try &.each do |pkg|
        @bodies.methods_for(pkg)[name]?.try &.each do |body|
          found << body if body.source.match(METHOD_RECEIVER).try(&.[1]) == m[3]
        end
      end
    end
    found.uniq!
  end

  # The strongest refusal in `body` a caller can meet: a 401 or a redirect to
  # login (`Authn`), or a 403 behind a permission test (`Authz`; behind any
  # other test it is `Authn`). Each refusal is read with the `if` conditions
  # it sits under, and does not count when one of them
  #
  # * tests that a request value is present (`if len(sudo) > 0 {`), or
  #   follows an `if !ok { return }` that lets the request through without
  #   it: a caller who sends nothing is never refused;
  # * reads a package-level setting (`setting.Service.RequireSignInView`):
  #   off unless the deployment turns it on;
  # * reads an option the call site's struct literal leaves unset or false.
  #   A factory called with one (`verify(&Options{SignInRequired: true})`)
  #   is shared by public and private routes alike, so only the refusals its
  #   own `true` options select count.
  #
  # With `follow`, an unqualified call to a function of the same package
  # counts as that function's verdict at the line of the call. A statement
  # that calls a method on the body's own receiver (`a.evaluateOr401(ctx)`
  # in `func (a *Auth) RequireClient`) counts as that method's verdict, up
  # to `hops` such calls deep. A call inside an `if` condition is not a
  # statement: `if !a.check(ctx) { ctx.Next() }` lets an anonymous caller
  # through whatever `check` does to one with bad credentials.
  private def body_verdict(body : Noir::GoCalleeExtractor::FunctionBody, fields : Hash(String, String)?, follow : Bool = true, hops : Int32 = 3) : Guard
    key = {body.file_path, body.start_row, follow, hops}
    if fields.nil? && (cached = @helper_verdicts[key]?)
      return cached
    end
    source = Noir::CComments.strip(body.source, quotes: %("'`))
    params = source.match(FUNC_PARAMS).try(&.[1].split(',').compact_map(&.strip.split(/\s+/).first?)) || [] of String
    option_gated = !fields.nil? && params.any? { |param| source.includes?("#{param}.") }
    imports = file_imports(body.file_path)
    package = follow ? @bodies.functions_for(File.dirname(body.file_path)) : nil
    receiver = hops > 0 ? source.match(METHOD_RECEIVER_NAME) : nil
    frames = [] of {Int32, Array(String)}
    depth = 0
    verdict = Guard::None
    lines = source.lines
    lines.each_with_index do |raw, idx|
      line = raw.gsub(STRING_LITERAL, %("")).strip
      closes = line.starts_with?('}')
      if closes
        depth -= 1
        pop_closed(frames, depth)
      end
      opened = line.count('{') - line.count('}') + (closes ? 1 : 0)
      if match = line.match(IF_OPEN)
        # `if !ok { return }`: what follows runs only when the test fails.
        frames << {depth, [negate(match[1], params)]} if passes_through?(lines, idx)
        frames << {depth + opened, match[1].split("&&").map(&.strip)}
      elsif line.matches?(ELSE_OPEN)
        frames << {depth + opened, [] of String}
      end
      depth += opened
      pop_closed(frames, depth)

      conditions = frames.flat_map(&.[1])
      kind = if raw.matches?(LOGIN_REDIRECT)
               Guard::Authn
             elsif line.matches?(REJECTS_REQUEST)
               conditions.any?(&.matches?(AUTHZ_CONDITION)) ? Guard::Authz : Guard::Authn
             elsif receiver && (stmt = line.match(RECEIVER_STATEMENT)) && stmt[1] == receiver[1]
               receiver_method(body, receiver[2], stmt[2]).max_of? { |method| body_verdict(method, nil, follow, hops - 1) } || Guard::None
             elsif package
               line.scan(BODY_CALL).max_of? do |call|
                 package[call[1]]?.try { |helper| body_verdict(helper, nil, false) } || Guard::None
               end || Guard::None
             else
               Guard::None
             end
      next if kind <= verdict
      next if conditions.any? { |condition| dead_condition?(condition, params, imports, fields) }
      next if option_gated && conditions.none? { |condition| option_enabled?(condition, params, fields) }
      verdict = kind
    end
    @helper_verdicts[key] = verdict if fields.nil?
    verdict
  end

  # The `name` methods declared on `type` in `body`'s package.
  private def receiver_method(body : Noir::GoCalleeExtractor::FunctionBody, type : String, name : String) : Array(Noir::GoCalleeExtractor::FunctionBody)
    (@bodies.methods_for(File.dirname(body.file_path))[name]? || [] of Noir::GoCalleeExtractor::FunctionBody).select do |method|
      method.source.match(METHOD_RECEIVER).try(&.[1]) == type
    end
  end

  private def pop_closed(frames : Array({Int32, Array(String)}), depth : Int32)
    while (frame = frames.last?) && frame[0] > depth
      frames.pop
    end
  end

  # Whether the `if` opened at `lines[idx]` only lets the request through.
  private def passes_through?(lines : Array(String), idx : Int32) : Bool
    after = idx + 1
    after += 1 if lines[after]?.try(&.strip.matches?(PASS_STATEMENT))
    lines[after]?.try(&.strip) == "return" && lines[after + 1]?.try(&.strip) == "}"
  end

  # The condition that holds after `if condition { return }`.
  private def negate(condition : String, params : Array(String)) : String
    if (match = condition.match(ABSENCE_TEST)) && !params.includes?(match[1]? || match[2]? || match[3]?)
      PRESENT
    elsif condition.starts_with?('!') && !condition.includes?("&&") && !condition.includes?("||")
      condition[1..].strip
    else
      "!(#{condition})"
    end
  end

  private def dead_condition?(condition : String, params : Array(String), imports : Set(String), fields : Hash(String, String)?) : Bool
    return true if condition == PRESENT
    if (match = condition.match(OPTION_FIELD)) && params.includes?(match[2])
      return false unless fields
      return (fields[match[3]]? == "true") == (match[1] == "!")
    end
    if match = condition.match(PRESENCE_TEST)
      return !params.includes?(match[1]? || match[2]?)
    end
    condition.lstrip('!').strip.lchop('(').rchop(')').split("||").all? do |part|
      (match = part.strip.match(PACKAGE_VALUE)) && imports.includes?(match[1])
    end
  end

  private def option_enabled?(condition : String, params : Array(String), fields : Hash(String, String)?) : Bool
    return false unless (match = condition.match(OPTION_FIELD)) && match[1].empty? && params.includes?(match[2])
    fields.try(&.[match[3]]?) == "true"
  end

  # The package names `path` imports.
  private def file_imports(path : String) : Set(String)
    @imports.put_if_absent(path) do
      read_file(path).try { |source| Noir::GoCalleeExtractor.extract_import_aliases(source).keys.to_set } || Set(String).new
    end
  end

  private def check_endpoint(endpoint : Endpoint)
    # The first `auth` and the first `authz` evidence win (`add_tag` keeps
    # one tag per name), in the order: names on the route line, a `.Use`
    # just above it, its own middleware, closures it sits in, its group.
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?

      # Check the route definition line and surrounding context
      line_idx = line_num - 1 # 0-indexed
      next if line_idx < 0 || line_idx >= lines.size

      # Strings blanked so a path (`"/oauth/authorize"`) is not read as
      # middleware, and the handler dropped so `AuthHandler` is not either.
      route_line = code_only(lines[line_idx]).sub(HANDLER_ARG, ")\\1")

      # Check for inline auth middleware in route definition
      INLINE_AUTH_MIDDLEWARE.each do |pattern|
        if match = route_line.match(pattern)
          endpoint.add_tag(Tag.new("auth", "Protected by Go #{match[0]} middleware", "go_auth"))
          break
        end
      end

      # Check up to 5 lines above for middleware applied to this specific route
      # Go middleware is typically chained immediately before the route handler
      check_idx = line_idx - 1
      while check_idx >= 0 && check_idx >= line_idx - 5
        above_line = lines[check_idx].strip
        # Allow a single blank line directly above the route (Go style
        # often separates a chained `.Use(...)` from the route with one);
        # only stop once we're past that first line.
        break if above_line.empty? && check_idx < line_idx - 1
        # A block closed above the route: a `.Use` in it was that block's.
        break if above_line.starts_with?('}')

        # A chain that keeps its group nowhere guards only its own routes.
        if above_line.includes?(".Use") && !ephemeral_group_use(above_line)
          tag = middleware_args(above_line).compact_map { |arg| guard_by_definition(arg, path_info.path, authish_name: true) }.first?
          tag ||= Tag.new("auth", "Protected by Go JWT middleware", "go_auth") if JWT_PATTERNS.any? { |pattern| above_line.matches?(pattern) }
          if tag
            endpoint.add_tag(tag)
            break
          end
        end

        check_idx -= 1
      end

      # Read the definition of each middleware argument (everything between
      # the path and the handler).
      route_middleware_args(lines, line_idx, endpoint.method).each do |arg|
        guard_by_definition(arg, path_info.path).try { |guard| endpoint.add_tag(guard) }
      end

      @closure_scopes.each do |scope|
        endpoint.add_tag(scope[:tag]) if scope[:file] == path_info.path && scope[:from] < line_num < scope[:to]
      end
    end

    handler_guard_clause(endpoint).try { |tag| endpoint.add_tag(tag) }

    # Phase 3: Check group-level middleware scope
    check_middleware_scopes(endpoint).try { |tag| endpoint.add_tag(tag) }
  end

  # `if <init>; <cond> {` on one line.
  GUARD_IF = /\Aif\s+(?:([^;{]*);\s*)?(.+?)\s*\{\z/

  # The call a guard condition makes: `s.Abort(c)`, `!authorized(c)`, and
  # the chained `Auth(c, x).Abort(c)` (head call in groups 1-2).
  GUARD_CALL         = /\A!?\s*(?:(\w+)\s*\.\s*)?(\w+)\s*\([^()]*\)\z/
  CHAINED_GUARD_CALL = /\A!?\s*(?:(\w+)\s*\.\s*)?(\w+)\s*\(.*\)\s*\.\s*(\w+)\s*\([^()]*\)\z/

  # `name := F(`, `name, err := pkg.F(`, `name = F(`: the call that binds a
  # guard's receiver variable.
  CALL_BINDING = /\A\s*(\w+)\s*(?:,\s*\w+\s*)*:?=\s*(?:(\w+)\s*\.\s*)?(\w+)\s*\(/

  # A method head's receiver type: `func (m *Session) Abort(` -> `Session`.
  METHOD_RECEIVER = /\Afunc\s*\(\s*(?:\w+\s+)?\*?\s*(\w+)/

  # A guard clause at the top level of the endpoint's handler body:
  # `if <call> {` + `return` + `}` where the called function's definition
  # refuses the request (401/403 or a login redirect, see `body_verdict`).
  # The call is a function (`authorized(c)`, `pkg.Check(c)`) or a method on
  # a value the handler gets from a call (`s := Auth(c, ...)` then
  # `s.Abort(c)`, or `Auth(c, ...).Abort(c)`); the method is found through
  # that call's declared result type. Body statements that refuse inline are
  # not read: a login handler's `401` on a bad password is not a guard.
  private def handler_guard_clause(endpoint : Endpoint) : Tag?
    handler = endpoint.handler || return
    path = handler.path || return
    line = handler.line || return
    lines = read_file_lines(path) || return
    start = line - 1
    return if start < 0 || start >= lines.size
    head = code_only(lines[start])
    func_at = head.index("func") || return
    dir = File.dirname(path)
    depth = 0
    opened = false
    idx = start
    while idx < lines.size
      code = idx == start ? head[func_at..] : code_only(lines[idx])
      stripped = code.strip
      if opened && depth == 1 && (m = stripped.match(GUARD_IF)) &&
         lines[idx + 1]?.try(&.strip) == "return" && lines[idx + 2]?.try(&.strip) == "}"
        if tag = guard_call_tag(m[2].strip, m[1]?, lines, start, idx, path, dir)
          return tag
        end
      end
      code.each_char do |char|
        if char == '{'
          depth += 1
          opened = true
        elsif char == '}'
          depth -= 1
        end
      end
      break if opened && depth <= 0
      idx += 1
    end
  end

  private def guard_call_tag(condition : String, init : String?, lines : Array(String), start : Int32, idx : Int32,
                             path : String, dir : String) : Tag?
    bodies = [] of Noir::GoCalleeExtractor::FunctionBody
    shown = condition.lchop('!').strip
    if chained = condition.match(CHAINED_GUARD_CALL)
      bodies = methods_on_result(chained[1]?, chained[2], chained[3], dir)
    elsif call = condition.match(GUARD_CALL)
      qualifier = call[1]?
      name = call[2]
      if qualifier.nil?
        @bodies.functions_for(dir)[name]?.try { |body| bodies << body }
      elsif file_imports(path).includes?(qualifier)
        @dirs_by_base[qualifier]?.try &.each do |pkg|
          @bodies.functions_for(pkg)[name]?.try { |body| bodies << body }
        end
      else
        binding = init.try(&.match(CALL_BINDING)).try { |b| b if b[1] == qualifier }
        (idx - 1).downto(start + 1) do |row|
          break if binding
          binding = code_only(lines[row]).match(CALL_BINDING).try { |b| b if b[1] == qualifier }
        end
        bodies = methods_on_result(binding[2]?, binding[3], name, dir) if binding
      end
    end
    verdict = bodies.max_of? { |body| body_verdict(body, nil) } || Guard::None
    case verdict
    when Guard::Authn
      Tag.new("auth", "Protected by Go guard clause #{shown} (verified from its body: refuses anonymous callers)", "go_auth")
    when Guard::Authz
      Tag.new("authz", "Protected by Go guard clause #{shown} (verified from its body: permission check replies 403)", "go_auth")
    end
  end

  # The `method` definitions on the type the function `qualifier.name`
  # (resolved from `dir`) declares as its first result.
  private def methods_on_result(qualifier : String?, name : String, method : String, dir : String) : Array(Noir::GoCalleeExtractor::FunctionBody)
    functions = [] of Noir::GoCalleeExtractor::FunctionBody
    if qualifier
      @dirs_by_base[qualifier]?.try &.each { |pkg| @bodies.functions_for(pkg)[name]?.try { |body| functions << body } }
    else
      @bodies.functions_for(dir)[name]?.try { |body| functions << body }
    end
    functions.flat_map do |function|
      result = result_type(function.source)
      next [] of Noir::GoCalleeExtractor::FunctionBody unless result
      type_qualifier, type_name = result
      type_dirs = type_qualifier ? (@dirs_by_base[type_qualifier]? || [] of String) : [File.dirname(function.file_path)]
      type_dirs.flat_map do |type_dir|
        (@bodies.methods_for(type_dir)[method]? || [] of Noir::GoCalleeExtractor::FunctionBody).select do |body|
          body.source.match(METHOD_RECEIVER).try(&.[1]) == type_name
        end
      end
    end
  end

  # The first result type of the function whose source starts `source`:
  # `func Auth(c *gin.Context, ...) *entity.Session {` -> {"entity",
  # "Session"}, `func f() (s *Session, err error) {` -> {nil, "Session"}.
  private def result_type(source : String) : Tuple(String?, String)?
    head = source[0, source.index('{') || source.size]
    depth = 0
    seen = 0
    rest = nil
    head.each_char_with_index do |char, pos|
      if char == '('
        depth += 1
      elsif char == ')'
        depth -= 1
        if depth.zero?
          seen += 1
          # A method has its receiver list before the parameter list.
          if seen == (head.lstrip.lchop("func").lstrip.starts_with?('(') ? 2 : 1)
            rest = head[pos + 1..]
            break
          end
        end
      end
    end
    first = rest.try(&.strip.lchop('(').delete(')').split(',').first?.try(&.strip.split(/\s+/).last?)) || return
    type = first.lstrip('*')
    return unless type.matches?(/\A(?:\w+\.)?\w+\z/)
    qualifier, _, name = type.rpartition('.')
    {qualifier.empty? ? nil : qualifier, name}
  end

  # Record a group-level middleware scope. `prefix == "/"` arises two ways:
  # a bare engine-level `.Use(...)` (no enclosing group → truly global, every
  # subsequently registered route is guarded) or an explicit root/empty
  # *group* `g.Group("")` / `g.Group("/")` with a chained `.Use(...)`. Only
  # the latter is a sub-group whose middleware does not reach engine-level
  # static routes, so flag it to scope the coverage refinement below.
  private def add_middleware_scope(scope : GoRouteGroupScope::Scope, tag : Tag)
    @middleware_scopes << {
      prefix:     scope[:prefix],
      tag:        tag,
      root_group: scope[:kind] == GoRouteGroupScope::ScopeKind::Group && scope[:prefix] == "/",
      gate:       @current_gate,
    }
  end

  private def check_middleware_scopes(endpoint : Endpoint) : Tag?
    url = endpoint.url
    # A route chained off a group it builds in place (`g.Group("/user").
    # Use(mw).POST("", h)`) is on no other group, whatever its prefix.
    ephemeral = nil

    @middleware_scopes.each do |scope|
      next unless prefix_covers?(scope[:prefix], url)
      if gate = scope[:gate]
        next unless registered_on?(endpoint, gate)
      elsif scope[:prefix] != "/" || scope[:root_group]
        ephemeral = ephemeral_route?(endpoint) if ephemeral.nil?
        next if ephemeral
      end

      # A `.Use` on an explicit root/empty *group* (`g.Group("")` /
      # `g.Group("/")`) creates a sub-group; in gin it does not reach
      # engine-level static-asset routes (the SPA shell, `/static/*`,
      # favicon, web-app manifest) registered directly on the engine. Those
      # are public, so a broad root-group auth scope must not tag them —
      # the main source of go_auth false positives (e.g. gotify tagging
      # `/`, `/index.html`, `/static/*any`, `/manifest.json` as auth).
      next if scope[:root_group] && static_asset_route?(url)

      return scope[:tag]
    end

    nil
  end

  # Whether one of the endpoint's route lines in the gate's file is a call on
  # its receiver (`authV1.POST("users/add", ...)`), or on a group derived
  # from it (`app := authV1.Group("/app")` then `app.GET(...)`), on one of
  # its rows.
  private def registered_on?(endpoint : Endpoint, gate : Gate) : Bool
    endpoint.details.code_paths.any? do |path_info|
      next false unless path_info.path == gate[:file]
      line = path_info.line
      lines = read_file_lines(gate[:file])
      next false if line.nil? || lines.nil? || line < 1 || line > lines.size || !gate[:rows].includes?(line)
      derived_from?(lines[line - 1].match(ROUTE_RECEIVER).try(&.[1]), gate[:receiver], gate[:parents])
    end
  end

  private def ephemeral_route?(endpoint : Endpoint) : Bool
    endpoint.details.code_paths.any? do |path_info|
      line = path_info.line || next false
      lines = read_file_lines(path_info.path) || next false
      next false if line < 1 || line > lines.size
      !ephemeral_group_use(lines[line - 1].strip).nil?
    end
  end

  private def derived_from?(name : String?, receiver : String, parents : Hash(String, String)) : Bool
    16.times do
      return false unless name
      return true if name == receiver
      name = parents[name]?
    end
    false
  end

  # The 1-based last line of the block holding line `index` (1-based): where
  # the braces opened from that line on first close below their start.
  private def enclosing_block_end(lines : Array(String), index : Int32) : Int32
    depth = 0
    (index - 1).upto(lines.size - 1) do |row|
      code_only(lines[row]).each_char do |char|
        if char == '{'
          depth += 1
        elsif char == '}'
          depth -= 1
          return row + 1 if depth < 0
        end
      end
    end
    lines.size
  end
end
