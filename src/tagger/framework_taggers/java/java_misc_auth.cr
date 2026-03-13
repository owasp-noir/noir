require "../../../models/framework_tagger"
require "../../../models/endpoint"

class JavaMiscAuthTagger < FrameworkTagger
  # Vert.x auth patterns
  VERTX_AUTH_PATTERNS = [
    {/AuthHandler/, "Vert.x AuthHandler"},
    {/JWTAuth/, "Vert.x JWTAuth"},
    {/BasicAuthHandler/, "Vert.x BasicAuthHandler"},
    {/OAuth2AuthHandler/, "Vert.x OAuth2AuthHandler"},
    {/RedirectAuthHandler/, "Vert.x RedirectAuthHandler"},
    {/SessionHandler/, "Vert.x SessionHandler"},
    {/routingContext\.user\(\)/, "Vert.x user() check"},
  ]

  # Armeria auth patterns
  ARMERIA_AUTH_PATTERNS = [
    {/AuthService/, "Armeria AuthService decorator"},
    {/\.decorator\s*\(\s*AuthService/, "Armeria AuthService"},
    {/Authorizer/, "Armeria Authorizer"},
    {/BasicToken/, "Armeria BasicToken auth"},
    {/OAuth2Token/, "Armeria OAuth2Token auth"},
  ]

  # JSP/Servlet auth patterns
  JSP_AUTH_PATTERNS = [
    {/request\.getUserPrincipal\s*\(\)/, "Servlet getUserPrincipal"},
    {/request\.isUserInRole\s*\(/, "Servlet isUserInRole"},
    {/request\.getRemoteUser\s*\(\)/, "Servlet getRemoteUser"},
    {/HttpServletRequest.*getSession/, "Servlet session check"},
    {/<security-constraint>/, "web.xml security-constraint"},
    {/<auth-constraint>/, "web.xml auth-constraint"},
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "java_misc_auth"
  end

  def self.target_techs : Array(String)
    ["java_vertx", "java_armeria", "java_jsp"]
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

      # Check route context for auth patterns
      description = check_route_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "java_misc_auth"))
        return
      end

      # Check handler body
      description = check_handler_body(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "java_misc_auth"))
        return
      end
    end
  end

  private def check_route_auth(lines : Array(String), line_idx : Int32) : String?
    start_idx = [line_idx - 10, 0].max

    all_patterns = VERTX_AUTH_PATTERNS + ARMERIA_AUTH_PATTERNS + JSP_AUTH_PATTERNS
    (start_idx..line_idx).each do |idx|
      current = lines[idx]
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
    end

    nil
  end

  private def check_handler_body(lines : Array(String), line_idx : Int32) : String?
    idx = line_idx + 1
    end_idx = [line_idx + 15, lines.size - 1].min

    all_patterns = VERTX_AUTH_PATTERNS + ARMERIA_AUTH_PATTERNS + JSP_AUTH_PATTERNS
    while idx <= end_idx
      current = lines[idx].strip
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
      idx += 1
    end

    nil
  end
end
