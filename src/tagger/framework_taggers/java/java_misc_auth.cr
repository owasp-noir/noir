require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../prefix_scope"

@[Noir::TaggerFor(key: "java_misc_auth", name: "Java Misc Auth Tagger", desc: "Identifies Vert.x/Armeria/JSP authentication patterns", order: 210)]
class JavaMiscAuthTagger < FrameworkTagger
  include PrefixScope

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

  ALL_PATTERNS = VERTX_AUTH_PATTERNS + ARMERIA_AUTH_PATTERNS + JSP_AUTH_PATTERNS

  # A Vert.x route registration, `router.route("/private/*").handler(...)`;
  # group 1 is its path (absent for `router.route()`, which covers every
  # route).
  VERTX_ROUTE = /\b\w+\s*\.\s*(?:route|get|post|put|delete|patch|head|options|trace|connect)\s*\(\s*(?:"([^"]*)"\s*)?\)\s*(?:\.\s*(?:handler|blockingHandler|respond|failureHandler|produces|consumes|order|subRouter)\b|$)/

  def self.target_techs : Array(String)
    ["java_vertx", "java_armeria", "java_jsp"]
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

      # Check route context for auth patterns
      vertx = endpoint.details.technology == "java_vertx"
      description = check_route_auth(lines, line_idx, endpoint.url, vertx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "java_misc_auth"))
        return
      end

      # Check handler body
      description = check_handler_body(lines, line_idx, vertx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "java_misc_auth"))
        return
      end
    end
  end

  # The lines just above the route, plus (for Vert.x) every earlier route
  # registration whose path scopes over this one: `router.route("/private/*")
  # .handler(AuthHandler)` guards the routes under `/private` registered
  # after it, and no other.
  private def check_route_auth(lines : Array(String), line_idx : Int32, url : String, vertx : Bool) : String?
    start_idx = [line_idx - 10, 0].max

    (0..line_idx).each do |idx|
      current = lines[idx]
      next if import_line?(current)
      if vertx && idx < line_idx && (route = current.match(VERTX_ROUTE))
        next unless vertx_route_covers?(route[1]?, url)
      elsif idx < start_idx
        next
      end
      ALL_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
    end

    nil
  end

  private def check_handler_body(lines : Array(String), line_idx : Int32, vertx : Bool) : String?
    idx = line_idx + 1
    end_idx = [line_idx + 15, lines.size - 1].min

    while idx <= end_idx
      current = lines[idx].strip
      # The next route registration starts another route's handlers.
      break if vertx && current.matches?(VERTX_ROUTE)
      ALL_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
      idx += 1
    end

    nil
  end

  private def import_line?(line : String) : Bool
    line.lstrip.starts_with?("import ")
  end

  # Vert.x matches a path ending in `*` as a prefix and any other path
  # exactly.
  private def vertx_route_covers?(path : String?, url : String) : Bool
    return true if path.nil?
    return prefix_covers?(path.rchop('*'), url) if path.ends_with?('*')
    path.rstrip('/') == url.rstrip('/')
  end
end
