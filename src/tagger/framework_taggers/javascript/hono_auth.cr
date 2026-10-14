require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "hono_auth", name: "Hono Auth Tagger", desc: "Identifies Hono authentication patterns (bearerAuth, jwt, basicAuth, custom middleware)", order: 250)]
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

  # The start of a route registration: a window around one route stops here
  # so it never reads the neighbouring route's middleware or handler.
  ROUTE_DECLARATION = /\.\s*(?:get|post|put|patch|delete|options|head|all|on|use|route)\s*\(/

  def initialize(options : Hash(String, YAML::Any))
    super
    @use_auth_scopes = [] of {prefix: String, description: String}
  end

  def self.target_techs : Array(String)
    ["js_hono"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    pre_scan_use_auth
    super
  end

  private def pre_scan_use_auth
    @use_auth_scopes.clear

    extensions = [".ts", ".js", ".tsx", ".jsx", ".mjs", ".cjs"]
    extensions.each do |ext|
      files = collect_files_by_extension(ext)
      files.each do |file|
        lines = read_file_lines(file)
        next if lines.nil?
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
      lines = read_file_lines(path_info.path)
      next if lines.nil?
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
    end

    # Check prefix-based use() scopes
    description = check_use_scopes(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "hono_auth"))
      return
    end

    # Check for context user extraction in handler body (secondary)
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      line_num = path_info.line
      next if lines.nil? || line_num.nil? || line_num < 1 || line_num > lines.size
      description = check_context_user(lines, line_num - 1)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by Hono auth (#{description})", "hono_auth"))
        return
      end
    end
  end

  private def check_route_and_nearby(lines : Array(String), line_idx : Int32) : String?
    (statement_start(lines, line_idx)..line_idx).each do |i|
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
    (line_idx..statement_end(lines, line_idx)).each do |i|
      current = lines[i]
      CONTEXT_USER_PATTERNS.each do |pattern|
        if current.matches?(pattern)
          return "context user extraction"
        end
      end
    end
    nil
  end

  # The route line plus up to 2 lines above it that are still open into it
  # (`app.get(` with the path on the next line, an options object) — never a
  # line above a route registration, and never a complete statement above.
  private def statement_start(lines : Array(String), line_idx : Int32) : Int32
    start = line_idx
    return start if lines[line_idx].matches?(ROUTE_DECLARATION)
    {line_idx - 1, line_idx - 2}.each do |i|
      break if i < 0 || open_brackets(lines[i]) <= 0
      start = i
      break if lines[i].matches?(ROUTE_DECLARATION)
    end
    start
  end

  # The last line of the statement opened on `line_idx` (its brackets
  # closed), at most 8 lines on: a one-line route ends on its own line.
  private def statement_end(lines : Array(String), line_idx : Int32) : Int32
    last = {line_idx + 8, lines.size - 1}.min
    depth = 0
    (line_idx..last).each do |i|
      depth += open_brackets(lines[i])
      return i if depth <= 0
    end
    last
  end

  private def open_brackets(line : String) : Int32
    code = code_only(line)
    code.count("({[") - code.count(")}]")
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
