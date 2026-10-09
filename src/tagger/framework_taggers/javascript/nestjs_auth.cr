require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "nestjs_auth", name: "NestJS Auth Tagger", desc: "Identifies NestJS-style decorator auth (Nest guards, tsoa @Security, routing-controllers @Authorized, Ts.ED @Authenticate)", order: 150)]
class NestjsAuthTagger < FrameworkTagger
  # NestJS authentication guards — verify who the caller is.
  GUARD_PATTERNS = [
    {/\@UseGuards\s*\(\s*AuthGuard/, "NestJS @UseGuards(AuthGuard)"},
    {/\@UseGuards\s*\(\s*JwtAuthGuard/, "NestJS @UseGuards(JwtAuthGuard)"},
    {/\@UseGuards\s*\(\s*LocalAuthGuard/, "NestJS @UseGuards(LocalAuthGuard)"},
    {/\@UseGuards\s*\(\s*AuthenticationGuard/, "NestJS @UseGuards(AuthenticationGuard)"},
    {/\@UseGuards\s*\(\s*\w*[Aa]uth\w*Guard/, "NestJS auth guard"},
    {/\@UseGuards\s*\(\s*GqlAuthGuard/, "NestJS GraphQL auth guard"},
    # The other decorator-controller frameworks (tsoa, routing-controllers,
    # Ts.ED) mark authenticated handlers and controllers the same way.
    {/\@Security\s*\(/, "tsoa @Security"},
    {/\@Authorized\s*\(/, "routing-controllers @Authorized"},
    {/\@(?:Authenticate|Authorize|UseAuth)\s*\(/, "Ts.ED @Authenticate"},
  ]

  # NestJS authorization decorators/guards — verify what the caller may do.
  # Distinct from authentication so JwtAuthGuard + @Roles stack as
  # auth_guard + authz_guard rather than collapsing into a single auth tag.
  ROLE_PATTERNS = [
    {/\@UseGuards\s*\([^)]*\bRolesGuard\b/, "NestJS @UseGuards(RolesGuard)"},
    {/\@Roles\s*\(/, "NestJS @Roles decorator"},
    {/\@Permissions\s*\(/, "NestJS @Permissions decorator"},
    {/\@RequirePermissions\s*\(/, "NestJS @RequirePermissions decorator"},
    {/\@SetMetadata\s*\(\s*['"]roles['"]/, "NestJS role metadata"},
  ]

  # NestJS auth-related decorators
  AUTH_DECORATORS = [
    {/\@ApiBearerAuth\s*\(/, "NestJS @ApiBearerAuth (Swagger)"},
    {/\@ApiBasicAuth\s*\(/, "NestJS @ApiBasicAuth (Swagger)"},
    {/\@ApiOAuth2\s*\(/, "NestJS @ApiOAuth2 (Swagger)"},
    {/\@ApiSecurity\s*\(/, "NestJS @ApiSecurity (Swagger)"},
  ]

  # Public/skip auth markers (negative signal)
  PUBLIC_PATTERNS = [
    /\@Public\s*\(\)/,
    /\@SkipAuth\s*\(\)/,
    /\@AllowAnonymous\s*\(\)/,
    /\@NoSecurity\s*\(\)/, # tsoa
    /\@SetMetadata\s*\(\s*['"]isPublic['"]/,
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @class_guards = Hash(String, String).new
  end

  def self.target_techs : Array(String)
    ["js_nestjs", "ts_nestjs", "ts_tsoa", "ts_routing_controllers", "ts_tsed"]
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

      # Check if endpoint is explicitly public
      if public?(lines, line_idx)
        return
      end

      # Collect method- and class-level evidence without short-circuiting.
      # A method @Roles used to return before class @UseGuards(JwtAuthGuard),
      # so authz was stored as auth_guard and class authn was dropped.
      authn_descs = [] of String
      authz_descs = [] of String
      collect_method_decorators(lines, line_idx, authn_descs, authz_descs)
      collect_class_decorators(lines, line_idx, authn_descs, authz_descs)

      # add_tag dedupes by (name, tagger), so authn and authz need distinct
      # names to stack on the same endpoint.
      if authn = authn_descs.first?
        endpoint.add_tag(Tag.new("auth", "Protected by #{authn}", "nestjs_auth"))
      end
      if authz = authz_descs.first?
        endpoint.add_tag(Tag.new("authz", "Protected by #{authz}", "nestjs_auth"))
      end

      return unless authn_descs.empty? && authz_descs.empty?
    end
  end

  private def public?(lines : Array(String), method_line : Int32) : Bool
    idx = method_line - 1
    while idx >= 0 && idx >= method_line - 5
      current = lines[idx].strip
      break if current.empty? && idx < method_line - 1

      PUBLIC_PATTERNS.each do |pattern|
        return true if current.matches?(pattern)
      end

      idx -= 1
    end

    # Decorator order does not matter to Nest: `@Get()` then `@Public()` is
    # as public as the reverse.
    annotation_lines_below(lines, method_line, "@").any? do |below|
      PUBLIC_PATTERNS.any? { |pattern| below.matches?(pattern) }
    end
  end

  private def collect_method_decorators(lines : Array(String), method_line : Int32,
                                        authn_descs : Array(String), authz_descs : Array(String))
    idx = method_line - 1
    while idx >= 0 && idx >= method_line - 8
      current = lines[idx].strip
      break if current.empty? && idx < method_line - 1
      # Stop if we hit another method: its signature, or the closing brace
      # of a non-async one, which the signature test does not catch.
      break if current.includes?("async ") && current.includes?("(") && idx < method_line - 1
      break if current == "}"

      collect_decorator_line(current, authn_descs, authz_descs)

      idx -= 1
    end

    # `@Get()` then `@UseGuards(...)` guards the handler exactly as the
    # reverse order does, and the walk above only sees the latter.
    annotation_lines_below(lines, method_line, "@").each do |below|
      collect_decorator_line(below, authn_descs, authz_descs)
    end
  end

  private def collect_decorator_line(current : String, authn_descs : Array(String), authz_descs : Array(String))
    ROLE_PATTERNS.each do |pattern, desc|
      authz_descs << desc if current.matches?(pattern) && !authz_descs.includes?(desc)
    end
    GUARD_PATTERNS.each do |pattern, desc|
      authn_descs << desc if current.matches?(pattern) && !authn_descs.includes?(desc)
    end
    AUTH_DECORATORS.each do |pattern, desc|
      authn_descs << desc if current.matches?(pattern) && !authn_descs.includes?(desc)
    end
  end

  private def collect_class_decorators(lines : Array(String), method_line : Int32,
                                       authn_descs : Array(String), authz_descs : Array(String))
    # Walk backwards to find the class definition, checking for class-level guards
    idx = method_line
    while idx >= 0
      current = lines[idx].strip

      if current.includes?("class ") && current.includes?("{")
        # Found class — now check decorators above it
        class_idx = idx - 1
        while class_idx >= 0 && class_idx >= idx - 10
          decorator = lines[class_idx].strip
          break if decorator.empty? && class_idx < idx - 1

          ROLE_PATTERNS.each do |pattern, desc|
            labeled = "#{desc} (class-level)"
            authz_descs << labeled if decorator.matches?(pattern) && !authz_descs.includes?(labeled) && !authz_descs.includes?(desc)
          end
          GUARD_PATTERNS.each do |pattern, desc|
            labeled = "#{desc} (class-level)"
            authn_descs << labeled if decorator.matches?(pattern) && !authn_descs.includes?(labeled) && !authn_descs.includes?(desc)
          end

          class_idx -= 1
        end
        break
      end

      idx -= 1
    end
  end
end
