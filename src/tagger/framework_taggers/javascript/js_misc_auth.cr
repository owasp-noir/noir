require "../../../models/framework_tagger"
require "../../../models/endpoint"

class JsMiscAuthTagger < FrameworkTagger
  MAX_ROUTE_SCOPE_LINES = 12

  # Fastify auth patterns
  FASTIFY_PATTERNS = [
    {/onRequest.*authenticate/, "Fastify onRequest authenticate hook"},
    {/preHandler.*authenticate/, "Fastify preHandler authenticate"},
    {/fastify\.authenticate/, "Fastify authenticate decorator"},
    {/preValidation.*auth/i, "Fastify preValidation auth"},
    {/@fastify\/jwt/, "Fastify JWT plugin"},
    {/fastify-auth/, "Fastify auth plugin"},
    {/fastify\.auth\s*\(/, "Fastify auth"},
  ]

  # Koa auth patterns
  KOA_PATTERNS = [
    {/koa-passport/, "Koa Passport middleware"},
    {/koa-jwt/, "Koa JWT middleware"},
    {/koa-session/, "Koa session middleware"},
    {/passport\.authenticate\s*\(/, "Koa Passport authenticate"},
    {/ctx\.state\.user/, "Koa ctx.state.user check"},
    {/ctx\.isAuthenticated\s*\(\)/, "Koa isAuthenticated check"},
  ]

  # Restify auth patterns
  RESTIFY_PATTERNS = [
    {/authorizationParser/, "Restify authorizationParser"},
    {/req\.authorization/, "Restify req.authorization check"},
    {/req\.username/, "Restify req.username check"},
  ]

  # Generic Node.js auth middleware (shared across frameworks)
  GENERIC_NODE_AUTH = [
    {/\brequireAuth\b/, "requireAuth middleware"},
    {/\bisAuthenticated\b/, "isAuthenticated middleware"},
    {/\bensureLoggedIn\b/, "ensureLoggedIn middleware"},
    {/\bverifyToken\b/, "verifyToken middleware"},
    {/\bcheckAuth\b/, "checkAuth middleware"},
    {/\bauthMiddleware\b/, "authMiddleware"},
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "js_misc_auth"
  end

  def self.target_techs : Array(String)
    ["js_fastify", "js_koa", "js_restify", "js_nuxtjs"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end
    endpoints
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      lines = content.split("\n")
      line_num = path_info.line
      next if line_num.nil?
      line_idx = line_num - 1

      # Check the route statement/block itself so nearby auth hooks from
      # previous routes do not bleed into public handlers.
      description = check_route_scope(route_scope(lines, line_idx))
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "js_misc_auth"))
        return
      end
    end
  end

  private def check_route_scope(scope : Array(String)) : String?
    all_patterns = FASTIFY_PATTERNS + KOA_PATTERNS + RESTIFY_PATTERNS + GENERIC_NODE_AUTH
    scope.each do |current|
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
    end
    nil
  end

  private def route_scope(lines : Array(String), line_idx : Int32) : Array(String)
    return [] of String if line_idx < 0 || line_idx >= lines.size

    selected = [] of String
    brace_depth = 0
    paren_balance = 0
    seen_block = false

    line_idx.upto(Math.min(line_idx + MAX_ROUTE_SCOPE_LINES - 1, lines.size - 1)) do |idx|
      raw_line = lines[idx]
      selected << raw_line

      sanitized = raw_line.gsub(/(['"]).*?\1/, "\"\"")
      opens = sanitized.count('{')
      closes = sanitized.count('}')
      brace_depth += opens - closes
      paren_balance += sanitized.count('(') - sanitized.count(')')
      seen_block ||= opens > 0

      if seen_block
        break if brace_depth <= 0
      else
        stripped = sanitized.strip
        statement_done = stripped.ends_with?(";") || stripped.ends_with?(")")
        break if statement_done && paren_balance <= 0
      end
    end

    selected
  end
end
