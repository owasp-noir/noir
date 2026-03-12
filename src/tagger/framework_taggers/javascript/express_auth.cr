require "../../../models/framework_tagger"
require "../../../models/endpoint"

class ExpressAuthTagger < FrameworkTagger
  PASSPORT_PATTERNS = [
    /passport\.authenticate\s*\(/,
  ]

  JWT_MIDDLEWARE_PATTERNS = [
    /expressjwt\s*\(/,
    /expressJwt\s*\(/,
  ]

  AUTH_MIDDLEWARE_NAMES = [
    /\brequireAuth\b/,
    /\bisAuth\b/,
    /\bisAuthenticated\b/,
    /\benchureLoggedIn\b/,
    /\benchureAuthenticated\b/,
    /\bauthorize\b/,
    /\brequireLogin\b/,
    /\bauthMiddleware\b/,
    /\bverifyToken\b/,
    /\bcheckAuth\b/,
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "express_auth"
    @app_use_auth_patterns = [] of {prefix: String, description: String}
  end

  def self.target_techs : Array(String)
    ["js_express"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Pre-scan: Find app.use() level auth middleware
    pre_scan_app_use_auth

    # Check each endpoint
    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end

    endpoints
  end

  private def pre_scan_app_use_auth
    @app_use_auth_patterns.clear

    extensions = [".js", ".ts", ".mjs", ".cjs"]
    extensions.each do |ext|
      files = get_files_by_prefix_and_extension(@base_path, ext)
      files.each do |file|
        content = read_file(file)
        next if content.nil?

        lines = content.split("\n")
        lines.each do |line|
          stripped = line.strip

          # Match app.use('/prefix', authMiddleware)
          match = stripped.match(/(?:app|router)\.use\s*\(\s*['"]([^'"]+)['"]/)
          if match
            prefix = match[1]
            if has_auth_middleware_in_line?(stripped)
              @app_use_auth_patterns << {prefix: prefix, description: "Protected by Express app.use() auth middleware on #{prefix}"}
            end
          end

          # Match app.use(authMiddleware) without prefix (applies to all routes)
          if stripped.matches?(/(?:app|router)\.use\s*\(/) && !match
            if has_auth_middleware_in_line?(stripped)
              @app_use_auth_patterns << {prefix: "/", description: "Protected by Express global auth middleware"}
            end
          end
        end
      end
    end
  end

  private def check_endpoint(endpoint : Endpoint)
    # Check route definition line for auth patterns
    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      lines = content.split("\n")
      line_num = path_info.line
      next if line_num.nil?

      # Check the route definition line and a few lines around it (same statement)
      route_lines = get_route_statement(lines, line_num - 1) # 0-indexed
      route_text = route_lines.join(" ")

      # Check for passport.authenticate in route definition
      PASSPORT_PATTERNS.each do |pattern|
        if route_text.matches?(pattern)
          match = route_text.match(/passport\.authenticate\s*\(\s*['"]([^'"]+)['"]/)
          strategy = match ? match[1] : "unknown"
          endpoint.add_tag(Tag.new("auth", "Protected by Passport.js #{strategy} strategy", "express_auth"))
          return
        end
      end

      # Check for JWT middleware
      JWT_MIDDLEWARE_PATTERNS.each do |pattern|
        if route_text.matches?(pattern)
          endpoint.add_tag(Tag.new("auth", "Protected by Express JWT middleware", "express_auth"))
          return
        end
      end

      # Check for generic auth middleware names in route definition
      AUTH_MIDDLEWARE_NAMES.each do |pattern|
        if route_text.matches?(pattern)
          match = route_text.match(pattern)
          middleware_name = match ? match[0] : "auth"
          endpoint.add_tag(Tag.new("auth", "Protected by Express #{middleware_name} middleware", "express_auth"))
          return
        end
      end
    end

    # Check app.use() level auth for route prefix matching
    description = check_app_use_auth(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "express_auth"))
    end
  end

  # Get lines that make up a route statement (handles multi-line route definitions)
  private def get_route_statement(lines : Array(String), line_idx : Int32) : Array(String)
    return [] of String if line_idx < 0 || line_idx >= lines.size

    result = [lines[line_idx]]

    # Look at preceding lines that might be part of the same statement
    # (e.g., chained method calls)
    i = line_idx - 1
    while i >= 0 && i >= line_idx - 2
      stripped = lines[i].strip
      break if stripped.empty? || stripped.ends_with?(";") || stripped.ends_with?(")")
      # Only include if this looks like part of the route definition
      if stripped.matches?(/\.(get|post|put|patch|delete|all|use)\s*\(/) ||
         stripped.includes?("passport") || stripped.includes?("jwt") ||
         stripped.includes?("Auth") || stripped.includes?("auth")
        result.unshift(lines[i])
      else
        break
      end
      i -= 1
    end

    # Look at following lines that might complete the statement
    i = line_idx + 1
    while i < lines.size && i <= line_idx + 3
      stripped = lines[i].strip
      break if stripped.empty?
      result << lines[i]
      break if stripped.includes?(");") || stripped.ends_with?(")")
      i += 1
    end

    result
  end

  private def check_app_use_auth(endpoint : Endpoint) : String?
    url = endpoint.url

    @app_use_auth_patterns.each do |rule|
      if url.starts_with?(rule[:prefix])
        return rule[:description]
      end
    end

    nil
  end

  private def has_auth_middleware_in_line?(line : String) : Bool
    PASSPORT_PATTERNS.any? { |p| line.matches?(p) } ||
      JWT_MIDDLEWARE_PATTERNS.any? { |p| line.matches?(p) } ||
      AUTH_MIDDLEWARE_NAMES.any? { |p| line.matches?(p) }
  end
end
