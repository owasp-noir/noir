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
  # Also GoFrame's `group.Middleware(` and Kratos' `http.Middleware(`
  # server option. (PocketBase's `.Bind(` is gated on the file importing
  # PocketBase: `c.Bind(&req)` is in every gin / echo handler file.)
  USE_REGISTRATION = /\.\s*(?:Use|Pre|Middleware)\s*\(|\.\s*(?:Group|Party)\s*\(\s*"[^"]*"\s*,/

  # Where the middleware arguments start on a `code_only` line (string
  # literals blanked to `""`): right after `.Use(` / `.Pre(` (GoFrame's
  # `.Middleware(`), or after the path literal of a `Group("/seg", ...)`
  # constructor or a route call.
  MIDDLEWARE_ARGS_START = /\.\s*(?:Use|Pre|Middleware)\s*\(|\.\s*\w+\s*\(\s*""\s*,/

  # Middleware added inside a closure group on its router: `.Use(` /
  # `.Pre(`, or, on the closure's own router parameter only, GoFrame's
  # `group.Middleware(` and `.Bind(` (a PocketBase middleware, or a GoFrame
  # controller whose routes the closure's middleware then guards);
  # `group.ALLMap(g.Map{"/x": ctrl.Profile})` binds handlers like `.Bind`.
  CLOSURE_USE        = /(\w+)\.(Use|Pre|Middleware|Bind|ALLMap|Map)\s*\(/
  CLOSURE_PARAM_VERB = %w[Middleware Bind ALLMap Map]
  # The router parameter of a closure opened at the end of a line:
  # `s.Group("/api", func(group *ghttp.RouterGroup) {` -> `group`.
  CLOSURE_PARAM = /\bfunc\s*\(\s*(\w+)\s+[^()]*\)\s*\{\s*\z/

  # PocketBase: `sg := rg.Group("/sql").Bind(mw)` / `sg.Bind(mw)`.
  BIND_REGISTRATION = /\A(\w+)\s*(?::?=\s*\w+(?:\s*\.\s*\w+)*\s*\.\s*Group\s*\([^()]*\)\s*)?\.\s*Bind\s*\(/

  # PocketBase: `sub.GET("", h).Bind(apis.RequireSuperuserAuth())`.
  ROUTE_BIND = /\)\s*\.\s*Bind\s*\(/

  # Kratos: the `http.Middleware(...)` server option (under whatever alias
  # the file imports Kratos' `transport/http` as), run for every route the
  # server serves.
  SERVER_MIDDLEWARE = /\b(\w+)\s*\.\s*Middleware\s*\(/

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
  # PocketBase replies with `e.UnauthorizedError(...)` / `e.ForbiddenError(...)`
  # (before 0.23, `apis.NewUnauthorizedError(...)`), GoFrame with
  # `r.SetError(gerror.NewCode(gcode.CodeNotAuthorized, ...))`.
  REJECTS_REQUEST = /[(,]\s*(?:\w+\.)?Status(?:Unauthorized|Forbidden)\b|[(,]\s*40[13]\s*[,)]|\b(?:\w+\.)?Err(?:Unauthorized|Forbidden)\b|[.\s(]New(?:Unauthorized|Forbidden)Error\s*\(|\.\s*(?:Unauthorized|Forbidden)Error\s*\(|[(,]\s*gcode\s*\.\s*CodeNotAuthorized\b/

  # A redirect to the login page (`ctx.RedirectForLogin(...)`,
  # `c.Redirect(302, "/login")`, `response.HTMLRedirect(w, r, loginURL)`),
  # matched with string literals kept.
  LOGIN_REDIRECT = /(?=.*Redirect\w*\s*\().*(?:[Ll]og_?[Ii]n|[Ss]ign_?[Ii]n)/

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

  # `required` / `!required`: a bare (flag) parameter.
  FLAG_TEST = /\A(!?)\s*(\w+)\z/

  # `pkg.Var.Field` with no call: a package-level (configuration) value.
  PACKAGE_VALUE = /\A!?\s*(\w+)(?:\.\w+)+\z/

  # A middleware config's `Skipper:` set to anything but the default.
  SKIPPER_FIELD = /\bSkipper\s*:(?!\s*(?:nil\b|(?:\w+\.)?DefaultSkipper\b))/

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
  alias Gate = {file: String, receiver: String, rows: Range(Int32, Int32), parents: Hash(String, Array({String, Int32}))}

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
    @middleware_scopes = [] of {prefix: String, tag: Tag, root_group: Bool, gate: Gate?, owner: Gate?, module: String}
    @closure_scopes = [] of {file: String, from: Int32, to: Int32, tag: Tag}
    @current_gate = nil.as(Gate?)
    @current_owner = nil.as(Gate?)
    @bodies = Noir::GoCalleeExtractor::LazyPackageBodies.empty
    @dirs_by_base = Hash(String, Array(String)).new
    @guards = Hash({String, String, Bool, String?}, Tag?).new
    @helper_verdicts = Hash({String, Int32, Bool, Int32, String?, Bool, String?}, Guard).new
    @imports = Hash(String, Set(String)).new
    @import_paths = Hash(String, Hash(String, String)).new
    @bindings = Hash(String, Hash(String, String)).new
    @modules = Hash(String, String).new
    @linked_modules = Hash({String, String}, Bool).new
    @router_chains = Hash({String, Int32, String}, {Array({String, Int32}), Bool}).new
    @owner_uses = Hash({String, Int32, String, String}, Array(Int32)).new
    @bound_requests = Hash(String, Tag).new
    @server_scopes = [] of {owner: Gate, tag: Tag}
    @gozero_groups = Hash(String, Array({Range(Int32, Int32), Array(Tag)})).new
  end

  def self.target_techs : Array(String)
    [
      "go_echo", "go_gin", "go_chi", "go_fiber",
      "go_beego", "go_mux", "go_fasthttp",
      "go_gozero", "go_goyave",
      "go_hertz", "go_iris", "go_gf", "go_http",
      "go_pocketbase", "go_kratos",
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
    @server_scopes.clear
    @bound_requests.clear

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
      # A test's router is its own program, not the one it tests.
      next if file.ends_with?("_test.go")
      content = read_file(file)
      scan_group_middleware(content, file) if content
    end
  end

  private def scan_group_middleware(content : String, file : String)
    uses = USE_REGISTRATION.matches?(content, options: Noir::TextFile::MATCH_OPTIONS)
    closures = CLOSURE_REGISTRATION.matches?(content, options: Noir::TextFile::MATCH_OPTIONS)
    pocketbase = content.includes?("pocketbase/") && content.includes?(".Bind(")
    return unless uses || closures || pocketbase

    # Closures handed to a call (`m.Group("/user", func() {`, chi's
    # `r.Group(func(r chi.Router) {`), with the middleware a `.With(...)` on
    # the opening line or a `.Use(...)` inside puts in front of their routes.
    lines = content.lines
    frames = [] of {line: Int32, depth: Int32, param: String?, args: Array(String), uses: Array({Int32, Array(String)}), binds: Array({Int32, String})}
    depth = 0
    index = 0
    each_group_scoped_line(content) do |stripped, scopes|
      index += 1
      in_closure = false
      server = uses && (option = stripped.match(SERVER_MIDDLEWARE)) && kratos_http?(file, option[1])
      if server
        register_server_scopes(file, lines, index)
      elsif pocketbase && (bind = stripped.match(BIND_REGISTRATION))
        register_bind_scopes(bind, file, lines, index, scopes)
      end
      if closures
        code = code_only(stripped).rstrip
        # A `.Use` on the closure's own router guards the routes after it
        # in that closure, not every route under the group's prefix.
        call = server ? nil : code.match(CLOSURE_USE)
        if (frame = frames.last?) && call && !scopes.groups.has_key?(call[1]) &&
           (!CLOSURE_PARAM_VERB.includes?(call[2]) || call[1] == frame[:param])
          statement = statement_text(lines, index)
          args = (start = statement.match(CLOSURE_USE)) ? call_args(statement[start.end..]) : [] of String
          case call[2]
          when "ALLMap", "Map"
            args.each { |arg| arg.scan(/:\s*(\w+(?:\.\w+)?)\s*[,}]/) { |value| frame[:binds] << {index, value[1]} } }
          when "Bind"
            frame[:uses] << {index, args}
            args.each { |arg| frame[:binds] << {index, arg} }
          else
            frame[:uses] << {index, args}
          end
          in_closure = true
        end
        code.each_char_with_index do |char, pos|
          if char == '{'
            if pos == code.size - 1 && code.matches?(CLOSURE_ARG_OPEN)
              args = (with_call = code.match(WITH_CALL)) ? call_args(code[with_call.end..]) : [] of String
              frames << {line: index, depth: depth, param: code.match(CLOSURE_PARAM).try(&.[1]), args: args,
                         uses: [] of {Int32, Array(String)}, binds: [] of {Int32, String}}
            end
            depth += 1
          elsif char == '}'
            depth -= 1
            next unless (top = frames.last?) && top[:depth] == depth
            frames.pop
            # `}, reqToken(), reqAdmin())`: middleware after the closure.
            guards = (top[:args] + trailing_args(code[pos + 1..], lines, index)).map do |arg|
              {top[:line], add_closure_scope(file, top[:line], index, arg)}
            end
            top[:uses].each do |(line, args)|
              args.each { |arg| guards << {line, add_closure_scope(file, line, index, arg)} }
            end
            # GoFrame: `group.Bind(Ctrl{})` after `group.Middleware(Auth)`,
            # in this closure or one enclosing it, puts the controller's
            # routes, declared with their request types, behind it.
            unless top[:binds].empty?
              frames.each do |outer|
                outer[:args].each { |arg| guards << {outer[:line], guard_by_definition(arg, file, authish_name: true)} }
                outer[:uses].each { |(line, args)| args.each { |arg| guards << {line, guard_by_definition(arg, file, authish_name: true)} } }
              end
            end
            top[:binds].each do |(line, arg)|
              tag = guards.find { |(row, guard)| guard && row < line }.try(&.[1]) || next
              bound_request_types(arg, file).each { |type| @bound_requests.put_if_absent(type) { tag } }
            end
          end
        end
      end
      register_auth_scopes(stripped, scopes, file, lines, index) if uses && !in_closure && !server
    end
  end

  private def add_closure_scope(file : String, from : Int32, to : Int32, arg : String) : Tag?
    tag = guard_by_definition(arg, file, authish_name: true)
    @closure_scopes << {file: file, from: from, to: to, tag: tag} if tag
    tag
  end

  NEW_SERVER = /\b(\w+)\s*:?=\s*(\w+)\s*\.\s*NewServer\s*\(/

  # Whether the import alias `name` is Kratos' HTTP transport in `file`.
  private def kratos_http?(file : String, name : String) : Bool
    !!import_paths(file)[name]?.try { |path| path.includes?("go-kratos/kratos") && path.ends_with?("/transport/http") }
  end

  # Kratos: each guard `http.Middleware(...)` hands the server its function
  # builds (`srv := http.NewServer(http.Middleware(jwt.Server(...)))`,
  # `opts = append(opts, http.Middleware(...))`) runs for every route of
  # that server (see `served_by?`).
  # ponytail: `selector.Server(jwt.Server(...)).Match(whitelist)` is not a
  # guard: the whitelist is not modelled.
  private def register_server_scopes(file : String, lines : Array(String), index : Int32)
    statement = statement_text(lines, index)
    start = statement.match(SERVER_MIDDLEWARE) || return
    head = function_start(lines, index)
    last = head < 0 ? lines.size : enclosing_block_end(lines, head + 2)
    server = ((head + 1)...Math.min(last, lines.size)).compact_map do |row|
      code_only(lines[row]).match(NEW_SERVER).try { |m| m[1] if kratos_http?(file, m[2]) }
    end.first? || return
    owner = {file: file, receiver: server, rows: index..last, parents: {} of String => Array({String, Int32})}
    call_args(statement[start.end..]).each do |arg|
      tag = guard_by_definition(arg, file, authish_name: true) || next
      @server_scopes << {owner: owner, tag: tag}
    end
  end

  # Whether a route of the endpoint is on the owner's server: on it, or a
  # router it hands out (`r := srv.Route("/")`), in the owner's function,
  # or in a function the owner's function hands the server to
  # (`v1.RegisterGreeterHTTPServer(srv, greeter)`).
  private def served_by?(endpoint : Endpoint, owner : Gate) : Bool
    owner_lines = read_file_lines(owner[:file]) || return false
    endpoint.details.code_paths.any? do |path_info|
      line = path_info.line || next false
      lines = read_file_lines(path_info.path) || next false
      next false if line < 1 || line > lines.size
      name = lines[line - 1].match(ROUTE_RECEIVER).try(&.[1]) || next false
      start = function_start(lines, line)
      if path_info.path == owner[:file] && start == function_start(lines, owner[:rows].begin)
        router_chain(path_info.path, lines, line, name)[0].any? { |(router, _)| router == owner[:receiver] }
      else
        helper = start < 0 ? nil : lines[start].match(FUNC_NAME).try(&.[1])
        !!helper && !owner_uses(owner, owner_lines, helper, File.dirname(path_info.path)).empty?
      end
    end
  end

  # PocketBase: the middleware `sg := rg.Group("/sql").Bind(mw)` /
  # `sg.Bind(mw)` binds runs for the routes registered on `sg`, or a group
  # derived from it, below in the block, whatever their prefix.
  private def register_bind_scopes(bind : Regex::MatchData, file : String, lines : Array(String), index : Int32, scopes : GoRouteGroupScope::Scopes)
    statement = statement_text(lines, index)
    start = statement.match(/\.\s*Bind\s*\(/) || return
    gate = {file: file, receiver: bind[1], rows: index..enclosing_block_end(lines, index), parents: scopes.parents}
    call_args(statement[start.end..]).each do |arg|
      tag = guard_by_definition(arg, file, authish_name: true) || next
      @middleware_scopes << {prefix: "/", tag: tag, root_group: false, gate: gate, owner: nil, module: go_module(file)}
    end
  end

  # The request types of the controller methods `group.Bind(arg)` mounts:
  # `Ctrl{}` / `&user.Controller{}` / `user.NewV1()` (or a local bound to
  # one) -> the struct, and `func (c *Ctrl) Profile(ctx context.Context,
  # req *v1.ProfileReq)` -> `ProfileReq`. A method value (`auth.Protected`)
  # mounts that method alone.
  # ponytail: by type name; two packages declaring the same request type
  # name share a verdict.
  private def bound_request_types(arg : String, file : String) : Array(String)
    arg = arg.strip
    method = nil
    if (m = arg.match(/\A(\w+)\.(\w+)\z/)) && !file_imports(file).includes?(m[1])
      arg, method = m[1], m[2]
    end
    if arg.matches?(/\A\w+\z/)
      local = arg
      arg = local_binding(file, local) || (read_file(file) || "").scan(LOCAL_TYPE).find { |t| t[1] == local }.try { |t| "#{t[2]?.try { |pkg| "#{pkg}." }}#{t[3]}{}" } || return [] of String
    end
    type = if m = arg.match(/\A&?\s*(?:(\w+)\.)?([A-Z]\w*)\s*\{/)
             {m[1]?, m[2], File.dirname(file)}
           elsif m = arg.match(/\A(?:(\w+)\.)?(\w+)\s*\(/)
             dirs = m[1]? ? (@dirs_by_base[m[1]]? || [] of String) : [File.dirname(file)]
             dirs.compact_map do |dir|
               function = @bodies.functions_for(dir)[m[2]]? || next
               # The struct it returns: gf's generated `NewV1()` declares an
               # interface result.
               if built = function.source.match(/\breturn\s+&?\s*(?:(\w+)\.)?([A-Z]\w*)\s*\{/)
                 next {built[1]?, built[2], dir}
               end
               result_type(function.source).try { |(qualifier, name)| {qualifier, name, dir} }
             end.first?
           end
    return [] of String unless type
    qualifier, name, from = type
    dirs = qualifier ? (@dirs_by_base[qualifier]? || [] of String) : [from]
    dirs.flat_map do |dir|
      methods = @bodies.methods_for(dir)
      (method ? methods[method]? || [] of Noir::GoCalleeExtractor::FunctionBody : methods.values.flatten).compact_map do |body|
        next unless body.source.match(METHOD_RECEIVER).try(&.[1]) == name
        param = body.source.match(FUNC_PARAMS).try(&.[1].split(',')[1]?) || next
        param.strip.split(/\s+/).last.lstrip('*').rpartition('.')[2]
      end
    end.uniq!
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
    # The group variable the middleware is registered on, with the rows
    # after the registration in its block: in gin a group copies its
    # parent's middleware when it is created, so only groups derived there
    # inherit it.
    @current_owner = receiver ? {file: file, receiver: receiver, rows: index..enclosing_block_end(lines, index), parents: scopes.parents} : nil
    @current_gate = receiver && scopes.aliases.includes?(receiver) ? @current_owner : nil
    # `r.Group("/").Use(auth).POST("/x", h)` with the group kept nowhere:
    # the middleware reaches only the routes chained in that statement.
    # (Handed to a helper instead, `register(r.Group("/").Use(auth))`, it
    # still reaches every route under the prefix.)
    if chain = ephemeral_group_use(stripped)
      @current_gate = {file: file, receiver: chain, rows: index..statement_end(lines, index), parents: {} of String => Array({String, Int32})}
    end

    before = @middleware_scopes.size
    # The whole statement, so a config literal spread over the lines below
    # (`KeyAuthWithConfig(middleware.KeyAuthConfig{` / `Skipper: ...`) is
    # read with its fields.
    statement = statement_text(lines, index)
    args = middleware_args(statement)

    # Check for JWT library middleware
    JWT_PATTERNS.each do |pattern|
      if statement.matches?(pattern) && stripped.includes?(".Use") && args.none?(&.matches?(SKIPPER_FIELD))
        jwt_match = statement.match(pattern)
        jwt_name = jwt_match ? jwt_match[0] : "JWT"
        add_middleware_scope(scope, file, Tag.new("auth", "Protected by Go JWT middleware (#{jwt_name})", "go_auth"))
      end
    end
    return unless before == @middleware_scopes.size

    # Read each middleware argument's definition; its name counts only when
    # the definition is not in the scan.
    args.each do |arg|
      tag = guard_by_definition(arg, file, authish_name: true)
      add_middleware_scope(scope, file, tag) if tag
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
          return code[pos + 1..].matches?(/\A\s*\.\s*(?:[A-Za-z]+\s*\(|\z)/) ? chain[1] : nil
        end
        depth -= 1
      end
    end
  end

  # The statement starting on line `index` (1-based) as code on one line,
  # up to 30 lines of it.
  private def statement_text(lines : Array(String), index : Int32) : String
    (index..Math.min(statement_end(lines, index), index + 30)).join(" ") { |row| code_only(lines[row - 1]) }
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
      # A config with a `Skipper` lets the requests it picks through
      # unchecked: not an unconditional guard.
      next if arg.matches?(SKIPPER_FIELD)
      ref = arg.match(MIDDLEWARE_REFERENCE)
      next unless ref
      qualifier = ref[1].gsub(/\s+/, "").rchop('.')
      name = ref[2]
      reference = qualifier.empty? ? name : "#{qualifier}.#{name}"
      shown = display || reference
      fields = arg.includes?('{') ? arg.scan(LITERAL_FIELD).to_h { |field| {field[1], field[2].strip} } : nil
      # A factory called with flags only (`Auth(false)`): each keyed by its
      # position, read under its parameter's name by `body_verdict`.
      if fields.nil? && arg[ref.end - 1]? == '('
        flags = call_args(arg[ref.end..])
        fields = flags.each_with_index.to_h { |(flag, i)| {i.to_s, flag} } if !flags.empty? && flags.all? { |flag| flag == "true" || flag == "false" }
      end
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
      lines = read_file_lines(file) || [] of String
      lines.each_with_index do |line, idx|
        next unless line.includes?('=')
        code = code_only(line)
        next unless code.matches?(LOCAL_BINDING)
        # A call spread over the lines below, read whole (not a closure's
        # body).
        code = statement_text(lines, idx + 1) if code.count('(') > code.count(')') && !code.includes?("func")
        if match = code.match(LOCAL_BINDING)
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
  # type's method; when that method finds no refusal but hands the request
  # to a call the walk does not follow (`session.Require(c)`, an interface
  # field's `a.V.Verify(c)`), it is nil, so the name decides as for a
  # middleware whose definition is not in the scan.
  # ponytail: same package plus a sibling package directory named like the
  # qualifier (or the local's type package), one hop deep; a guard reached
  # through such a delegated call still resolves by name only.
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
      if bodies.empty? && !file_imports(file).includes?(qualifier)
        typed = local_type_methods(qualifier, name, file)
        verdict = typed.max_of? { |body| body_verdict(body, fields) }
        return if verdict == Guard::None && typed.any? { |body| delegates?(body) }
        return verdict
      end
    end
    bodies.max_of? { |body| body_verdict(body, fields) }
  end

  # A call on a value: `session.Require(c)`, `a.V.Verify(c)`.
  SELECTOR_CALL = /(?<![\w.])(\w+)((?:\s*\.\s*\w+)+)\s*\(/

  # Whether `body` calls something other than its own parameters' methods
  # and single methods on its own receiver, which `body_verdict` follows.
  private def delegates?(body : Noir::GoCalleeExtractor::FunctionBody) : Bool
    source = Noir::CComments.strip(body.source, quotes: %("'`)).gsub(STRING_LITERAL, %(""))
    params = source.match(FUNC_PARAMS).try(&.[1].split(',').compact_map(&.strip.split(/\s+/).first?)) || [] of String
    receiver = source.match(METHOD_RECEIVER_NAME).try(&.[1])
    source.scan(SELECTOR_CALL).any? do |m|
      next false if params.includes?(m[1])
      !(m[1] == receiver && m[2].count('.') == 1)
    end
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
  #
  # A statement calling a function of another scanned package (`response.
  # JSONUnauthorized(w, r)`) counts when that function refuses
  # unconditionally (`strict`): a shared error writer that picks 401 for
  # some errors is not a refusal. A net/http middleware (one that hands on
  # with `next.ServeHTTP`) that returns without handing on when a credential
  # it reads off the request is empty (`apiKey := r.FormValue("api_key")`;
  # `if apiKey == "" { ...; return }`) refuses anonymous callers whatever it
  # writes. With `route_path`, a condition that is a path predicate of the
  # request (`!isPublicRoute(r)`, see `path_predicate`) is read for that
  # route: a refusal it rules out does not count.
  #
  # An `else if` / `else` arm runs only when the arms before it did not, so
  # `if token == "" { next.ServeHTTP(w, r) } else if bad { 401 }` never
  # refuses a caller who sends nothing. Handing the request on is calling
  # any handler the middleware was given (`h.ServeHTTP(w, r)`, `next(w,
  # r)`). With `route_method` too, a test of the request method
  # (`r.Method == http.MethodGet`) is read for the route.
  private def body_verdict(body : Noir::GoCalleeExtractor::FunctionBody, fields : Hash(String, String)?, follow : Bool = true, hops : Int32 = 3,
                           route_path : String? = nil, strict : Bool = false, route_method : String? = nil) : Guard
    key = {body.file_path, body.start_row, follow, hops, route_path, strict, route_method}
    if fields.nil? && (cached = @helper_verdicts[key]?)
      return cached
    end
    source = Noir::CComments.strip(body.source, quotes: %("'`))
    net_http = source.includes?(".ServeHTTP(")
    credentials = Set(String).new
    params = source.match(FUNC_PARAMS).try(&.[1].split(',').compact_map(&.strip.split(/\s+/).first?)) || [] of String
    fields = fields.transform_keys { |name| name.to_i?.try { |i| params[i]? } || name } if fields
    option_gated = !fields.nil? && params.any? { |param| source.includes?("#{param}.") }
    imports = file_imports(body.file_path)
    package = follow ? @bodies.functions_for(File.dirname(body.file_path)) : nil
    receiver = hops > 0 ? source.match(METHOD_RECEIVER_NAME) : nil
    passers = source.scan(HANDLER_PARAM).map(&.[1]).to_set
    # Each open condition, as read (strings blanked) and as written.
    frames = [] of {Int32, Array(String), Array(String)}
    # Per depth, the negations of the arms of the `if` chain open there.
    chains = Hash(Int32, {Array(String), Array(String)}).new
    depth = 0
    verdict = Guard::None
    lines = source.lines
    branched = false
    lines.each_with_index do |raw, idx|
      line = raw.gsub(STRING_LITERAL, %("")).strip
      branched ||= line.matches?(BRANCH_LINE)
      if net_http && (read = raw.strip.match(CREDENTIAL_READ)) && CREDENTIAL_KEYS.includes?(read[2].downcase.delete("-_"))
        credentials << read[1]
      end
      closes = line.starts_with?('}')
      if closes
        depth -= 1
        pop_closed(frames, depth)
      end
      opened = line.count('{') - line.count('}') + (closes ? 1 : 0)
      if match = line.match(IF_OPEN)
        written = raw.strip.match(IF_OPEN).try(&.[1]) || match[1]
        prior = (line.starts_with?('}') ? chains[depth]? : nil) || {[] of String, [] of String}
        # `if !ok { return }`: what follows runs only when the test fails.
        if passes_through?(lines, idx, passers)
          frames << {depth, [negate(match[1], params)], [negate(written, params)]}
        end
        frames << {depth + opened, prior[0] + match[1].split("&&").map(&.strip), prior[1] + written.split("&&").map(&.strip)}
        chains[depth] = {prior[0] + [negate(match[1], params)], prior[1] + [negate(written, params)]}
      elsif line.matches?(ELSE_OPEN)
        prior = chains[depth]? || {[] of String, [] of String}
        frames << {depth + opened, prior[0], prior[1]}
      end
      depth += opened
      pop_closed(frames, depth)

      conditions = frames.flat_map(&.[1])
      written_conditions = frames.flat_map(&.[2])
      next if strict && (branched || !conditions.empty?)
      kind = if raw.matches?(LOGIN_REDIRECT)
               Guard::Authn
             elsif line.matches?(REJECTS_REQUEST)
               # A test of the route's path or method says nothing about what
               # the caller may do.
               tests = route_path && conditions.size == written_conditions.size ? conditions.each_with_index.reject { |(_, i)| !request_test(written_conditions[i], body, route_path, route_method).nil? }.map(&.[0]).to_a : conditions
               tests.any?(&.matches?(AUTHZ_CONDITION)) ? Guard::Authz : Guard::Authn
             elsif receiver && (stmt = line.match(RECEIVER_STATEMENT)) && stmt[1] == receiver[1]
               receiver_method(body, receiver[2], stmt[2]).max_of? { |method| body_verdict(method, nil, follow, hops - 1, route_path, route_method: route_method) } || Guard::None
             elsif (absent = line.match(IF_OPEN)) && (test = absent[1].match(ABSENCE_TEST)) &&
                   credentials.includes?(test[1]? || test[2]? || test[3]? || "") && stops_request?(lines, idx, passers)
               Guard::Authn
             elsif package && idx > 0 # the head line names the function itself
               called = line.scan(BODY_CALL).max_of? do |call|
                 package[call[1]]?.try { |helper| body_verdict(helper, nil, false) } || Guard::None
               end || Guard::None
               called == Guard::None && !line.matches?(BRANCH_LINE) ? imported_call_verdict(line, imports) : called
             else
               Guard::None
             end
      next if kind <= verdict
      next if conditions.any? { |condition| dead_condition?(condition, params, imports, fields) }
      next if route_path && written_conditions.any? { |condition| request_test(condition, body, route_path, route_method) == false }
      next if option_gated && conditions.none? { |condition| option_enabled?(condition, params, fields) }
      verdict = kind
    end
    @helper_verdicts[key] = verdict if fields.nil?
    verdict
  end

  # A control-flow line: a refusal under it is conditional.
  BRANCH_LINE = /\A(?:\}\s*)?(?:else\b|if\b|for\b|switch\b|select\b|case\b|default\s*:)/

  # `apiKey := r.FormValue("api_key")`: a request value bound to a local.
  CREDENTIAL_READ = /\A(\w+)\s*:?=\s*\w+\s*\.\s*(?:FormValue|PostFormValue|Header\s*\.\s*Get|URL\s*\.\s*Query\(\)\s*\.\s*Get|Form\s*\.\s*Get)\s*\(\s*"([^"]+)"\s*\)\z/
  # The request keys that carry the caller's credential, lowercased without
  # `-` / `_` (`api_key`, `X-Auth-Token`). A request is stopped for lack of
  # one only as authentication; a stop for lack of an `Idempotency-Key` or
  # a `page_token` is not.
  CREDENTIAL_KEYS = Set{"authorization", "apikey", "xapikey", "accesstoken", "authtoken", "xauthtoken", "token",
                        "session", "sessionid", "sessiontoken", "jwt", "bearer"}

  # A call into another scanned package: `response.JSONUnauthorized(`.
  IMPORTED_CALL = /(?<![\w.])(\w+)\s*\.\s*(\w+)\s*\(/

  # The verdict of the functions of other scanned packages a statement
  # calls, each read strictly (see `body_verdict`).
  private def imported_call_verdict(line : String, imports : Set(String)) : Guard
    line.scan(IMPORTED_CALL).max_of? do |call|
      next Guard::None unless imports.includes?(call[1])
      (@dirs_by_base[call[1]]? || [] of String).max_of? do |dir|
        @bodies.functions_for(dir)[call[2]]?.try { |helper| body_verdict(helper, nil, false, strict: true) } || Guard::None
      end || Guard::None
    end || Guard::None
  end

  # Whether the `if` block opened at `lines[idx]` returns without handing the
  # request on.
  private def stops_request?(lines : Array(String), idx : Int32, passers : Set(String)) : Bool
    block = if_block(lines, idx)
    block.includes?("return") && block.none? { |stmt| passes_on?(stmt, passers) }
  end

  # `next.ServeHTTP(w, r)`, `c.Next()`, or a call of a handler the
  # middleware was given (`h.ServeHTTP(w, r)`, `next(w, r)`).
  private def passes_on?(stmt : String, passers : Set(String)) : Bool
    return true if stmt.matches?(PASS_STATEMENT)
    !!(m = stmt.match(/\A(\w+)\s*(?:\.\s*ServeHTTP\s*)?\(/)) && passers.includes?(m[1])
  end

  # What `condition` is for a request to `route_path` with `route_method`,
  # when it only tests the request path (inline, `strings.HasPrefix(r.URL.
  # Path, "/pub/")`, or through a predicate of the body's package,
  # `!isPublicRoute(r)`) or the method (`r.Method == http.MethodGet`). Nil
  # when it tests anything else. A subtree pattern (`/fever/`) stands for
  # every path under it.
  private def request_test(condition : String, body : Noir::GoCalleeExtractor::FunctionBody, route_path : String, route_method : String?) : Bool?
    path = route_path.includes?("{$}") ? route_path.sub("{$}", "") : (route_path.ends_with?('/') ? "#{route_path}{rest...}" : route_path)
    path_test(condition, path, nil, body, 0, route_method)
  end

  PREDICATE_CALL = /\A(\w+)\s*\(\s*\w+\s*\)\z/
  PATH_BINDING   = /\A(\w+)\s*:=\s*(\w+)\.URL\.Path\z/
  SWITCH_ON      = /\Aswitch\s+([\w.]+)\s*\{\z/
  CASE_ARM       = /\Acase\s+(.+):\z/
  RETURN_BOOL    = /\Areturn\s+(true|false)\z/
  IF_TEST        = /\Aif\s+(.+?)\s*\{\z/
  RETURN_TEST    = /\Areturn\s+(.+)\z/
  STRING_TEST    = /\Astrings\.Has(Prefix|Suffix)\(\s*([\w.]+)\s*,\s*"([^"]*)"\s*\)\z/
  EQUALITY_TEST  = /\A([\w.]+)\s*(==|!=)\s*"([^"]*)"\z/

  # What the predicate `body` (`func isPublicRoute(r *http.Request) bool`)
  # returns for a request to `path`, when it only reads the request path:
  # `switch path { case "/a", "/b": return true }`, `if <test> { return
  # true }` and a final `return <test>`, the tests being `strings.HasPrefix`
  # / `HasSuffix`, `==` / `!=` on the path and calls to other such
  # predicates, joined by `||`, `&&` and `!`. Nil for anything else.
  # ponytail: the route path as declared; a predicate behind
  # `http.StripPrefix` sees the stripped path.
  private def path_predicate(body : Noir::GoCalleeExtractor::FunctionBody, path : String, depth : Int32 = 0) : Bool?
    return if depth > 3
    source = Noir::CComments.strip(body.source, quotes: %("'`))
    return unless source.includes?(".URL.Path")
    request = source.match(FUNC_PARAMS).try(&.[1].split(',').first?.try(&.strip.split(/\s+/).first?)) || return
    names = Set{"#{request}.URL.Path"}
    statements = [] of String
    pending = ""
    (source.lines[1..]? || [] of String).each do |raw|
      text = raw.strip
      next if text.empty?
      pending = pending.empty? ? text : "#{pending} #{text}"
      next if pending.ends_with?("||") || pending.ends_with?("&&") || pending.ends_with?(',') || pending.count('(') > pending.count(')')
      statements << pending
      pending = ""
    end
    idx = 0
    while idx < statements.size
      stmt = statements[idx]
      idx += 1
      next if stmt == "}"
      if m = stmt.match(PATH_BINDING)
        return unless m[2] == request
        names << m[1]
      elsif m = stmt.match(SWITCH_ON)
        return unless names.includes?(m[1])
        while idx < statements.size && statements[idx] != "}"
          arm = statements[idx].match(CASE_ARM) || return
          ret = statements[idx + 1]?.try(&.match(RETURN_BOOL)) || return
          literals = arm[1].split(',').map(&.strip)
          return unless literals.all?(&.matches?(/\A"[^"]*"\z/))
          # A pattern that may equal a literal decides nothing.
          matches = literals.map { |lit| path_equals?(path, lit[1...-1]) }
          return if matches.includes?(nil)
          return ret[1] == "true" if matches.includes?(true)
          idx += 2
        end
        idx += 1
      elsif m = stmt.match(IF_TEST)
        test = path_test(m[1], path, names, body, depth)
        ret = statements[idx]?.try(&.match(RETURN_BOOL))
        return if ret.nil? || statements[idx + 1]? != "}" || test.nil?
        return ret[1] == "true" if test
        idx += 2
      elsif m = stmt.match(RETURN_TEST)
        return path_test(m[1], path, names, body, depth)
      else
        return
      end
    end
  end

  # One test of a path predicate, see `path_predicate`.
  # `names` are the expressions holding the path; nil reads any
  # `<request>.URL.Path`.
  private def path_test(expr : String, path : String, names : Set(String)?, body : Noir::GoCalleeExtractor::FunctionBody, depth : Int32,
                        method : String? = nil) : Bool?
    expr = expr.strip
    while expr.starts_with?('(') && expr.ends_with?(')') && wraps_whole?(expr)
      expr = expr[1...-1].strip
    end
    {"||", "&&"}.each do |op|
      parts = split_top_level(expr, op)
      next if parts.size < 2
      values = parts.map { |part| path_test(part, path, names, body, depth, method) }
      decided = op == "||"
      return decided if values.includes?(decided)
      return values.includes?(nil) ? nil : !decided
    end
    return path_test(expr[1..], path, names, body, depth, method).try { |value| !value } if expr.starts_with?('!')
    return true if expr == "true"
    return false if expr == "false"
    if method && (m = expr.match(METHOD_TEST))
      return (method == (m[2]? || m[3]).upcase) == (m[1] == "==")
    end
    if m = expr.match(STRING_TEST)
      return unless path_name?(names, m[2])
      return m[1] == "Prefix" ? path_has_prefix?(path, m[3]) : path_has_suffix?(path, m[3])
    end
    if m = expr.match(EQUALITY_TEST)
      return unless path_name?(names, m[1])
      return path_equals?(path, m[3]).try { |value| m[2] == "==" ? value : !value }
    end
    if (m = expr.match(PREDICATE_CALL)) && (predicate = @bodies.functions_for(File.dirname(body.file_path))[m[1]]?)
      return path_predicate(predicate, path, depth + 1)
    end
    nil
  end

  METHOD_TEST = /\A\w+\.Method\s*(==|!=)\s*(?:http\.Method(\w+)|"(\w+)")\z/

  private def path_name?(names : Set(String)?, expr : String) : Bool
    names ? names.includes?(expr) : expr.matches?(/\A\w+\.URL\.Path\z/)
  end

  # Whether the parentheses opening `expr` close at its end.
  private def wraps_whole?(expr : String) : Bool
    depth = 0
    expr.each_char_with_index do |char, pos|
      depth += 1 if char == '('
      depth -= 1 if char == ')'
      return pos == expr.size - 1 if depth.zero?
    end
    false
  end

  # `expr` split at `op` outside parentheses and string literals.
  private def split_top_level(expr : String, op : String) : Array(String)
    parts = [] of String
    depth = 0
    start = 0
    quoted = false
    pos = 0
    while pos < expr.size
      char = expr[pos]
      if char == '"' && (pos == 0 || expr[pos - 1] != '\\')
        quoted = !quoted
      elsif !quoted
        depth += 1 if char == '('
        depth -= 1 if char == ')'
        if depth.zero? && expr[pos, op.size] == op
          parts << expr[start...pos].strip
          pos += op.size
          start = pos
          next
        end
      end
      pos += 1
    end
    parts << expr[start..].strip
    parts
  end

  # A ServeMux pattern's literal head before its first wildcard, and
  # whether it has one.
  private def static_head(path : String) : Tuple(String, Bool)
    brace = path.index('{')
    brace ? {path[0, brace], true} : {path, false}
  end

  private def path_equals?(path : String, literal : String) : Bool?
    head, wild = static_head(path)
    return head == literal unless wild
    literal.starts_with?(head) ? nil : false
  end

  private def path_has_prefix?(path : String, literal : String) : Bool?
    head, wild = static_head(path)
    return true if head.starts_with?(literal)
    return false unless wild
    literal.starts_with?(head) ? nil : false
  end

  private def path_has_suffix?(path : String, literal : String) : Bool?
    close = path.rindex('}') || return path.ends_with?(literal)
    tail = path[close + 1..]
    return if tail.empty?
    return true if tail.ends_with?(literal)
    literal.ends_with?(tail) ? nil : false
  end

  # The `name` methods declared on `type` in `body`'s package.
  private def receiver_method(body : Noir::GoCalleeExtractor::FunctionBody, type : String, name : String) : Array(Noir::GoCalleeExtractor::FunctionBody)
    (@bodies.methods_for(File.dirname(body.file_path))[name]? || [] of Noir::GoCalleeExtractor::FunctionBody).select do |method|
      method.source.match(METHOD_RECEIVER).try(&.[1]) == type
    end
  end

  private def pop_closed(frames : Array({Int32, Array(String), Array(String)}), depth : Int32)
    while (frame = frames.last?) && frame[0] > depth
      frames.pop
    end
  end

  # Whether the `if` opened at `lines[idx]` only lets the request through.
  # It ends in `return`, right after handing the request on or alone
  # (`if token == "" { log(...); next.ServeHTTP(w, r); return }`).
  private def passes_through?(lines : Array(String), idx : Int32, passers : Set(String) = Set(String).new) : Bool
    block = if_block(lines, idx)
    return false unless block.last? == "return"
    block.size == 1 || passes_on?(block[-2], passers)
  end

  # The stripped statement lines of the block opened at the end of
  # `lines[idx]`.
  private def if_block(lines : Array(String), idx : Int32) : Array(String)
    block = [] of String
    depth = 0
    (idx...lines.size).each do |row|
      code = lines[row].gsub(STRING_LITERAL, %(""))
      depth += code.count('{') - code.count('}')
      break if depth <= 0
      block << code.strip if row > idx && !code.blank?
    end
    block
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
    # `if required {` on a flag the call site passes (`Auth(false)`).
    if fields && (match = condition.match(FLAG_TEST)) && params.includes?(match[2]) && (flag = fields[match[2]]?)
      return (flag == "true") == (match[1] == "!")
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
    @imports.put_if_absent(path) { import_paths(path).keys.to_set }
  end

  # Alias -> import path of each import of `path`.
  private def import_paths(path : String) : Hash(String, String)
    @import_paths.put_if_absent(path) do
      read_file(path).try { |source| Noir::GoCalleeExtractor.extract_import_aliases(source) } || Hash(String, String).new
    end
  end

  private def check_endpoint(endpoint : Endpoint)
    # net/http registers no middleware by name or by group: only what wraps
    # the route's handler or mux, and the handler's own guard clauses.
    if endpoint.details.technology == "go_http"
      net_http_guards(endpoint)
      handler_guard_clause(endpoint).try { |tag| endpoint.add_tag(tag) }
      return
    end

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
      # on the same router: a `.Use` on another group (`v1.Use(auth)` above
      # `health.GET(...)`) is that group's.
      route_receiver = lines[line_idx].match(ROUTE_RECEIVER).try(&.[1])
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
        use_receiver = above_line.match(GoRouteGroupScope::USE_CALL).try(&.[1])
        if above_line.includes?(".Use") && !ephemeral_group_use(above_line) &&
           (route_receiver.nil? || use_receiver.nil? ||
           router_chain(path_info.path, lines, line_num, route_receiver)[0].any? { |(router, _)| router == use_receiver })
          statement = statement_text(lines, check_idx + 1)
          args = middleware_args(statement)
          tag = args.compact_map { |arg| guard_by_definition(arg, path_info.path, authish_name: true) }.first?
          if tag.nil? && args.none?(&.matches?(SKIPPER_FIELD)) && JWT_PATTERNS.any? { |pattern| statement.matches?(pattern) }
            tag = Tag.new("auth", "Protected by Go JWT middleware", "go_auth")
          end
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

      case endpoint.details.technology
      when "go_pocketbase"
        # Middleware bound on the route itself, the chain read on across
        # lines (`sub.GET("", h).` then `Bind(mw)`).
        statement = statement_text(lines, line_num)
        last = statement_end(lines, line_num)
        while last < lines.size && last < line_num + 10 && (code_only(lines[last - 1]).rstrip.ends_with?('.') || lines[last].lstrip.starts_with?('.'))
          statement += " " + statement_text(lines, last + 1)
          last = statement_end(lines, last + 1)
        end
        if bind = statement.match(ROUTE_BIND)
          call_args(statement[bind.end..]).each do |arg|
            guard_by_definition(arg, path_info.path, authish_name: true).try { |guard| endpoint.add_tag(guard) }
          end
        end
      when "go_gozero"
        gozero_guards(path_info.path, lines, line_idx).each { |guard| endpoint.add_tag(guard) }
      when "go_gf"
        bound_request_guard(lines, line_idx).try { |guard| endpoint.add_tag(guard) }
      end

      @closure_scopes.each do |scope|
        endpoint.add_tag(scope[:tag]) if scope[:file] == path_info.path && scope[:from] < line_num < scope[:to]
      end
    end

    handler_guard_clause(endpoint).try { |tag| endpoint.add_tag(tag) }

    # Phase 3: Check group-level middleware scope
    check_middleware_scopes(endpoint).try { |tag| endpoint.add_tag(tag) }
    @server_scopes.each { |scope| endpoint.add_tag(scope[:tag]) if served_by?(endpoint, scope[:owner]) }
  end

  # --- go-zero / GoFrame ---------------------------------------------------

  GOZERO_SERVICE     = /\Aservice\s+[\w-]+\s*\{/
  GOZERO_KEY         = /\b(jwt|middleware)\s*:\s*(\w+(?:\s*,\s*\w+)*)/
  GOZERO_ROUTES      = /\.\s*AddRoutes\s*\(/
  GOZERO_MIDDLEWARES = /rest\s*\.\s*WithMiddlewares\s*\(\s*\[\]\s*rest\s*\.\s*Middleware\s*\{([^}]*)\}/

  # go-zero: the `jwt:` / `middleware:` keys of the `@server(...)` block
  # over the route's `service` block in an `.api` file, or the
  # `rest.WithJwt(...)` / `rest.WithMiddlewares(...)` options of the
  # `server.AddRoutes(...)` call a generated `routes.go` route sits in.
  private def gozero_guards(path : String, lines : Array(String), idx : Int32) : Array(Tag)
    if path.ends_with?(".api")
      service = idx.downto(0).find { |row| lines[row].strip.matches?(GOZERO_SERVICE) } || return [] of Tag
      head = (service - 1).downto(0).find { |row| (line = lines[row].strip).starts_with?("@server") || line.starts_with?('}') }
      return [] of Tag unless head && lines[head].strip.starts_with?("@server")
      return gozero_option_tags((head...service).join(" ") { |row| code_only(lines[row]) })
    end
    # Each `AddRoutes(...)` call of the file, read once.
    groups = @gozero_groups.put_if_absent(path) do
      lines.each_index.select { |row| lines[row].matches?(GOZERO_ROUTES) }.map do |row|
        last = statement_end(lines, row + 1)
        {(row + 1)..last, gozero_option_tags((row + 1..last).join(" ") { |line| code_only(lines[line - 1]) })}
      end.to_a
    end
    groups.find { |(rows, _)| rows.includes?(idx + 1) }.try(&.[1]) || [] of Tag
  end

  private def gozero_option_tags(text : String) : Array(Tag)
    tags = [] of Tag
    middlewares = [] of String
    text.scan(GOZERO_KEY) do |m|
      if m[1] == "jwt"
        tags << Tag.new("auth", "Protected by go-zero JWT (jwt: #{m[2]})", "go_auth")
      else
        middlewares.concat(m[2].split(',').map(&.strip))
      end
    end
    tags << Tag.new("auth", "Protected by go-zero JWT (rest.WithJwt)", "go_auth") if text.includes?("WithJwt(")
    text.scan(GOZERO_MIDDLEWARES) { |m| middlewares.concat(m[1].split(',').map(&.strip.rpartition('.')[2])) }
    middlewares.each { |name| gozero_middleware_tag(name).try { |tag| tags << tag } }
    tags
  end

  # A go-zero middleware `Name` is the `Handle` method of `NameMiddleware`,
  # generated under `internal/middleware/`; it guards when its body
  # refuses the request.
  private def gozero_middleware_tag(name : String) : Tag?
    bodies = (@dirs_by_base["middleware"]? || [] of String).flat_map do |dir|
      (@bodies.methods_for(dir)["Handle"]? || [] of Noir::GoCalleeExtractor::FunctionBody).select do |body|
        body.source.match(METHOD_RECEIVER).try(&.[1]) == "#{name}Middleware"
      end
    end
    case bodies.max_of? { |body| body_verdict(body, nil) }
    when Guard::Authn
      Tag.new("auth", "Protected by go-zero middleware #{name} (verified from its body: refuses anonymous callers)", "go_auth")
    when Guard::Authz
      Tag.new("authz", "Protected by go-zero middleware #{name} (verified from its body: permission check replies 403)", "go_auth")
    end
  end

  # GoFrame: a `g.Meta` route declared in the request struct of a
  # controller a guarded group binds (see `bound_request_types`).
  private def bound_request_guard(lines : Array(String), idx : Int32) : Tag?
    return if @bound_requests.empty?
    idx.downto(Math.max(idx - 30, 0)) do |row|
      line = lines[row].strip
      return if row < idx && line.starts_with?('}')
      # Also a struct of a grouped `type ( ... )` block.
      if m = line.match(/\A(?:type\s+)?(\w+)\s+struct\b/)
        return @bound_requests[m[1]]?
      end
    end
  end

  # --- net/http ServeMux ---------------------------------------------------

  # `mux.Handle(` / `mux.HandleFunc(` at a statement start, with the mux.
  NET_HTTP_ROUTE = /\A\s*(\w+(?:\s*\.\s*\w+)*?)\s*\.\s*(?:Handle|HandleFunc)\s*\(/
  # A statement binding its right-hand side: `h := x`, `h = x`, `var h T = x`.
  NET_HTTP_ASSIGNMENT = /\A\s*(?:var\s+)?(\w+)(?:\s+[\w.*\[\]]+)?\s*:?=(?!=)\s*/
  # What a local is bound to: a struct literal or a call, by type or callee.
  BOUND_TYPE  = /\A&?\s*(?:(\w+)\.)?(\w+)\s*\{/
  BOUND_CALL  = /\A(?:(\w+)\.)?(\w+)\s*\(/
  RETURN_EXPR = /\A\s*return\s+(.+)\z/
  MOUNT_HEAD  = /\A(\w+)\.(?:Handle|HandleFunc)\z/
  # A call's callee at the start of an expression.
  LEADING_CALL = /\A((?:\w+\s*\.\s*)*\w+)\s*\(/

  # One statement of a function, joined across lines until its parentheses
  # balance, with strings blanked; `depth` is its brace depth (1 at the top
  # of the function body).
  record NetHttpStatement, row : Int32, text : String, depth : Int32

  # A wrapper call, and whether it is applied only inside a block (`if
  # os.Getenv("AUTH") == "on" { h = requireAuth(h) }`): a setting decides.
  alias Wrap = {String, Bool}

  # net/http has no `.Use`: a route's middleware wraps its handler
  # (`mux.Handle("/x", auth(h))`, also through a local bound to the wrapped
  # handler or to a closure that wraps it, `withAuth := func(fn
  # http.HandlerFunc) http.Handler { return a.check(fn) }`) or the mux it is
  # registered on (`return mw.cors(mw.auth(mux))`, `h := auth(mux)`, or
  # `root.Handle("/", auth(mux))` and then what wraps `root`), in the
  # function that registers the route. Only a call the value is handed to
  # directly counts, and only one whose definition is a middleware: it takes
  # a handler and hands the request to it (see `middleware_definition?`);
  # each is judged by its definition, read for the route's path and method
  # (see `body_verdict`). A mux is guarded by its wrappers only when every
  # use that serves it is wrapped (`root.Handle("/api/", auth(api))` next to
  # `root.Handle("/legacy/", api)` leaves it open).
  # ponytail: within that function; a mux handed in as a parameter, or
  # returned to a caller that wraps it, is not followed.
  private def net_http_guards(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      next unless path_info.path.ends_with?(".go")
      line = path_info.line || next
      lines = read_file_lines(path_info.path) || next
      statements = function_statements(path_info.path, lines, line - 1) || next
      index = statements.index { |stmt| stmt.row == line - 1 } || next
      stmt = statements[index].text
      route = stmt.match(NET_HTTP_ROUTE) || next
      receiver = route[1].gsub(/\s+/, "")
      handler = call_args(stmt[route.end..]).last? || next
      # The URL drops a pattern's `{$}` end anchor (`GET /{$}` is `/` only,
      # not the subtree `/`); read it back off the registration.
      route_path = endpoint.url
      route_path += "{$}" if !route_path.includes?("{$}") && lines[line - 1].match(/"(?:[A-Z]+\s+)?[^"]*\{\$\}"/)
      judge = ->(wraps : Array(Wrap)) do
        wraps.uniq.compact_map { |(head, conditional)| net_http_guard(head, path_info.path, statements, route_path, endpoint.method, conditional) }
      end
      tags = judge.call(handler_wraps(handler.strip, statements, index, lines, 0))
      unless receiver == "http"
        chains = mux_chains(receiver, statements, Set(String).new)
        verdicts = chains.map { |chain| judge.call(chain) }
        tags.concat(verdicts.first) if !verdicts.empty? && verdicts.all? { |found| !found.empty? }
      end
      tags.each { |tag| endpoint.add_tag(tag) }
    end
  end

  @function_statements = Hash({String, Int32}, Array(NetHttpStatement)).new

  # The function holding `lines[idx]`, statement by statement; the first is
  # the function's own head.
  private def function_statements(file : String, lines : Array(String), idx : Int32) : Array(NetHttpStatement)?
    return if idx < 0 || idx >= lines.size
    start = idx
    while start > 0 && !lines[start].starts_with?("func")
      start -= 1
    end
    return unless lines[start].starts_with?("func")
    @function_statements.put_if_absent({file, start}) do
      statements = [] of NetHttpStatement
      depth = 0
      pending = nil.as(NetHttpStatement?)
      (start...lines.size).each do |row|
        code = code_only(lines[row]).strip
        text = pending ? "#{pending.text} #{code}" : code
        current = NetHttpStatement.new(pending ? pending.row : row, text, pending ? pending.depth : depth)
        if text.count('(') > text.count(')')
          pending = current
        else
          pending = nil
          statements << current
        end
        depth += code.count('{') - code.count('}')
        break if depth <= 0 && row > start
      end
      statements
    end
  end

  # The wrapper calls of a handler expression, outermost first: `a(b(h))`
  # -> a, b; `mw(x)(h)` -> mw. Closure bodies are not read, and neither are
  # a call's other arguments.
  private def wrap_chain(expr : String) : Array(String)
    heads = [] of String
    text = expr.strip
    8.times do
      break if text.starts_with?("func")
      m = text.match(LEADING_CALL) || break
      open = m.end - 1
      close = closing_paren(text, open) || break
      head = m[1].gsub(/\s+/, "")
      if close == text.size - 1
        heads << head
        text = call_args(text[open + 1..]).last?.try(&.strip) || break
      elsif text[close + 1..].lstrip.starts_with?('(') && (second = text.index('(', close + 1)) && closing_paren(text, second) == text.size - 1
        heads << head
        text = text[second + 1...-1].strip
      else
        break
      end
    end
    heads
  end

  private def closing_paren(text : String, open : Int32) : Int32?
    depth = 0
    (open...text.size).each do |pos|
      depth += 1 if text[pos] == '('
      next unless text[pos] == ')'
      depth -= 1
      return pos if depth.zero?
    end
  end

  # The wrappers of a route's handler argument: its own wrapper calls, a
  # local it names bound to wrapped values (`h := newReport(db)` then
  # `h = withAuth(h)`, read back through each rebinding), and what a local
  # closure among them returns.
  private def handler_wraps(handler : String, statements : Array(NetHttpStatement), before : Int32, lines : Array(String), depth : Int32) : Array(Wrap)
    wraps = [] of Wrap
    return wraps if depth > 4
    if handler.matches?(/\A\w+\z/)
      found = binding_before(handler, statements, before) || return wraps
      at, value = found
      conditional = statements[at].depth > statements[before].depth
      wrap_chain(value).each { |head| wraps.concat(closure_or_head(head, statements, lines, conditional)) }
      # `h = withAuth(h)`: the earlier binding of `h` is what it wraps.
      innermost = innermost_arg(value)
      wraps.concat(handler_wraps(handler, statements, at, lines, depth + 1)) if innermost == handler
    else
      wrap_chain(handler).each { |head| wraps.concat(closure_or_head(head, statements, lines, false)) }
    end
    wraps
  end

  # A head naming a local closure stands for the wrappers it returns.
  private def closure_or_head(head : String, statements : Array(NetHttpStatement), lines : Array(String), conditional : Bool) : Array(Wrap)
    if !head.includes?('.') && (returned = closure_returns(head, statements, lines))
      returned.map { |inner| {inner, conditional} }
    else
      [{head, conditional}]
    end
  end

  # The argument a wrapper chain ends at: `h` in `withAuth(cors(h))`.
  private def innermost_arg(expr : String) : String
    text = expr.strip
    8.times do
      m = text.match(LEADING_CALL) || break
      close = closing_paren(text, m.end - 1) || break
      break unless close == text.size - 1
      text = call_args(text[m.end..]).last?.try(&.strip) || break
    end
    text
  end

  # The last statement binding `name` above statement `before`, and the
  # value it assigns; nil for none or a closure.
  private def binding_before(name : String, statements : Array(NetHttpStatement), before : Int32) : {Int32, String}?
    (before - 1).downto(1) do |at|
      text = statements[at].text
      assign = text.match(NET_HTTP_ASSIGNMENT) || next
      next unless assign[1] == name
      value = text[assign.end..].strip
      return value.starts_with?("func") ? nil : {at, value}
    end
  end

  # What the last statement binding `name` in the function assigns, unless
  # it is a closure.
  private def binding_of(name : String, statements : Array(NetHttpStatement)) : String?
    binding_before(name, statements, statements.size).try(&.[1])
  end

  # The wrapper calls a closure bound to `name` returns (`withAuth :=
  # func(fn http.HandlerFunc) http.Handler { return a.check(fn) }` ->
  # `a.check`).
  private def closure_returns(name : String, statements : Array(NetHttpStatement), lines : Array(String)) : Array(String)?
    row = statements.find { |stmt| (assign = stmt.text.match(NET_HTTP_ASSIGNMENT)) && assign[1] == name && stmt.text[assign.end..].lstrip.starts_with?("func") }.try(&.row) || return
    heads = [] of String
    depth = 0
    (row...lines.size).each do |idx|
      code = code_only(lines[idx])
      if idx > row && (ret = code.match(RETURN_EXPR))
        heads.concat(wrap_chain(ret[1]))
      end
      depth += code.count('{') - code.count('}')
      break if depth <= 0 && idx > row
    end
    heads
  end

  # The wrapper chains of each use of the mux `receiver` that serves it:
  # handed directly to wrapper calls, then to a `Handle` mounting it on
  # another mux (whose own uses follow), an assignment (the local's uses
  # follow), or anything else (a `return`, `ListenAndServe`), where the chain
  # ends. `h = mw(h)` adds its wrappers to every use of `h`.
  private def mux_chains(receiver : String, statements : Array(NetHttpStatement), seen : Set(String)) : Array(Array(Wrap))
    chains = [] of Array(Wrap)
    return chains if seen.includes?(receiver) || seen.size > 8
    seen = seen.dup << receiver
    rewraps = [] of Wrap
    statements.each_with_index do |stmt, at|
      next if at.zero? || !stmt.text.includes?(receiver)
      text = stmt.text
      assign = text.match(NET_HTTP_ASSIGNMENT)
      conditional = stmt.depth > 1
      each_value_use(text, receiver) do |pos|
        next if assign && pos < assign.end
        mount = nil
        wraps = [] of Wrap
        direct_heads(text, pos).each do |head|
          if m = head.match(MOUNT_HEAD)
            mount = m[1]
            break
          end
          wraps << {head, conditional}
        end
        onward = if mount
                   mount == "http" ? [] of Array(Wrap) : mux_chains(mount, statements, seen)
                 elsif assign && assign[1] == receiver
                   rewraps.concat(wraps)
                   next
                 elsif assign
                   mux_chains(assign[1], statements, seen)
                 else
                   [] of Array(Wrap)
                 end
        onward = [[] of Wrap] if onward.empty?
        onward.each { |chain| chains << wraps + chain }
      end
    end
    chains.map { |chain| rewraps + chain }
  end

  # Each position in `text` where `name` is used as a value: not a field,
  # not a call, not a selector head.
  private def each_value_use(text : String, name : String, &)
    pos = 0
    while found = text.index(name, pos)
      pos = found + name.size
      before = found > 0 ? text[found - 1] : ' '
      next if before.alphanumeric? || before == '_' || before == '.'
      rest = text[pos..].lstrip
      next if (after = text[pos]?) && (after.alphanumeric? || after == '_')
      next if rest.starts_with?('.') || rest.starts_with?('(') || rest.starts_with?(":=")
      yield found
    end
  end

  # The heads of the calls the value at `pos` is handed to directly, inner
  # first: `b` then `a` in `a(x, b(v))`. A call the value is only part of
  # an argument of (`f(v + 1)`), or a closure, ends the chain.
  private def direct_heads(text : String, pos : Int32) : Array(String)
    opens = [] of Int32
    (0...pos).each do |idx|
      case text[idx]
      when '(' then opens << idx
      when ')' then opens.pop?
      end
    end
    heads = [] of String
    first = pos
    last = pos
    while last < text.size && (text[last].alphanumeric? || text[last] == '_')
      last += 1
    end
    opens.reverse_each do |open|
      close = closing_paren(text, open) || break
      head = call_head_before(text, open)
      break if head.empty? || head == "func"
      left = text[open + 1...first].rstrip
      right = text[last...close].lstrip
      break unless (left.empty? || left.ends_with?(',')) && (right.empty? || right.starts_with?(','))
      heads << head
      # The call itself is the value handed outward.
      first = call_start_before(text, open)
      last = close + 1
    end
    heads
  end

  # Where the callee before the `(` at `idx` starts (see `call_head_before`).
  private def call_start_before(text : String, idx : Int32) : Int32
    stop = idx - 1
    while stop >= 0 && text[stop].whitespace?
      stop -= 1
    end
    if stop >= 0 && text[stop] == ')'
      depth = 0
      stop.downto(0) do |back|
        depth += 1 if text[back] == ')'
        depth -= 1 if text[back] == '('
        return call_start_before(text, back) if depth.zero?
      end
      return 0
    end
    start = stop
    while start >= 0 && (text[start].alphanumeric? || text[start] == '_' || text[start] == '.')
      start -= 1
    end
    start + 1
  end

  # The callee before the `(` at `idx`: the selector chain, or for `)(`, the
  # callee of the call that closes there.
  private def call_head_before(text : String, idx : Int32) : String
    stop = idx - 1
    while stop >= 0 && text[stop].whitespace?
      stop -= 1
    end
    if stop >= 0 && text[stop] == ')'
      depth = 0
      stop.downto(0) do |back|
        depth += 1 if text[back] == ')'
        depth -= 1 if text[back] == '('
        return call_head_before(text, back) if depth.zero?
      end
      return ""
    end
    start = stop
    while start >= 0 && (text[start].alphanumeric? || text[start] == '_' || text[start] == '.')
      start -= 1
    end
    text[start + 1..stop]
  end

  # The guard a net/http wrapper `head` earns, judged by its definition for
  # a request to `route_path` with `route_method`. A definition that is not
  # a middleware (a route registrar, a handler factory) earns none; a
  # wrapper whose definition is not found falls back to `guard_by_definition`
  # (a library middleware is read by name).
  private def net_http_guard(head : String, file : String, statements : Array(NetHttpStatement), route_path : String,
                             route_method : String, conditional : Bool) : Tag?
    qualifier, _, name = head.rpartition('.')
    bodies = net_http_bodies(qualifier, name, file, statements)
    if bodies.nil? || bodies.empty?
      tag = guard_by_definition("#{head}(", file, authish_name: true) || return
      return conditional ? Tag.new(tag.name, "#{tag.description} (applied only when a setting can lift it: inside a conditional block)", tag.tagger) : tag
    end
    bodies = bodies.select { |body| middleware_definition?(body) }
    return if bodies.empty?
    lifted = bodies.compact_map { |body| setting_lift(body) }.first?
    note = if lifted
             "; a setting can lift it: it hands the request on unchecked when `#{lifted}`"
           elsif conditional
             "; a setting can lift it: it is applied inside a conditional block"
           else
             ""
           end
    case bodies.max_of { |body| body_verdict(body, nil, route_path: route_path, route_method: route_method) }
    when Guard::Authn
      Tag.new("auth", "Protected by Go middleware #{head} (verified from its body: refuses anonymous callers#{note})", "go_auth")
    when Guard::Authz
      Tag.new("authz", "Protected by Go middleware #{head} (verified from its body: permission check replies 403#{note})", "go_auth")
    end
  end

  # Whether `body` is a middleware: it takes a handler (`next http.Handler`,
  # also in the closure a factory returns) and uses it again, calling it or
  # handing it on (`next.ServeHTTP(w, r)`, `next(w, r)`, `m.serve(w, r,
  # next)`). A route registrar takes a mux; a handler factory takes none.
  private def middleware_definition?(body : Noir::GoCalleeExtractor::FunctionBody) : Bool
    source = Noir::CComments.strip(body.source, quotes: %("'`))
    source.scan(HANDLER_PARAM).any? do |m|
      source.scan(/(?<![\w.])#{Regex.escape(m[1])}(?!\w)/).size >= 2
    end
  end

  # `if <cond> {` then `return next` and `}`.
  HANDS_ON_UNCHECKED = /^\s*if\s+([^{\n]+?)\s*\{[ \t]*(?:\/\/[^\n]*)?\n\s*return\s+(\w+)\s*(?:\/\/[^\n]*)?\n\s*\}/m
  # A parameter typed as a handler: `next http.Handler`, `h http.HandlerFunc`.
  HANDLER_PARAM = /\b(\w+)\s+(?:\w+\.)?Handler(?:Func)?\b/

  # The condition under which a middleware factory returns the handler it
  # wraps unwrapped (`if token == "" { return next }`): a setting the
  # deployment chooses turns the check off. Nil when it never does.
  private def setting_lift(body : Noir::GoCalleeExtractor::FunctionBody) : String?
    source = Noir::CComments.strip(body.source, quotes: %("'`))
    handlers = source.scan(HANDLER_PARAM).map(&.[1]).to_set
    source.scan(HANDS_ON_UNCHECKED) { |m| return m[1].strip if handlers.includes?(m[2]) }
    nil
  end

  # The definitions `qualifier.name` names from `file`: a function of the
  # package or of an imported one, or a method of the type a local of the
  # function is bound to (`mw := newMiddleware(s)`, `a := &Auth{}`). Nil
  # when none is found.
  private def net_http_bodies(qualifier : String, name : String, file : String, statements : Array(NetHttpStatement)) : Array(Noir::GoCalleeExtractor::FunctionBody)?
    dir = File.dirname(file)
    if qualifier.empty?
      @bodies.functions_for(dir)[name]?.try { |body| return [body] }
      # A local bound to a middleware factory's result (`auth :=
      # authMiddleware(cfg.Token)`).
      binding_of(name, statements).try(&.match(BOUND_CALL)).try do |m|
        next if m[1]?
        @bodies.functions_for(dir)[m[2]]?.try { |body| [body] }
      end
    elsif qualifier.includes?('.')
      nil
    elsif file_imports(file).includes?(qualifier)
      (@dirs_by_base[qualifier]? || [] of String).compact_map { |pkg| @bodies.functions_for(pkg)[name]? }
    elsif bound = binding_of(qualifier, statements)
      if m = bound.match(BOUND_TYPE)
        type_dirs = m[1]? ? (@dirs_by_base[m[1]]? || [] of String) : [dir]
        type_dirs.flat_map do |type_dir|
          (@bodies.methods_for(type_dir)[name]? || [] of Noir::GoCalleeExtractor::FunctionBody).select { |body| body.source.match(METHOD_RECEIVER).try(&.[1]) == m[2] }
        end
      elsif m = bound.match(BOUND_CALL)
        methods_on_result(m[1]?, m[2], name, dir)
      end
    end
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
  private def add_middleware_scope(scope : GoRouteGroupScope::Scope, file : String, tag : Tag)
    @middleware_scopes << {
      prefix:     scope[:prefix],
      tag:        tag,
      root_group: scope[:kind] == GoRouteGroupScope::ScopeKind::Group && scope[:prefix] == "/",
      gate:       @current_gate,
      owner:      @current_owner,
      module:     go_module(file),
    }
  end

  # The directory of the `go.mod` nearest above `path`, or the filesystem
  # root when there is none. A program's middleware never reaches another
  # module's routes.
  private def go_module(path : String) : String
    dir = File.dirname(path)
    @modules.put_if_absent(dir) do
      File.exists?(File.join(dir, "go.mod")) || File.dirname(dir) == dir ? dir : go_module(dir)
    end
  end

  GO_MODULE_PATH = /^module\s+(\S+)/m

  # Whether module `a` is module `b` or one of them requires the other (a
  # go.work / `replace` workspace wires routes across modules).
  private def same_program?(a : String, b : String) : Bool
    return true if a == b
    @linked_modules.put_if_absent({a, b}) do
      mod_a = File.read(File.join(a, "go.mod")) rescue ""
      mod_b = File.read(File.join(b, "go.mod")) rescue ""
      path_a = mod_a.match(GO_MODULE_PATH).try(&.[1])
      path_b = mod_b.match(GO_MODULE_PATH).try(&.[1])
      next false if path_a.nil? || path_b.nil? || path_a == path_b
      mod_b.split.includes?(path_a) || mod_a.split.includes?(path_b)
    end
  end

  private def check_middleware_scopes(endpoint : Endpoint) : Tag?
    url = endpoint.url
    # A route chained off a group it builds in place (`g.Group("/user").
    # Use(mw).POST("", h)`) inherits only the middleware of the group it
    # builds on (`g`) and that group's ancestors, whatever its prefix.
    ephemeral = nil

    @middleware_scopes.each do |scope|
      next unless prefix_covers?(scope[:prefix], url)
      next if !endpoint.details.code_paths.empty? && endpoint.details.code_paths.none? { |path_info| same_program?(go_module(path_info.path), scope[:module]) }
      if gate = scope[:gate]
        next unless registered_on?(endpoint, gate)
      elsif owner = scope[:owner]
        if scope[:prefix] != "/" || scope[:root_group]
          ephemeral = ephemeral_head(endpoint) if ephemeral.nil?
          if ephemeral && (head = ephemeral[owner[:file]]?)
            name, line = head
            next unless owner[:rows].includes?(line) && derived_from?(name, owner, line)
          elsif created_before?(endpoint, owner)
            next
          end
        end
        # Echo runs `e.Use` middleware for every route, whenever it was
        # registered; a group's, and gin's, fiber's or Iris', reach only the
        # routes registered after it.
        ordered = !(endpoint.details.technology == "go_echo" && scope[:prefix] == "/" && !scope[:root_group])
        next if other_router?(endpoint, owner, ordered)
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
      derived_from?(lines[line - 1].match(ROUTE_RECEIVER).try(&.[1]), gate, line)
    end
  end

  # Whether the endpoint is registered on a child of the owner's group that
  # was created before the middleware was added (`early :=
  # authed.Group("/early")` above `authed.Use(auth)`): gin copies a group's
  # middleware when the child is created, so the child does not get it.
  private def created_before?(endpoint : Endpoint, owner : Gate) : Bool
    endpoint.details.code_paths.any? do |path_info|
      next false unless path_info.path == owner[:file]
      line = path_info.line || next false
      lines = read_file_lines(owner[:file]) || next false
      next false if line < 1 || line > lines.size
      name = lines[line - 1].match(ROUTE_RECEIVER).try(&.[1]) || next false
      next false if name == owner[:receiver]
      found = owner[:parents][name]?.try &.select { |(_, row)| row < line }.max_by?(&.[1])
      !!found && found[0] == owner[:receiver] && found[1] < owner[:rows].begin
    end
  end

  # Whether one of the endpoint's route lines is provably on a router the
  # owner's middleware does not reach.
  #
  # * In the owner's function: a router built there by a library
  #   constructor (`s := chi.NewRouter()`) and never mounted on the owner,
  #   or one derived from a router the owner is derived from too, but not
  #   from the owner (`ping := r.Group("/api/ping")` next to `v1 :=
  #   r.Group("/api")`; `v1.Use(auth)`); with `ordered`, a route registered
  #   (in gin, a group created) before the `.Use`.
  # * In another function: one the owner's function hands the owner's
  #   router (`register(v1.Group("/x"))`, `r.Mount("/admin", adminRouter())`)
  #   only above the `.Use`, with `ordered`; or, when the owner's function
  #   never does, a router built by a library constructor while the owner
  #   is one too (`r := chi.NewRouter()` in `main` and in `adminRouter`).
  #
  # A router handed in as a parameter, or built some other way, may be the
  # owner's, so it is left to the prefix.
  # ponytail: one hop; a router mounted through a helper of a helper is
  # judged by the call the owner's function makes.
  private def other_router?(endpoint : Endpoint, owner : Gate, ordered : Bool) : Bool
    use_row = owner[:rows].begin
    owner_lines = read_file_lines(owner[:file]) || return false
    # From the row below the registration, so `v1 := r.Group("/api",
    # auth)` is read as derived from `r`.
    owner_chain, owner_local = router_chain(owner[:file], owner_lines, use_row + 1, owner[:receiver])
    endpoint.details.code_paths.any? do |path_info|
      line = path_info.line || next false
      lines = read_file_lines(path_info.path) || next false
      next false if line < 1 || line > lines.size
      name = lines[line - 1].match(ROUTE_RECEIVER).try(&.[1]) || next false
      chain, local = router_chain(path_info.path, lines, line, name)
      if path_info.path == owner[:file] && function_start(lines, line) == function_start(lines, use_row)
        if hop = chain.find { |(router, _)| router == owner[:receiver] }
          # fiber matches middleware in registration order, so only the
          # route's own line counts; gin copies a group's handlers when it
          # is created.
          ordered && (endpoint.details.technology == "go_fiber" ? line : hop[1]) < use_row
        elsif local
          owner_uses(owner, owner_lines, chain.last[0]).empty?
        else
          chain.any? { |(router, _)| owner_chain.any? { |(other, _)| other == router } }
        end
      else
        start = function_start(lines, line)
        helper = start < 0 ? nil : lines[start].match(FUNC_NAME).try(&.[1])
        calls = helper ? owner_uses(owner, owner_lines, helper, File.dirname(path_info.path)) : [] of Int32
        calls.empty? ? local && owner_local : ordered && calls.all? { |row| row < use_row }
      end
    end
  end

  FUNC_NAME = /\Afunc\s*(?:\([^)]*\)\s*)?(\w+)/

  # The 1-based rows of the owner's function that hand the owner's router
  # `target`: a line naming the owner that calls `target(` or mounts
  # `target` (`r.Mount("/s", s)`).
  # A call qualified by an import (`helloworld.RegisterGreeterHTTPServer(`)
  # counts only when that import is `package_dir`, the helper's package: a
  # same-named helper of another package is not the one called.
  private def owner_uses(owner : Gate, owner_lines : Array(String), target : String, package_dir : String? = nil) : Array(Int32)
    @owner_uses.put_if_absent({owner[:file], owner[:rows].begin, owner[:receiver], "#{target} #{package_dir}"}) do
      start = function_start(owner_lines, owner[:rows].begin)
      last = start < 0 ? owner_lines.size : enclosing_block_end(owner_lines, start + 2)
      ((start + 1)...Math.min(last, owner_lines.size)).compact_map do |row|
        code = code_only(owner_lines[row])
        next unless code.includes?(target)
        tokens = code.split(/\W+/)
        next unless tokens.includes?(owner[:receiver])
        at = code.index("#{target}(")
        called = !at.nil? && (at.zero? || !code[at - 1].alphanumeric? && code[at - 1] != '_')
        if called && package_dir && at && (qualifier = code[0, at].match(/(\w+)\s*\.\s*\z/))
          if path = import_paths(owner[:file])[qualifier[1]]?
            # The last segment, or the one before a `/v2` major suffix.
            segments = path.split('/')
            segments.pop if segments.size > 1 && segments.last.matches?(/\Av\d+\z/) && segments.last != File.basename(package_dir)
            called = segments.last == File.basename(package_dir)
          end
        end
        row + 1 if called || (code.includes?("Mount(") && tokens.includes?(target))
      end
    end
  end

  ROUTER_ASSIGNMENT = /\A(?:var\s+)?(\w+)(?:\s+[\w.*\[\]]+)?\s*:?=(?!=)\s*(.+)\z/
  # A router read off another variable: `r.Group("/x")`, `r.PathPrefix("/api").
  # Subrouter()`, `r.With(mw)`, or `r` itself.
  ROUTER_FROM = /\A(\w+)\s*(?:\.|\z)/
  # A library's router constructor: `gin.Default()`, `chi.NewRouter()`,
  # `fiber.New(...)`.
  ROUTER_CONSTRUCTOR = /\A&?\s*(\w+)\s*\.\s*(?:New\w*|Default)\s*\(/
  # A closure handed to a call on a router, taking the router:
  # `r.Route("/x", func(r chi.Router) {`.
  CLOSURE_ROUTER_PARAM = /(\w+)\s*\.\s*\w+\s*\(.*\bfunc\s*\(\s*(\w+)\b/

  # The routers the route `name.VERB(...)` on `line` (1-based) registers
  # through, walking up its function: each with the row it is used or
  # derived on (`ping` on the route's line, then `r` on `ping :=
  # r.Group(...)`), and whether the last was built there by a library
  # constructor rather than handed in.
  private def router_chain(path : String, lines : Array(String), line : Int32, name : String) : {Array({String, Int32}), Bool}
    @router_chains.put_if_absent({path, line, name}) do
      chain = [{name, line}]
      local = false
      depth = 0
      (line - 2).downto(0) do |row|
        code = code_only(lines[row]).strip
        depth += code.count('}') - code.count('{')
        enclosing = depth < 0
        if depth <= 0
          depth = 0
          current = chain.last[0]
          if (m = code.match(ROUTER_ASSIGNMENT)) && m[1] == current
            hop = m[2].match(ROUTER_FROM)
            if hop.nil? || file_imports(path).includes?(hop[1])
              local = local_router?(m[2], path)
              break
            end
            chain << {hop[1], row + 1}
          elsif enclosing && (m = code.match(CLOSURE_ROUTER_PARAM)) && m[2] == current
            chain << {m[1], row + 1}
          end
        end
        break if lines[row].starts_with?("func")
      end
      {chain, local}
    end
  end

  private def local_router?(expr : String, path : String) : Bool
    m = expr.match(ROUTER_CONSTRUCTOR) || return false
    file_imports(path).includes?(m[1]) && !@dirs_by_base.has_key?(m[1])
  end

  # The 0-based row of the `func` that holds line `row` (1-based); -1 at
  # file scope.
  private def function_start(lines : Array(String), row : Int32) : Int32
    (row - 1).downto(0) { |idx| return idx if lines[idx]?.try(&.starts_with?("func")) }
    -1
  end

  # File -> {head variable, 1-based line} of each of the endpoint's route
  # lines that is a chain building its group in place.
  private def ephemeral_head(endpoint : Endpoint) : Hash(String, {String, Int32})
    heads = Hash(String, {String, Int32}).new
    endpoint.details.code_paths.each do |path_info|
      line = path_info.line || next
      lines = read_file_lines(path_info.path) || next
      next if line < 1 || line > lines.size
      ephemeral_group_use(lines[line - 1].strip).try { |head| heads[path_info.path] = {head, line} }
    end
    heads
  end

  # Whether the group `name` used on `line` is the gate's receiver or was
  # derived from it: each hop takes the assignment of the name nearest above
  # the line inside the gate's rows, so a group created before the
  # middleware was added, or a same-named group in another function, is not.
  private def derived_from?(name : String?, gate : Gate, line : Int32) : Bool
    16.times do
      return false unless name
      return true if name == gate[:receiver]
      found = gate[:parents][name]?.try &.select { |(_, row)| row < line && gate[:rows].includes?(row) }.max_by?(&.[1])
      return false unless found
      name, line = found
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
