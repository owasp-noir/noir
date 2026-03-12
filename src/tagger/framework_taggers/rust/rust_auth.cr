require "../../../models/framework_tagger"
require "../../../models/endpoint"

class RustAuthTagger < FrameworkTagger
  # Actix-Web auth middleware/extractor patterns
  ACTIX_AUTH_PATTERNS = [
    /HttpAuthentication/,
    /BearerAuth/,
    /BasicAuth/,
    /Identity/,
  ]

  # Rocket request guard types (in function signatures)
  GUARD_TYPE_PATTERNS = [
    /\b(?:Auth|Authenticated|AuthGuard|AuthUser|AuthToken)\b/,
    /\b(?:ApiKey|ApiToken|BearerToken|AccessToken)\b/,
    /\b(?:Claims|JwtClaims|TokenClaims|JwtToken)\b/,
    /\b(?:AdminUser|AdminGuard|Admin)\b/,
    /\b(?:UserGuard|UserToken|CurrentUser|LoggedInUser)\b/,
    /\b(?:Session|SessionUser|CookieAuth)\b/,
    /\b(?:RoleGuard|Permission|Authorized)\b/,
  ]

  # Axum extractor patterns
  AXUM_EXTRACTOR_PATTERNS = [
    /Extension<.*(?:Auth|Claims|Token|User|Session).*>/,
    /TypedHeader<.*(?:Authorization|Bearer).*>/,
  ]

  # Middleware layer patterns (in Router/App setup)
  MIDDLEWARE_LAYER_PATTERNS = [
    /\.wrap\s*\(\s*(\w*[Aa]uth\w*)/,
    /\.wrap\s*\(\s*HttpAuthentication/,
    /\.layer\s*\(\s*(\w*[Aa]uth\w*)/,
    /\.layer\s*\(\s*middleware::from_fn\s*\(\s*(\w*auth\w*)/i,
  ]

  # Guard/middleware attribute patterns
  GUARD_ATTRIBUTE_PATTERNS = [
    /#\[guard\s*=\s*"(\w+)"\]/,
    /#\[.*guard.*\]/i,
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "rust_auth"
    @middleware_scopes = [] of {prefix: String, description: String}
  end

  def self.target_techs : Array(String)
    [
      "rust_axum", "rust_rocket", "rust_actix_web",
      "rust_loco", "rust_rwf", "rust_tide",
      "rust_warp", "rust_gotham",
    ]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Phase 1: Pre-scan for service/scope-level middleware
    pre_scan_middleware_scopes

    # Phase 2: Check each endpoint
    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end

    endpoints
  end

  private def pre_scan_middleware_scopes
    @middleware_scopes.clear

    files = get_files_by_prefix_and_extension(@base_path, ".rs")
    files.each do |file|
      content = read_file(file)
      next if content.nil?

      scan_scope_middleware(content)
    end
  end

  private def scan_scope_middleware(content : String)
    lines = content.split("\n")
    current_scope : String? = nil

    lines.each_with_index do |line, idx|
      stripped = line.strip

      # Track current scope context
      scope_match = stripped.match(/web::(?:scope|resource)\s*\(\s*"([^"]*)"/)
      if scope_match
        current_scope = scope_match[1]
      end

      # Check if this line has auth middleware
      has_auth = false
      middleware_name = "auth"

      MIDDLEWARE_LAYER_PATTERNS.each do |pattern|
        match = stripped.match(pattern)
        if match
          has_auth = true
          middleware_name = match[1]? || "auth"
          break
        end
      end

      if has_auth
        # Determine scope: check current line, then walk back to find scope
        prefix = find_scope_for_line(lines, idx, current_scope)
        if prefix
          @middleware_scopes << {
            prefix:      prefix,
            description: "Protected by Rust #{middleware_name} middleware on #{prefix}",
          }
        end
        # If no scope found, skip — don't default to "/" (global)
      end

      # Reset scope context on closing parenthesis/brace
      if stripped == ")" || stripped == ");" || stripped == "}"
        current_scope = nil
      end
    end
  end

  private def find_scope_for_line(lines : Array(String), line_idx : Int32, current_scope : String?) : String?
    # Use tracked scope if available
    return current_scope if current_scope

    # Walk backwards to find a scope/route definition
    idx = line_idx - 1
    while idx >= 0 && idx >= line_idx - 10
      prev = lines[idx].strip

      scope_match = prev.match(/web::(?:scope|resource)\s*\(\s*"([^"]*)"/)
      return scope_match[1] if scope_match

      route_match = prev.match(/\.route\s*\(\s*"([^"]*)"/)
      return route_match[1] if route_match

      idx -= 1
    end

    nil
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      lines = content.split("\n")
      line_num = path_info.line
      next if line_num.nil?

      line_idx = line_num - 1 # 0-indexed
      next if line_idx < 0 || line_idx >= lines.size

      # Check for guard attributes above the route
      description = check_guard_attributes(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", description, "rust_auth"))
        return
      end

      # Check function signature for auth guard types/extractors
      description = check_function_signature(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", description, "rust_auth"))
        return
      end

      # Check for actix-web auth extractors in function body
      description = check_actix_extractors(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", description, "rust_auth"))
        return
      end
    end

    # Check scope-level middleware
    description = check_middleware_scopes(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "rust_auth"))
    end
  end

  private def check_guard_attributes(lines : Array(String), route_line_idx : Int32) : String?
    # Walk backwards from route attribute to find guard attributes
    idx = route_line_idx - 1
    while idx >= 0 && idx >= route_line_idx - 5
      current = lines[idx].strip
      break if current.empty? && idx < route_line_idx - 1

      GUARD_ATTRIBUTE_PATTERNS.each do |pattern|
        match = current.match(pattern)
        if match
          guard_name = match[1]? || "guard"
          return "Protected by Rust #[guard] attribute (#{guard_name})"
        end
      end

      idx -= 1
    end

    nil
  end

  private def check_function_signature(lines : Array(String), route_line_idx : Int32) : String?
    # Look at lines after the route attribute for the function signature
    # Route attributes like #[get("/path")] are followed by fn handler(...)
    idx = route_line_idx
    end_idx = [route_line_idx + 5, lines.size - 1].min

    while idx <= end_idx
      current = lines[idx]

      # Check for auth-related types in function parameters
      if current.includes?("fn ") || current.includes?("async fn ")
        # Gather the full function signature (may span multiple lines)
        sig_lines = [current]
        sig_idx = idx + 1
        while sig_idx < lines.size && !current.includes?("{") && !current.includes?("->")
          sig_lines << lines[sig_idx]
          current = lines[sig_idx]
          sig_idx += 1
        end
        signature = sig_lines.join(" ")

        GUARD_TYPE_PATTERNS.each do |pattern|
          if signature.matches?(pattern)
            match = signature.match(pattern)
            guard_type = match ? match[0] : "Auth"
            return "Protected by Rust #{guard_type} request guard"
          end
        end

        AXUM_EXTRACTOR_PATTERNS.each do |pattern|
          if signature.matches?(pattern)
            return "Protected by Rust auth extractor"
          end
        end

        break
      end

      idx += 1
    end

    nil
  end

  private def check_actix_extractors(lines : Array(String), route_line_idx : Int32) : String?
    # Check function signature and body for actix-web auth types
    idx = route_line_idx
    end_idx = [route_line_idx + 3, lines.size - 1].min

    while idx <= end_idx
      current = lines[idx]

      ACTIX_AUTH_PATTERNS.each do |pattern|
        if current.matches?(pattern)
          match = current.match(pattern)
          auth_type = match ? match[0] : "auth"
          return "Protected by Actix-Web #{auth_type}"
        end
      end

      idx += 1
    end

    nil
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
end
