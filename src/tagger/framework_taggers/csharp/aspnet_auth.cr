require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "aspnet_auth", name: "ASP.NET Auth Tagger", desc: "Identifies ASP.NET authentication patterns ([Authorize], policies)", order: 170)]
class AspnetAuthTagger < FrameworkTagger
  # ASP.NET [Authorize] attribute patterns
  AUTHORIZE_PATTERNS = [
    {/\[Authorize\]/, "ASP.NET [Authorize]"},
    {/\[Authorize\s*\(\s*Roles\s*=/, "ASP.NET [Authorize(Roles)]"},
    {/\[Authorize\s*\(\s*Policy\s*=/, "ASP.NET [Authorize(Policy)]"},
    {/\[Authorize\s*\(\s*AuthenticationSchemes\s*=/, "ASP.NET [Authorize(AuthenticationSchemes)]"},
    # `[Authorize("Policy")]`, `[ApiController, Authorize]`, `[Authorize, HttpGet]`
    {/\[(?:[^\]]*,\s*)?Authorize\s*[(,\]]/, "ASP.NET [Authorize]"},
  ]

  # Minimal API fluent auth: `app.MapGet("/x", h).RequireAuthorization();`.
  # This is a chained method call, never a `[...]` attribute, so it can't
  # live in AUTHORIZE_PATTERNS (which is scanned in attribute position).
  MINIMAL_API_REQUIRE_AUTH = /\.RequireAuthorization\s*\(/
  MINIMAL_API_ALLOW_ANON   = /\.AllowAnonymous\s*\(/

  # Public override markers
  ALLOW_ANONYMOUS_PATTERN = /\[(?:[^\]]*,\s*)?AllowAnonymous\s*[(,\]]/

  # App-wide authorization that every endpoint without its own
  # `[AllowAnonymous]` inherits: ASP.NET Core's `FallbackPolicy`, the
  # controller-wide `MapControllers().RequireAuthorization()` / global
  # `AuthorizeFilter`, and MVC 5's `filters.Add(new AuthorizeAttribute())`.
  FALLBACK_POLICY      = /FallbackPolicy\s*=[^;]*RequireAuthenticatedUser\s*\(/
  CONTROLLERS_GLOBAL   = /MapControllers\s*\(\s*\)\s*\.RequireAuthorization\s*\(|Filters\.Add\s*(?:<\s*AuthorizeFilter\s*>|\(\s*new\s+AuthorizeFilter\b)|filters\.Add\s*\(\s*new\s+(?:System\.Web\.Mvc\.)?AuthorizeAttribute\b/
  CONTROLLER_TECHS     = %w[cs_aspnet_mvc cs_aspnet_core_mvc]
  MINIMAL_API_RECEIVER = /^\s*(\w+)\s*\.\s*Map(?:Get|Post|Put|Delete|Patch|Methods|Group)\b/

  # ASP.NET Core middleware auth in action body
  ACTION_AUTH_PATTERNS = [
    {/User\.Identity\.IsAuthenticated/, "ASP.NET User.Identity.IsAuthenticated"},
    {/User\.IsInRole\s*\(/, "ASP.NET User.IsInRole check"},
    {/HttpContext\.User/, "ASP.NET HttpContext.User check"},
  ]

  def self.target_techs : Array(String)
    ["cs_aspnet_mvc", "cs_aspnet_core_mvc", "cs_aspnet_core_minimal_api", "cs_carter", "cs_wolverine"]
  end

  def initialize(options : Hash(String, YAML::Any))
    super
    @fallback_policy = false
    @controllers_global = false
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @fallback_policy = false
    @controllers_global = false
    collect_files_by_extension(".cs").each do |path|
      content = read_file(path)
      next unless content
      @fallback_policy ||= content.includes?("FallbackPolicy") && content.matches?(FALLBACK_POLICY)
      @controllers_global ||= content.includes?("Authorize") && content.matches?(CONTROLLERS_GLOBAL)
    end
    super
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

      # Check for [AllowAnonymous] on this action or its controller:
      # anonymous access wins over any [Authorize] in ASP.NET Core.
      class_attrs = class_attribute_lines(lines, line_idx)
      if has_allow_anonymous?(lines, line_idx) || class_attrs.any?(&.matches?(ALLOW_ANONYMOUS_PATTERN))
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
      return if description == ""
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "aspnet_auth"))
        return
      end

      # Check class-level [Authorize] (applies to all actions)
      class_attrs.each do |attr|
        description ||= AUTHORIZE_PATTERNS.find { |pattern, _| attr.matches?(pattern) }.try(&.[1])
      end
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description} (class-level)", "aspnet_auth"))
        return
      end

      if @fallback_policy
        endpoint.add_tag(Tag.new("auth", "Protected by ASP.NET FallbackPolicy (RequireAuthenticatedUser)", "aspnet_auth"))
        return
      end
      if @controllers_global && CONTROLLER_TECHS.includes?(endpoint.details.technology)
        endpoint.add_tag(Tag.new("auth", "Protected by ASP.NET global authorization for controllers", "aspnet_auth"))
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
  # let a chained `.AllowAnonymous()` opt the route back out — returned as
  # "" so no app-wide policy re-tags it. A route mapped on a group variable
  # inherits the group's `.RequireAuthorization()` (`var api =
  # app.MapGroup("/api").RequireAuthorization(); api.MapGet(...)`).
  private def check_minimal_api_fluent(lines : Array(String), route_line : Int32, depth : Int32 = 0) : String?
    statement = statement_at(lines, route_line)

    return "" if statement.matches?(MINIMAL_API_ALLOW_ANON)
    return "ASP.NET .RequireAuthorization()" if statement.matches?(MINIMAL_API_REQUIRE_AUTH)
    return if depth >= 5

    receiver = statement.match(MINIMAL_API_RECEIVER).try(&.[1])
    return unless receiver && receiver != "app"
    declaration = /\b#{Regex.escape(receiver)}\s*=\s*[\w.]*MapGroup\s*\(/
    (0...route_line).reverse_each do |idx|
      next unless lines[idx].matches?(declaration)
      return check_minimal_api_fluent(lines, idx, depth + 1)
    end
    nil
  end

  private def statement_at(lines : Array(String), line_idx : Int32) : String
    idx = line_idx
    end_idx = [line_idx + 6, lines.size - 1].min
    String.build do |sb|
      while idx <= end_idx
        sb << lines[idx] << ' '
        break if lines[idx].includes?(";")
        idx += 1
      end
    end
  end

  # The attribute lines above the class enclosing `method_line`.
  private def class_attribute_lines(lines : Array(String), method_line : Int32) : Array(String)
    attrs = [] of String
    idx = method_line
    while idx >= 0
      current = lines[idx].strip

      if current.includes?("class ") && (current.includes?(":") || current.includes?("{"))
        attr_idx = idx - 1
        while attr_idx >= 0 && attr_idx >= idx - 5
          attr = lines[attr_idx].strip
          break if attr.empty? && attr_idx < idx - 1
          attrs << attr
          attr_idx -= 1
        end
        break
      end

      idx -= 1
    end
    attrs
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
