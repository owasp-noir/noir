require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "./group_scope"

@[Noir::TaggerFor(key: "go_auth", name: "Go Auth Tagger", desc: "Identifies Go authentication patterns (middleware, JWT, session)", order: 50)]
class GoAuthTagger < FrameworkTagger
  include GoRouteGroupScope

  # Middleware usage patterns in route groups
  USE_AUTH_MIDDLEWARE_PATTERNS = [
    /\.Use\s*\(\s*(\w*[Aa]uth\w*)/,
    /\.Use\s*\(\s*(\w*JWT\w*)/i,
    /\.Use\s*\(\s*(\w*[Tt]oken\w*)/,
    /\.Use\s*\(\s*(\w*[Ss]ession\w*)/,
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

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "go_auth"
    @middleware_scopes = [] of {prefix: String, middleware: String, description: String, root_group: Bool}
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

    # Phase 2: Check each endpoint
    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end

    endpoints
  end

  private def pre_scan_middleware_scopes
    @middleware_scopes.clear

    files = collect_files_by_extension(".go")
    files.each do |file|
      content = read_file(file)
      next if content.nil?

      scan_group_middleware(content, file)
    end
  end

  private def scan_group_middleware(content : String, file : String)
    each_group_scoped_line(content) do |stripped, scopes|
      register_auth_scopes(stripped, scopes)
    end
  end

  private def register_auth_scopes(stripped : String, scopes : GoRouteGroupScope::Scopes)
    scope = resolve_use_scope(stripped, scopes)
    return if scope.nil?
    # The middleware guards a route group whose URL prefix we could not read
    # (`r.Group(cfg.APIBase + "/v1")`). Recording it as global would claim
    # every endpoint in the app is protected — including the ones registered on
    # the app's explicitly public groups. Decline instead.
    return if scope[:kind] == GoRouteGroupScope::ScopeKind::Unknown

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

      route_line = lines[line_idx]

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
    }
  end

  private def check_middleware_scopes(endpoint : Endpoint) : String?
    url = endpoint.url

    @middleware_scopes.each do |scope|
      next unless prefix_covers?(scope[:prefix], url)

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
end
