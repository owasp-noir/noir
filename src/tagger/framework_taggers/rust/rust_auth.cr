require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../prefix_scope"

@[Noir::TaggerFor(key: "rust_auth", name: "Rust Auth Tagger", desc: "Identifies Rust authentication patterns (guards, extractors, middleware)", order: 70)]
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
    # ntex spells actix's `.wrap(...)` as `.middleware(...)`.
    /\.middleware\s*\(\s*(\w*[Aa]uth\w*)/,
    /\.(?:route_)?layer\s*\(\s*(\w*[Aa]uth\w*)/,
    # `from_fn(auth)`, `from_fn_with_state(state.clone(), auth)`
    /\.(?:route_)?layer\s*\(\s*(?:middleware::)?from_fn(?:_with_state)?\s*\(\s*(?:[^,()]*(?:\([^()]*\))?\s*,\s*)?(\w*auth\w*)/i,
  ]

  # An Axum `.layer(...)` / `.route_layer(...)`: it wraps the routes added to
  # the router *before* it in the builder chain, and none added after.
  AXUM_LAYER = /\.(?:route_)?layer\s*\(/

  # What an Axum builder chain mounts: `.route("/p", …)` is that one path,
  # `.nest("/p", …)` everything under it.
  AXUM_MOUNT = /\.(route|nest(?:_service)?)\s*\(\s*"([^"]*)"/

  # Guard/middleware attribute patterns
  GUARD_ATTRIBUTE_PATTERNS = [
    /#\[guard\s*=\s*"(\w+)"\]/,
    /#\[.*guard.*\]/i,
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @middleware_scopes = [] of {prefix: String, exact: Bool, local: Bool, description: String}
  end

  def self.target_techs : Array(String)
    [
      "rust_axum", "rust_rocket", "rust_actix_web",
      "rust_loco", "rust_rwf", "rust_tide",
      "rust_warp", "rust_gotham", "rust_ntex",
    ]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Phase 1: Pre-scan for service/scope-level middleware
    pre_scan_middleware_scopes
    super
  end

  private def pre_scan_middleware_scopes
    @middleware_scopes.clear

    files = collect_files_by_extension(".rs")
    files.each do |file|
      content = read_file(file)
      next if content.nil?

      scan_scope_middleware(content)
    end
  end

  private def scan_scope_middleware(content : String)
    lines = content.split("\n")
    # Stack-based scope tracking for nested Actix-Web scopes
    scope_stack = [] of String

    lines.each_with_index do |line, idx|
      stripped = line.strip

      # Track scope nesting
      scope_match = stripped.match(/web::(?:scope|resource)\s*\(\s*"([^"]*)"/)
      if scope_match
        scope_stack << scope_match[1]
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
        # Determine scope: use stack or walk back to find scope
        current_scope = scope_stack.empty? ? nil : PrefixScope.join_segments(scope_stack)
        layer = stripped.match(AXUM_LAYER) if current_scope.nil?
        if layer
          axum_layered_mounts(lines, idx, layer.begin(0)).each do |kind, path|
            @middleware_scopes << {
              prefix:      path,
              exact:       kind == "route",
              local:       true,
              description: "Protected by Rust #{middleware_name} middleware on #{path}",
            }
          end
        elsif prefix = find_scope_for_line(lines, idx, current_scope)
          @middleware_scopes << {
            prefix:      prefix,
            exact:       false,
            local:       false,
            description: "Protected by Rust #{middleware_name} middleware on #{prefix}",
          }
        end
      end

      # Pop scope on closing parenthesis/brace that ends a scope block
      if stripped == ")" || stripped == ");" || stripped == "})" || stripped == "});"
        scope_stack.pop unless scope_stack.empty?
      end
    end
  end

  # The routes/nests an Axum layer at `layer_at` on line `line_idx` wraps.
  # A layer still inside a `.route("/p", get(h).layer(…))` call wraps that
  # one route; otherwise it wraps every mount earlier in the same builder
  # chain, which ends going up at its `let`/`Router::new()` head or at the
  # previous statement's `;`.
  private def axum_layered_mounts(lines : Array(String), line_idx : Int32, layer_at : Int32) : Array({String, String})
    head = lines[line_idx].strip[0, layer_at]
    mounts = head.scan(AXUM_MOUNT).map { |m| {m[1], m[2]} }
    return mounts.last(1) if head.count('(') > head.count(')')
    return mounts if head.includes?("Router::new") || head.starts_with?("let ")

    idx = line_idx - 1
    # ponytail: line-based chain walk; a `;` inside a multi-line closure
    # handler ends it early (a missed tag, never a false one).
    while idx >= 0 && idx >= line_idx - 200
      prev = lines[idx].strip
      break if prev.ends_with?(';') || prev.starts_with?("fn ") || prev.includes?(" fn ")
      mounts.concat(prev.scan(AXUM_MOUNT).map { |m| {m[1], m[2]} })
      break if prev.includes?("Router::new") || prev.starts_with?("let ")
      idx -= 1
    end
    mounts
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
      lines = read_file_lines(path_info.path)
      next if lines.nil?
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
      # Skip empty lines; stop at non-attribute code boundaries
      if current.empty?
        idx -= 1
        next
      end
      break unless current.starts_with?("#[") || current.starts_with?("//")

      if description = guard_attribute_description(current)
        return description
      end

      idx -= 1
    end

    # Attributes stacked below the route attribute guard it just the same.
    annotation_lines_below(lines, route_line_idx, "#[").each do |below|
      if description = guard_attribute_description(below)
        return description
      end
    end

    nil
  end

  private def guard_attribute_description(line : String) : String?
    GUARD_ATTRIBUTE_PATTERNS.each do |pattern|
      if match = line.match(pattern)
        guard_name = match[1]? || "guard"
        return "Protected by Rust #[guard] attribute (#{guard_name})"
      end
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
      prefix = scope[:prefix]
      covered = scope[:exact] ? url == prefix : PrefixScope.prefix_covers?(prefix, url)
      # An Axum layer names router-local paths; that router may itself be
      # `.nest`ed, so `/users` also covers `/api/users`.
      if !covered && scope[:local] && prefix.starts_with?('/') && prefix.size > 1
        covered = url.ends_with?(prefix) || (!scope[:exact] && url.includes?("#{prefix}/"))
      end
      return scope[:description] if covered
    end

    nil
  end
end
