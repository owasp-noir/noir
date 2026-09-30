require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "nestjs_auth", name: "NestJS Auth Tagger", desc: "Identifies NestJS authentication patterns (Guards, decorators)", order: 150)]
class NestjsAuthTagger < FrameworkTagger
  # NestJS authentication guards — verify who the caller is.
  GUARD_PATTERNS = [
    {/\@UseGuards\s*\(\s*AuthGuard/, "NestJS @UseGuards(AuthGuard)"},
    {/\@UseGuards\s*\(\s*JwtAuthGuard/, "NestJS @UseGuards(JwtAuthGuard)"},
    {/\@UseGuards\s*\(\s*LocalAuthGuard/, "NestJS @UseGuards(LocalAuthGuard)"},
    {/\@UseGuards\s*\(\s*AuthenticationGuard/, "NestJS @UseGuards(AuthenticationGuard)"},
    {/\@UseGuards\s*\(\s*\w*[Aa]uth\w*Guard/, "NestJS auth guard"},
    {/\@UseGuards\s*\(\s*GqlAuthGuard/, "NestJS GraphQL auth guard"},
  ]

  # NestJS authorization decorators/guards — verify what the caller may do.
  # Distinct from authentication so JwtAuthGuard + @Roles stack as
  # auth_guard + authz_guard rather than collapsing into a single auth tag.
  ROLE_PATTERNS = [
    {/\@UseGuards\s*\(\s*RolesGuard/, "NestJS @UseGuards(RolesGuard)"},
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
    /\@SetMetadata\s*\(\s*['"]isPublic['"]/,
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @class_guards = Hash(String, String).new
  end

  def self.target_techs : Array(String)
    ["js_nestjs", "ts_nestjs"]
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

    false
  end

  private def collect_method_decorators(lines : Array(String), method_line : Int32,
                                        authn_descs : Array(String), authz_descs : Array(String))
    idx = method_line - 1
    while idx >= 0 && idx >= method_line - 8
      current = lines[idx].strip
      break if current.empty? && idx < method_line - 1
      # Stop if we hit another method
      break if current.includes?("async ") && current.includes?("(") && idx < method_line - 1

      ROLE_PATTERNS.each do |pattern, desc|
        authz_descs << desc if current.matches?(pattern) && !authz_descs.includes?(desc)
      end
      GUARD_PATTERNS.each do |pattern, desc|
        authn_descs << desc if current.matches?(pattern) && !authn_descs.includes?(desc)
      end
      AUTH_DECORATORS.each do |pattern, desc|
        authn_descs << desc if current.matches?(pattern) && !authn_descs.includes?(desc)
      end

      idx -= 1
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
