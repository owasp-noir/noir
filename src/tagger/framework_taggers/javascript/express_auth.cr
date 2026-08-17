require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../prefix_scope"

@[Noir::TaggerFor(key: "express_auth", name: "Express Auth Tagger", desc: "Identifies Express.js authentication patterns (Passport, JWT, auth middleware)", order: 40)]
class ExpressAuthTagger < FrameworkTagger
  include PrefixScope

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
    /\bensureLoggedIn\b/,
    /\bensureAuthenticated\b/,
    /\bauthorize\b/,
    /\brequireLogin\b/,
    /\bauthMiddleware\b/,
    /\bverifyToken\b/,
    /\bcheckAuth\b/,
  ]

  # `app.use('/prefix', authMiddleware)` — the guarded path is spelled out, so
  # the rule can be matched against endpoint URLs anywhere in the scan (the
  # routes it guards are usually mounted from another file).
  MOUNTED_USE = /(?:app|router)\.use\s*\(\s*['"]([^'"]+)['"]/

  # `x.use(authMiddleware)` — no path argument. Which routes this guards is a
  # property of the *object* `x`, not of any URL, so the receiver is captured.
  BARE_USE = /\b(\w+)\.use\s*\(/

  # A route registration, and who it was registered on: `app.get('/x', …)`,
  # `router.post(…)`, `app.route('/x')`.
  ROUTE_RECEIVER = /\b(\w+)\s*\.\s*(?:get|post|put|patch|delete|options|head|all|use|route)\s*\(/

  # The start of a route registration, used as a statement boundary so a
  # window around one route never reads the next one's middleware.
  ROUTE_DECLARATION = /\.\s*(?:get|post|put|patch|delete|options|head|all|use|route)\s*\(/

  def initialize(options : Hash(String, YAML::Any))
    super
    @mounted_auth_rules = [] of {prefix: String, description: String}
    @receiver_auth_rules = [] of {file: String, receiver: String, line: Int32, description: String}
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
    @mounted_auth_rules.clear
    @receiver_auth_rules.clear

    extensions = [".js", ".ts", ".mjs", ".cjs"]
    extensions.each do |ext|
      files = collect_files_by_extension(ext)
      files.each do |file|
        lines = read_file_lines(file)
        next if lines.nil?
        expanded = File.expand_path(file)

        lines.each_with_index do |line, idx|
          stripped = line.strip
          next unless stripped.includes?(".use")
          next unless has_auth_middleware_in_line?(stripped)

          if match = stripped.match(MOUNTED_USE)
            prefix = match[1]
            @mounted_auth_rules << {prefix: prefix, description: "Protected by Express app.use() auth middleware on #{prefix}"}
          elsif match = stripped.match(BARE_USE)
            # A path-less `use(auth)` guards the routes registered on THIS
            # object, below THIS line — nothing else. Registering it as a
            # global `prefix: "/"` rule (what this used to do) meant one
            # `router.use(requireAuth)` in `routes/admin.js` reported every
            # endpoint in the project as protected, including `/login`.
            receiver = match[1]
            @receiver_auth_rules << {
              file:        expanded,
              receiver:    receiver,
              line:        idx + 1,
              description: "Protected by Express #{receiver}.use() auth middleware",
            }
          end
        end
      end
    end
  end

  private def check_endpoint(endpoint : Endpoint)
    receiver_description = nil

    # Check route definition line for auth patterns
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
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

      receiver_description ||= check_receiver_use_auth(path_info.path, lines, line_num - 1)
    end

    # Check app.use() level auth: the router this route was registered on
    # first, then a path-scoped mount.
    description = receiver_description || check_mounted_use_auth(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "express_auth"))
    end
  end

  # Get lines that make up a route statement (handles multi-line route definitions)
  private def get_route_statement(lines : Array(String), line_idx : Int32) : Array(String)
    return [] of String if line_idx < 0 || line_idx >= lines.size

    result = [lines[line_idx]]

    # Look at preceding lines that might be part of the same statement
    # (e.g., chained method calls). Skipped when the referenced line already
    # starts a route registration — walking back from there can only reach
    # the *previous* route, whose middleware is not this route's.
    unless lines[line_idx].matches?(ROUTE_DECLARATION)
      i = line_idx - 1
      while i >= 0 && i >= line_idx - 2
        stripped = lines[i].strip
        break if stripped.empty? || stripped.ends_with?(";")
        # Only include if this looks like part of the route definition
        if stripped.matches?(ROUTE_DECLARATION)
          result.unshift(lines[i])
          break
        elsif stripped.includes?("passport") || stripped.includes?("expressjwt")
          result.unshift(lines[i])
        else
          break
        end
        i -= 1
      end
    end

    # Look at following lines that might complete the statement — but only
    # while the statement is actually still open. The route line's own
    # parentheses say whether it is: `app.get('/x', (req, res) => { … });`
    # closes on itself, and reading one line past it attributed the NEXT
    # route's `requireAuth` to this one.
    depth = paren_depth(lines[line_idx])
    i = line_idx + 1
    while depth > 0 && i < lines.size && i <= line_idx + 3
      stripped = lines[i].strip
      break if stripped.empty?
      break if stripped.matches?(ROUTE_DECLARATION)
      result << lines[i]
      depth += paren_depth(lines[i])
      i += 1
    end

    result
  end

  private def paren_depth(line : String) : Int32
    line.count('(') - line.count(')')
  end

  # A path-less `x.use(auth)` guards the routes registered on `x`, in the same
  # file, after that line.
  private def check_receiver_use_auth(path : String, lines : Array(String), line_idx : Int32) : String?
    return if @receiver_auth_rules.empty?
    return if line_idx < 0 || line_idx >= lines.size

    # Which object the route was registered on. Unreadable (a multi-line
    # registration whose receiver sits above the referenced line) means we
    # cannot tell app from sub-router, so decline rather than guess: a false
    # "protected" is the failure that gets an endpoint skipped in review.
    receiver = lines[line_idx].match(ROUTE_RECEIVER).try &.[1]
    return if receiver.nil?

    expanded = File.expand_path(path)
    line_num = line_idx + 1

    @receiver_auth_rules.each do |rule|
      next unless rule[:receiver] == receiver
      next unless rule[:file] == expanded
      next unless rule[:line] < line_num
      return rule[:description]
    end

    nil
  end

  private def check_mounted_use_auth(endpoint : Endpoint) : String?
    url = endpoint.url

    @mounted_auth_rules.each do |rule|
      if prefix_covers?(rule[:prefix], url)
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
