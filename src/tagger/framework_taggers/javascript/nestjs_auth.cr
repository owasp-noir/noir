require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../utils/c_comments"

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
    # The other decorator-controller frameworks mark authenticated handlers
    # and controllers the same way: tsoa `@Security`, routing-controllers
    # `@Authorized`, Ts.ED `@Authenticate` / `@UseAuth`.
    {/\@Security\s*\(/, "@Security decorator"},
    {/\@Authorized\s*\(/, "@Authorized decorator"},
    {/\@(?:Authenticate|UseAuth)\s*\(/, "@Authenticate decorator"},
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

  # A guard registered for every route: `{ provide: APP_GUARD, useClass:
  # JwtAuthGuard }` in a module, or `app.useGlobalGuards(new JwtAuthGuard())`.
  # The Nest docs' authentication recipe does exactly this and opts routes
  # out with `@Public()`.
  GLOBAL_GUARD_PATTERNS = [
    /provide:\s*APP_GUARD\s*,\s*use(?:Class|Existing):\s*(\w+)/,
    /use(?:Class|Existing):\s*(\w+)\s*,\s*provide:\s*APP_GUARD/,
    /useGlobalGuards\s*\(\s*new\s+(\w+)/,
  ]
  # Global guards are as often throttling or role checks; only a guard
  # named for authentication counts.
  AUTH_GUARD_NAME = /Auth|Jwt|JWT|Session|AccessToken/
  PACKAGE_JSON    = /\Apackage\.json\z/
  # Test harnesses (`test/app.e2e-spec.ts`, `*.spec.ts`) bootstrap the app
  # with their own guards, which must not leak onto real routes.
  TEST_PATH = %r{/(?:tests?|__tests__|e2e)/|[.-](?:spec|test)\.[cm]?[jt]sx?\z}

  def initialize(options : Hash(String, YAML::Any))
    super
    @global_guards = Hash(String?, String).new
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    find_global_auth_guards
    super
  end

  # The global auth guard of each app, keyed by its root (nearest
  # `package.json`), read from live, non-test code only.
  private def find_global_auth_guards
    @global_guards.clear
    {".ts", ".js"}.each do |ext|
      collect_files_by_extension(ext).each do |path|
        content = read_file(path)
        next unless content && (content.includes?("APP_GUARD") || content.includes?("useGlobalGuards"))
        next if base_relative_path(path).matches?(TEST_PATH)
        root = nearest_project_root(path, PACKAGE_JSON)
        next if @global_guards.has_key?(root)
        code = Noir::CComments.strip(content, quotes: %("'`))
        GLOBAL_GUARD_PATTERNS.each do |pattern|
          code.scan(pattern) do |m|
            @global_guards[root] ||= m[1] if m[1].matches?(AUTH_GUARD_NAME)
          end
        end
      end
    end
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

      # Check if endpoint (or its whole controller) is explicitly public
      class_decorators = class_decorator_lines(lines, line_idx)
      if public?(lines, line_idx) || class_decorators.any? { |line| PUBLIC_PATTERNS.any? { |pattern| line.matches?(pattern) } }
        return
      end

      # Collect method- and class-level evidence without short-circuiting.
      # A method @Roles used to return before class @UseGuards(JwtAuthGuard),
      # so authz was stored as auth_guard and class authn was dropped.
      authn_descs = [] of String
      authz_descs = [] of String
      collect_method_decorators(lines, line_idx, authn_descs, authz_descs)
      collect_class_decorators(class_decorators, authn_descs, authz_descs)
      if authn_descs.empty? && (guard = @global_guards[nearest_project_root(path_info.path, PACKAGE_JSON)]?)
        authn_descs << "NestJS global APP_GUARD (#{guard})"
      end

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
      break if member_end?(current)

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
      # Stop if we hit another method: its signature, or the end of a
      # non-async one, which the signature test does not catch.
      break if current.includes?("async ") && current.includes?("(") && idx < method_line - 1
      break if member_end?(current)

      collect_decorator_line(current, authn_descs, authz_descs)

      idx -= 1
    end

    # `@Get()` then `@UseGuards(...)` guards the handler exactly as the
    # reverse order does, and the walk above only sees the latter.
    annotation_lines_below(lines, method_line, "@").each do |below|
      collect_decorator_line(below, authn_descs, authz_descs)
    end
  end

  # The end of the previous member: a lone `}` or a one-line body such as
  # `public c() {}`. A multi-line decorator's object lines (`schema: {
  # type: 'object' }`) and callback statements (`cb(null, true);`) are
  # neither.
  ONE_LINE_BODY = /\)\s*(?::[^{}]*)?\{.*\}\z/

  private def member_end?(line : String) : Bool
    return false if line.starts_with?('@')
    line == "}" || line.matches?(ONE_LINE_BODY)
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

  private def collect_class_decorators(decorators : Array(String), authn_descs : Array(String), authz_descs : Array(String))
    decorators.each do |decorator|
      ROLE_PATTERNS.each do |pattern, desc|
        labeled = "#{desc} (class-level)"
        authz_descs << labeled if decorator.matches?(pattern) && !authz_descs.includes?(labeled) && !authz_descs.includes?(desc)
      end
      GUARD_PATTERNS.each do |pattern, desc|
        labeled = "#{desc} (class-level)"
        authn_descs << labeled if decorator.matches?(pattern) && !authn_descs.includes?(labeled) && !authn_descs.includes?(desc)
      end
    end
  end

  # The decorator lines above the class enclosing `method_line`.
  private def class_decorator_lines(lines : Array(String), method_line : Int32) : Array(String)
    decorators = [] of String
    idx = method_line
    while idx >= 0
      current = lines[idx].strip

      if current.includes?("class ") && current.includes?("{")
        class_idx = idx - 1
        while class_idx >= 0 && class_idx >= idx - 10
          decorator = lines[class_idx].strip
          break if decorator.empty? && class_idx < idx - 1
          decorators << decorator
          class_idx -= 1
        end
        break
      end

      idx -= 1
    end
    decorators
  end
end
