require "../../../models/framework_tagger"
require "../../../models/endpoint"

class AspnetAuthTagger < FrameworkTagger
  # ASP.NET [Authorize] attribute patterns
  AUTHORIZE_PATTERNS = [
    {/\[Authorize\]/, "ASP.NET [Authorize]"},
    {/\[Authorize\s*\(\s*Roles\s*=/, "ASP.NET [Authorize(Roles)]"},
    {/\[Authorize\s*\(\s*Policy\s*=/, "ASP.NET [Authorize(Policy)]"},
    {/\[Authorize\s*\(\s*AuthenticationSchemes\s*=/, "ASP.NET [Authorize(AuthenticationSchemes)]"},
  ]

  # Minimal API fluent auth: `app.MapGet("/x", h).RequireAuthorization();`.
  # This is a chained method call, never a `[...]` attribute, so it can't
  # live in AUTHORIZE_PATTERNS (which is scanned in attribute position).
  MINIMAL_API_REQUIRE_AUTH = /\.RequireAuthorization\s*\(/
  MINIMAL_API_ALLOW_ANON   = /\.AllowAnonymous\s*\(/

  # Public override markers
  ALLOW_ANONYMOUS_PATTERN = /\[AllowAnonymous\]/

  # ASP.NET Core middleware auth in action body
  ACTION_AUTH_PATTERNS = [
    {/User\.Identity\.IsAuthenticated/, "ASP.NET User.Identity.IsAuthenticated"},
    {/User\.IsInRole\s*\(/, "ASP.NET User.IsInRole check"},
    {/HttpContext\.User/, "ASP.NET HttpContext.User check"},
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "aspnet_auth"
  end

  def self.target_techs : Array(String)
    ["cs_aspnet_mvc", "cs_aspnet_core_mvc", "cs_aspnet_core_minimal_api", "cs_carter"]
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
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError.
      next if line_num < 1 || line_num > lines.size
      line_idx = line_num - 1

      # Check for [AllowAnonymous] on this action
      if has_allow_anonymous?(lines, line_idx)
        return
      end

      # Check method-level [Authorize]
      description = check_method_attributes(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "aspnet_auth"))
        return
      end

      # Check Minimal API fluent .RequireAuthorization() on the route statement
      description = check_minimal_api_fluent(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "aspnet_auth"))
        return
      end

      # Check class-level [Authorize] (applies to all actions)
      description = check_class_attributes(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description} (class-level)", "aspnet_auth"))
        return
      end

      # Check action body for auth checks
      description = check_action_body(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "aspnet_auth"))
        return
      end
    end
  end

  private def has_allow_anonymous?(lines : Array(String), method_line : Int32) : Bool
    idx = method_line - 1
    while idx >= 0 && idx >= method_line - 5
      current = lines[idx].strip
      break if current.empty? && idx < method_line - 1
      return true if current.matches?(ALLOW_ANONYMOUS_PATTERN)
      idx -= 1
    end
    false
  end

  private def check_method_attributes(lines : Array(String), method_line : Int32) : String?
    idx = method_line - 1
    while idx >= 0 && idx >= method_line - 8
      current = lines[idx].strip
      break if current.empty? && idx < method_line - 1

      AUTHORIZE_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      idx -= 1
    end

    nil
  end

  # Minimal API registrations chain auth fluently after the Map* call,
  # e.g. `app.MapGet("/x", h).RequireAuthorization();`, possibly split
  # across lines until the `;` terminator. Scan the whole statement, and
  # let a chained `.AllowAnonymous()` opt the route back out.
  private def check_minimal_api_fluent(lines : Array(String), route_line : Int32) : String?
    idx = route_line
    end_idx = [route_line + 6, lines.size - 1].min
    statement = String.build do |sb|
      while idx <= end_idx
        sb << lines[idx] << ' '
        break if lines[idx].includes?(";")
        idx += 1
      end
    end

    return if statement.matches?(MINIMAL_API_ALLOW_ANON)
    return "ASP.NET .RequireAuthorization()" if statement.matches?(MINIMAL_API_REQUIRE_AUTH)

    nil
  end

  private def check_class_attributes(lines : Array(String), method_line : Int32) : String?
    idx = method_line
    while idx >= 0
      current = lines[idx].strip

      if current.includes?("class ") && (current.includes?(":") || current.includes?("{"))
        # Found class definition, check attributes above
        attr_idx = idx - 1
        while attr_idx >= 0 && attr_idx >= idx - 5
          attr = lines[attr_idx].strip
          break if attr.empty? && attr_idx < idx - 1

          AUTHORIZE_PATTERNS.each do |pattern, desc|
            return desc if attr.matches?(pattern)
          end

          attr_idx -= 1
        end
        break
      end

      idx -= 1
    end

    nil
  end

  private def check_action_body(lines : Array(String), method_line : Int32) : String?
    idx = method_line + 1
    end_idx = [method_line + 15, lines.size - 1].min

    while idx <= end_idx
      current = lines[idx].strip

      ACTION_AUTH_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      idx += 1
    end

    nil
  end
end
