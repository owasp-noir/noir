require "../../../models/framework_tagger"
require "../../../models/endpoint"

class HonoAuthTagger < FrameworkTagger
  # Hono official auth middleware
  HONO_AUTH_MIDDLEWARE = [
    {/\bbearerAuth\s*\(/, "Hono bearerAuth middleware"},
    {/\bjwt\s*\(/, "Hono jwt middleware"},
    {/\bbasicAuth\s*\(/, "Hono basicAuth middleware"},
  ]

  # Custom or third-party auth middleware names commonly used with Hono
  CUSTOM_AUTH_NAMES = [
    /\bauthMiddleware\b/i,
    /\bauthGuard\b/i,
    /\brequireAuth\b/i,
    /\bverifyToken\b/i,
    /\bcheckAuth\b/i,
    /\bensureAuth\b/i,
    /\bwithAuth\b/i,
  ]

  # Context user extraction after auth (secondary signal)
  CONTEXT_USER_PATTERNS = [
    /c\.var\.(user|payload|auth|session)/,
    /c\.get\s*\(\s*['"](user|payload|auth|session)/,
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "hono_auth"
    @use_auth_scopes = [] of {prefix: String, description: String}
  end

  def self.target_techs : Array(String)
    ["js_hono"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    pre_scan_use_auth
    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end
    endpoints
  end

  private def pre_scan_use_auth
    @use_auth_scopes.clear

    extensions = [".ts", ".js", ".tsx", ".jsx", ".mjs", ".cjs"]
    extensions.each do |ext|
      files = collect_files_by_extension(ext)
      files.each do |file|
        content = read_file(file)
        next if content.nil?

        lines = content.split("\n")
        lines.each do |line|
          stripped = line.strip

          # Match app.use('/prefix', authMiddleware) or app.use(auth)
          if stripped =~ /(?:app|router|hono)\.use\s*\(\s*['"]([^'"]+)['"]\s*,/
            prefix = $1
            if has_auth_middleware_in_line?(stripped)
              @use_auth_scopes << {prefix: prefix, description: "Protected by Hono app.use() auth on #{prefix}"}
            end
          end

          # app.use('/prefix/*', ...)
          if stripped =~ /(?:app|router|hono)\.use\s*\(\s*['"]([^'"]+\*)['"]\s*,/
            prefix = $1.gsub("*", "")
            if has_auth_middleware_in_line?(stripped)
              @use_auth_scopes << {prefix: prefix, description: "Protected by Hono app.use() auth on #{prefix}"}
            end
          end

          # Global app.use(auth)
          if stripped =~ /(?:app|router|hono)\.use\s*\(\s*(?!['"])/
            if has_auth_middleware_in_line?(stripped)
              @use_auth_scopes << {prefix: "/", description: "Protected by Hono global auth middleware"}
            end
          end
        end
      end
    end
  end

  private def has_auth_middleware_in_line?(line : String) : Bool
    HONO_AUTH_MIDDLEWARE.each do |pattern, _|
      return true if line.matches?(pattern)
    end
    CUSTOM_AUTH_NAMES.each do |pattern|
      return true if line.matches?(pattern)
    end
    false
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      lines = content.split("\n")
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError.
      next if line_num < 1 || line_num > lines.size
      line_idx = line_num - 1

      # Check route definition + small surrounding window for chained middleware
      description = check_route_and_nearby(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "hono_auth"))
        return
      end

      # Check for context user extraction in handler body (secondary)
      description = check_context_user(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by Hono auth (#{description})", "hono_auth"))
        return
      end
    end

    # Check prefix-based use() scopes
    description = check_use_scopes(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "hono_auth"))
    end
  end

  private def check_route_and_nearby(lines : Array(String), line_idx : Int32) : String?
    # Look at the route line and up to 2 lines above (for chained or options object)
    start_idx = [line_idx - 2, 0].max
    (start_idx..line_idx).each do |i|
      current = lines[i]

      HONO_AUTH_MIDDLEWARE.each do |pattern, desc|
        if current.matches?(pattern)
          return desc
        end
      end

      CUSTOM_AUTH_NAMES.each do |pattern|
        if current.matches?(pattern)
          # Try to extract a nice name
          if m = current.match(/\b([a-zA-Z_]*[Aa]uth[a-zA-Z_]*)\b/)
            return "Hono #{m[1]} middleware"
          end
          return "custom Hono auth middleware"
        end
      end
    end
    nil
  end

  private def check_context_user(lines : Array(String), line_idx : Int32) : String?
    end_idx = [line_idx + 8, lines.size - 1].min
    (line_idx..end_idx).each do |i|
      current = lines[i]
      CONTEXT_USER_PATTERNS.each do |pattern|
        if current.matches?(pattern)
          return "context user extraction"
        end
      end
    end
    nil
  end

  private def check_use_scopes(endpoint : Endpoint) : String?
    url = endpoint.url
    @use_auth_scopes.each do |scope|
      prefix = scope[:prefix]
      # Normalize Hono /* prefixes and do proper prefix matching
      normalized = prefix.gsub(/\/\*$/, "/")
      if url.starts_with?(normalized) || url.starts_with?(prefix)
        return scope[:description]
      end
    end
    nil
  end
end
