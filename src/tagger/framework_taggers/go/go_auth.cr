require "../../../models/framework_tagger"
require "../../../models/endpoint"

class GoAuthTagger < FrameworkTagger
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
  ]

  # Import patterns for auth packages
  AUTH_IMPORT_PATTERNS = [
    /golang-jwt/,
    /dgrijalva\/jwt-go/,
    /go-chi\/jwtauth/,
    /labstack\/echo.*\/middleware/,
    /gin-contrib\/sessions/,
    /gorilla\/sessions/,
    /casbin/,
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "go_auth"
    @middleware_scopes = [] of {prefix: String, middleware: String, description: String}
  end

  def self.target_techs : Array(String)
    [
      "go_echo", "go_gin", "go_chi", "go_fiber",
      "go_beego", "go_mux", "go_fasthttp",
      "go_gozero", "go_goyave",
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

    files = get_files_by_prefix_and_extension(@base_path, ".go")
    files.each do |file|
      content = read_file(file)
      next if content.nil?

      scan_group_middleware(content, file)
    end
  end

  private def scan_group_middleware(content : String, file : String)
    lines = content.split("\n")
    # Track current route group context
    group_stack = [] of String

    lines.each_with_index do |line, _idx|
      stripped = line.strip

      # Track Group/Route prefix definitions
      group_match = stripped.match(/\.(?:Group|Route)\s*\(\s*"([^"]*)"/)
      if group_match
        group_stack << group_match[1]
      end

      # Track closing braces for scope tracking
      if stripped.starts_with?("}") || stripped == "})"
        group_stack.pop? unless group_stack.empty?
      end

      # Check for .Use() with auth middleware
      USE_AUTH_MIDDLEWARE_PATTERNS.each do |pattern|
        match = stripped.match(pattern)
        if match
          middleware_name = match[1]
          prefix = normalize_prefix(group_stack)
          prefix = "/" if prefix.empty?
          @middleware_scopes << {
            prefix:      prefix,
            middleware:  middleware_name,
            description: "Protected by Go middleware #{middleware_name}",
          }
        end
      end

      # Check for JWT library middleware
      JWT_PATTERNS.each do |pattern|
        if stripped.matches?(pattern) && stripped.includes?(".Use")
          prefix = normalize_prefix(group_stack)
          prefix = "/" if prefix.empty?
          jwt_match = stripped.match(pattern)
          jwt_name = jwt_match ? jwt_match[0] : "JWT"
          @middleware_scopes << {
            prefix:      prefix,
            middleware:  jwt_name,
            description: "Protected by Go JWT middleware (#{jwt_name})",
          }
        end
      end
    end
  end

  private def check_endpoint(endpoint : Endpoint)
    # Check route definition for inline middleware
    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      lines = content.split("\n")
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

      # Check lines just above for middleware applied to this specific route
      check_idx = line_idx - 1
      while check_idx >= 0 && check_idx >= line_idx - 5
        above_line = lines[check_idx].strip
        break if above_line.empty?

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

  private def check_middleware_scopes(endpoint : Endpoint) : String?
    url = endpoint.url

    @middleware_scopes.each do |scope|
      if url.starts_with?(scope[:prefix])
        return scope[:description]
      end
    end

    nil
  end

  private def normalize_prefix(segments : Array(String)) : String
    joined = segments.join("")
    # Ensure segments that lack a leading "/" are joined properly
    # e.g., ["api", "v1"] → "/api/v1", ["/api", "/v1"] → "/api/v1"
    parts = joined.split("/").reject(&.empty?)
    parts.empty? ? "/" : "/" + parts.join("/")
  end
end
