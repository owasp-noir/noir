require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "./group_scope"
require "../../../miniparsers/go_callee_extractor"
require "../../../utils/top_level_split"

@[Noir::TaggerFor(key: "go_auth", name: "Go Auth Tagger", desc: "Identifies Go authentication patterns (middleware, JWT, session)", order: 50)]
class GoAuthTagger < FrameworkTagger
  include GoRouteGroupScope

  # Middleware usage patterns in route groups
  USE_AUTH_MIDDLEWARE_PATTERNS = [
    /\.Use\s*\(\s*(\w*[Aa]uth\w*)/,
    /\.Use\s*\(\s*(\w*JWT\w*)/i,
    /\.Use\s*\(\s*(\w*[Tt]oken\w*)/,
    /\.Use\s*\(\s*(\w*[Pp]ermission\w*)/,
    /\.Use\s*\(\s*(\w*[Ll]ogin\w*)/,
    /\.Use\s*\(\s*(\w*RBAC\w*)/i,
    /\.Use\s*\(\s*(\w*ACL\w*)/i,
  ]

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

  # A name the loose `.Use(` patterns above would accept, applied to the
  # unqualified function name of a middleware argument.
  # `sessions.Sessions(store)` is a session *store*, not a check; a session
  # middleware that rejects is found by reading its body.
  AUTHISH_NAME = /auth|jwt|token|permission|login|rbac|acl/i

  # A middleware body that can refuse the request: a 401/403 status handed to
  # a reply or abort call (`AbortWithStatus(http.StatusUnauthorized)`,
  # `c.JSON(403, ...)`, `http.Error(w, "", 401)`, `WriteHeader(403)`) or a
  # framework sentinel error (`echo.ErrUnauthorized`, `fiber.ErrForbidden`).
  # Matched on `code_only` source, so a 401 in a comment or log string does
  # not count, and `== http.StatusUnauthorized` (a comparison, as in a
  # logging middleware) does not either.
  REJECTS_REQUEST = /[(,]\s*(?:\w+\.)?Status(?:Unauthorized|Forbidden)\b|[(,]\s*40[13]\s*[,)]|\b(?:\w+\.)?Err(?:Unauthorized|Forbidden)\b/

  # An unqualified call inside a middleware body, for the one-hop lookup.
  BODY_CALL = /(?<![\w.])([A-Za-z_]\w*)\s*\(/

  # The group variable a registration line credits: `authV1` for both
  # `authV1.Use(auth)` and `authV1 := apiV1.Group("/", auth)`.
  REGISTRATION_RECEIVER = /\A(\w+)\s*(?::?=\s*\w+\s*\.\s*(?:Group|Party)|\.\s*(?:Use|Pre))\s*\(/

  # The variable a route line registers on: `authV1` for `authV1.POST(...)`.
  ROUTE_RECEIVER = /\A\s*(\w+)\s*\.\s*\w+\s*\(/

  def initialize(options : Hash(String, YAML::Any))
    super
    @middleware_scopes = [] of {prefix: String, middleware: String, description: String, root_group: Bool, gate: {file: String, receiver: String}?}
    @current_gate = nil.as({file: String, receiver: String}?)
    @bodies = Noir::GoCalleeExtractor::LazyPackageBodies.empty
    @dirs_by_base = Hash(String, Array(String)).new
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
    return unless USE_REGISTRATION.matches?(content, options: Noir::TextFile::MATCH_OPTIONS)

    each_group_scoped_line(content) do |stripped, scopes|
      register_auth_scopes(stripped, scopes, file)
    end
  end

  private def register_auth_scopes(stripped : String, scopes : GoRouteGroupScope::Scopes, file : String)
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
    # routes registered on that variable in this file.
    # ponytail: routes such a group hands to a helper in another file
    # (`registerAuth(authV1)`) resolve by name only.
    receiver = stripped.match(REGISTRATION_RECEIVER).try &.[1]
    @current_gate = receiver && scopes.aliases.includes?(receiver) ? {file: file, receiver: receiver} : nil
    dir = File.dirname(file)

    before = @middleware_scopes.size

    # Check for .Use() with auth middleware
    USE_AUTH_MIDDLEWARE_PATTERNS.each do |pattern|
      match = stripped.match(pattern)
      if match
        middleware_name = match[1]
        add_middleware_scope(scope, middleware_name, "Protected by Go middleware #{middleware_name}")
      end
    end

    # Check for JWT library middleware
    JWT_PATTERNS.each do |pattern|
      if stripped.matches?(pattern) && stripped.includes?(".Use")
        jwt_match = stripped.match(pattern)
        jwt_name = jwt_match ? jwt_match[0] : "JWT"
        add_middleware_scope(scope, jwt_name, "Protected by Go JWT middleware (#{jwt_name})")
      end
    end
    return unless before == @middleware_scopes.size

    # No known name on the line: read each middleware argument's definition.
    middleware_args(stripped).each do |arg|
      description = guard_by_definition(arg, dir, authish_name: true)
      add_middleware_scope(scope, arg, description) if description
    end
  end

  # The middleware arguments of a registration line, split at the top level
  # and cut at the paren that closes the call, so a chained `.GET(...)` after
  # `.Use(a, b)` is not read as more middleware.
  private def middleware_args(line : String) : Array(String)
    code = code_only(line)
    start = code.match(MIDDLEWARE_ARGS_START)
    return [] of String unless start
    inner = code[start.end..]
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

  # A tag description for middleware argument `arg` when its definition can
  # reject the request, or (with `authish_name`) when its name says so; nil
  # when it is a closure, unresolvable, or only passes the request on.
  private def guard_by_definition(arg : String, dir : String, authish_name : Bool = false) : String?
    ref = arg.match(MIDDLEWARE_REFERENCE)
    return unless ref
    qualifier = ref[1].gsub(/\s+/, "").rchop('.')
    name = ref[2]
    display = qualifier.empty? ? name : "#{qualifier}.#{name}"
    if rejecting_definition?(qualifier, name, dir)
      "Protected by Go middleware #{display} (verified from its body: replies 401/403)"
    elsif authish_name && name.matches?(AUTHISH_NAME)
      "Protected by Go middleware #{display}"
    end
  end

  # Whether the function `qualifier.name`, resolved from the package in
  # `dir`, replies 401/403 itself or through one unqualified helper it calls.
  # ponytail: same package plus a sibling package directory named like the
  # qualifier, one hop deep; a guard reached through an interface, a third
  # party module or a deeper call chain still resolves by name only.
  private def rejecting_definition?(qualifier : String, name : String, dir : String) : Bool
    bodies = [] of Noir::GoCalleeExtractor::FunctionBody
    if qualifier.empty?
      @bodies.functions_for(dir)[name]?.try { |body| bodies << body }
    else
      @bodies.methods_for(dir)[name]?.try { |list| bodies.concat(list) }
      @dirs_by_base[qualifier]?.try &.each do |pkg|
        @bodies.functions_for(pkg)[name]?.try { |body| bodies << body }
      end
    end
    bodies.any? do |body|
      source = code_only(body.source)
      next true if source.matches?(REJECTS_REQUEST)
      package = @bodies.functions_for(File.dirname(body.file_path))
      source.scan(BODY_CALL).any? do |call|
        (helper = package[call[1]]?) && code_only(helper.source).matches?(REJECTS_REQUEST)
      end
    end
  end

  private def check_endpoint(endpoint : Endpoint)
    # Check route definition for inline middleware
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
        if route_line.matches?(pattern)
          match = route_line.match(pattern)
          middleware_name = match ? match[0] : "auth"
          endpoint.add_tag(Tag.new("auth", "Protected by Go #{middleware_name} middleware", "go_auth"))
          return
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

        USE_AUTH_MIDDLEWARE_PATTERNS.each do |pattern|
          match = above_line.match(pattern)
          if match
            middleware_name = match[1]
            endpoint.add_tag(Tag.new("auth", "Protected by Go #{middleware_name} middleware", "go_auth"))
            return
          end
        end

        JWT_PATTERNS.each do |pattern|
          if above_line.matches?(pattern) && above_line.includes?(".Use")
            endpoint.add_tag(Tag.new("auth", "Protected by Go JWT middleware", "go_auth"))
            return
          end
        end

        check_idx -= 1
      end

      # No known name on the route: read the definition of each middleware
      # argument (everything between the path and the handler).
      middleware_args(lines[line_idx])[0...-1].each do |arg|
        description = guard_by_definition(arg, File.dirname(path_info.path))
        next unless description
        endpoint.add_tag(Tag.new("auth", description, "go_auth"))
        return
      end
    end

    # Phase 3: Check group-level middleware scope
    description = check_middleware_scopes(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "go_auth"))
    end
  end

  # Record a group-level middleware scope. `prefix == "/"` arises two ways:
  # a bare engine-level `.Use(...)` (no enclosing group → truly global, every
  # subsequently registered route is guarded) or an explicit root/empty
  # *group* `g.Group("")` / `g.Group("/")` with a chained `.Use(...)`. Only
  # the latter is a sub-group whose middleware does not reach engine-level
  # static routes, so flag it to scope the coverage refinement below.
  private def add_middleware_scope(scope : GoRouteGroupScope::Scope,
                                   middleware : String, description : String)
    @middleware_scopes << {
      prefix:      scope[:prefix],
      middleware:  middleware,
      description: description,
      root_group:  scope[:kind] == GoRouteGroupScope::ScopeKind::Group && scope[:prefix] == "/",
      gate:        @current_gate,
    }
  end

  private def check_middleware_scopes(endpoint : Endpoint) : String?
    url = endpoint.url

    @middleware_scopes.each do |scope|
      next unless prefix_covers?(scope[:prefix], url)
      if gate = scope[:gate]
        next unless registered_on?(endpoint, gate[:file], gate[:receiver])
      end

      # A `.Use` on an explicit root/empty *group* (`g.Group("")` /
      # `g.Group("/")`) creates a sub-group; in gin it does not reach
      # engine-level static-asset routes (the SPA shell, `/static/*`,
      # favicon, web-app manifest) registered directly on the engine. Those
      # are public, so a broad root-group auth scope must not tag them —
      # the main source of go_auth false positives (e.g. gotify tagging
      # `/`, `/index.html`, `/static/*any`, `/manifest.json` as auth).
      next if scope[:root_group] && static_asset_route?(url)

      return scope[:description]
    end

    nil
  end

  # Whether one of the endpoint's route lines in `file` is a call on
  # `receiver` (`authV1.POST("users/add", ...)`).
  private def registered_on?(endpoint : Endpoint, file : String, receiver : String) : Bool
    endpoint.details.code_paths.any? do |path_info|
      next false unless path_info.path == file
      line = path_info.line
      lines = read_file_lines(file)
      next false if line.nil? || lines.nil? || line < 1 || line > lines.size
      lines[line - 1].match(ROUTE_RECEIVER).try(&.[1]) == receiver
    end
  end
end
