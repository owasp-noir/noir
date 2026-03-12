require "../../../models/framework_tagger"
require "../../../models/endpoint"

class JsMiscAuthTagger < FrameworkTagger
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
    {/\benchureLoggedIn\b/, "ensureLoggedIn middleware"},
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

      # Check route definition line for auth middleware
      description = check_route_line(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "js_misc_auth"))
        return
      end

      # Check nearby context (hooks, before handlers)
      description = check_nearby_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "js_misc_auth"))
        return
      end
    end
  end

  private def check_route_line(lines : Array(String), line_idx : Int32) : String?
    return nil if line_idx < 0 || line_idx >= lines.size

    # Check the route definition line and adjacent lines
    start_idx = [line_idx - 2, 0].max
    end_idx = [line_idx + 3, lines.size - 1].min

    (start_idx..end_idx).each do |idx|
      current = lines[idx]

      all_patterns = FASTIFY_PATTERNS + KOA_PATTERNS + RESTIFY_PATTERNS + GENERIC_NODE_AUTH
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
    end

    nil
  end

  private def check_nearby_auth(lines : Array(String), line_idx : Int32) : String?
    # Walk backwards to find hooks or middleware applied to this route context
    idx = line_idx - 1
    while idx >= 0 && idx >= line_idx - 10
      current = lines[idx].strip
      break if current.empty? && idx < line_idx - 3

      all_patterns = FASTIFY_PATTERNS + KOA_PATTERNS + RESTIFY_PATTERNS
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      idx -= 1
    end

    nil
  end
end
