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

  # What a global guard does with route metadata, read from its source:
  # the metadata keys it reads through `Reflector`, and the
  # `if (isPublic) return true` / `if (options.public) return true` /
  # `if (!options) return true` branches that let a request through
  # before any authentication runs.
  REFLECTOR_READ = /reflector\s*\.\s*get(?:AllAndOverride|AllAndMerge)?\s*(?:<[^(]*?>)?\s*\(\s*([\w.$'"]+)/
  SKIP_BRANCH    = /if\s*\(\s*(!?)\s*(\w+)\??(?:\.(\w+))?\s*\)\s*\{?\s*return\s+true\b/
  # Authentication starts once the guard touches the request or hands over
  # to Passport; a `return true` after that (`if (!roles) return true`)
  # admits only callers who already logged in.
  AUTH_START = /switchToHttp|getRequest|super\s*\.\s*canActivate|GqlExecutionContext|getArgs/
  # `export const Public = () => SetMetadata(IS_PUBLIC_KEY, true)`, or a
  # decorator that hands its own argument over, as
  # `Authenticated = (options = {}) => applyDecorators(SetMetadata(KEY, options), ...)`.
  SET_METADATA   = /SetMetadata\s*\(\s*([\w.$'"]+)\s*,\s*([^)]*?)\s*\)/
  TOP_LEVEL_DECL = /^(?:export\s+)?(?:const|function)\s+(\w+)\s*(?::[^=(]*)?(?:=\s*(?:async\s*)?)?\(\s*(?:\.\.\.)?(\w*)(?:\s*:[^=,)]*)?(?:\s*=\s*([^,)]+))?/m
  DECORATOR_CALL = /@(\w+)\s*\(([^)]*)\)?/
  FLAG_PAIR      = /(\w+)\s*:\s*([^,}]+)/
  # ponytail: a name heuristic for what the guard hands on to the auth
  # service (`admin`, `permission`, `roles` are checked after login);
  # reading that service is the upgrade.
  AUTHZ_KEY = /admin|role|permission|scope|polic/i

  # A decorator that sets one of the guard's metadata keys: the literal it
  # sets, or nil when it sets its own argument (`default` when called empty).
  record MetadataDecorator, literal : String?, default : String
  # One skip branch of the guard: the property it tests (nil for the whole
  # value) and whether the test is negated.
  record SkipBranch, prop : Regex?, negated : Bool
  record GuardMetadata, skips : Array(SkipBranch), decorators : Hash(String, MetadataDecorator)

  def initialize(options : Hash(String, YAML::Any))
    super
    @global_guards = Hash(String?, String).new
    @guard_metadata = Hash(String?, GuardMetadata).new
    @class_lines = Hash(String, Array(Int32)).new
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    find_global_auth_guards
    super
  end

  # The global auth guard of each app, keyed by its root (nearest
  # `package.json`), read from live, non-test code only.
  private def find_global_auth_guards
    @global_guards.clear
    @guard_metadata.clear
    guard_sources = [] of {String?, String}
    metadata_sources = [] of {String?, String}
    {".ts", ".js"}.each do |ext|
      collect_files_by_extension(ext).each do |path|
        content = read_file(path)
        next unless content
        registers = content.includes?("APP_GUARD") || content.includes?("useGlobalGuards")
        defines_guard = content.includes?("canActivate")
        sets_metadata = content.includes?("SetMetadata")
        next unless registers || defines_guard || sets_metadata
        next if base_relative_path(path).matches?(TEST_PATH)
        root = nearest_project_root(path, PACKAGE_JSON)
        code = Noir::CComments.strip(content, quotes: %("'`))
        guard_sources << {root, code} if defines_guard
        metadata_sources << {root, code} if sets_metadata
        next if !registers || @global_guards.has_key?(root)
        GLOBAL_GUARD_PATTERNS.each do |pattern|
          code.scan(pattern) do |m|
            @global_guards[root] ||= m[1] if m[1].matches?(AUTH_GUARD_NAME)
          end
        end
      end
    end

    @global_guards.each do |root, guard|
      class_decl = /\bclass\s+#{Regex.escape(guard)}\b/
      guard_sources.each do |source_root, code|
        next unless source_root == root && (class_at = code.index(class_decl))
        if metadata = read_guard_metadata(code, class_at, metadata_sources.select { |source| source[0] == root }.map(&.[1]))
          @guard_metadata[root] = metadata
        end
        break
      end
    end
  end

  # What the global guard defined at `class_at` of `code` does with route
  # metadata, and the decorators in `sources` that set the keys it reads.
  # Nil when it reads none or never lets a request through on them.
  private def read_guard_metadata(code : String, class_at : Int32, sources : Array(String)) : GuardMetadata?
    # Keys read anywhere in the file: a helper beside the guard often makes
    # the `Reflector` call (`getAuthenticatedOptions(this.reflector, ...)`).
    keys = code.scan(REFLECTOR_READ).map(&.[1].delete("'\""))
    return if keys.empty?

    body = code[class_at...(code.index(AUTH_START, class_at) || code.size)]
    skips = [] of SkipBranch
    body.scan(SKIP_BRANCH) do |m|
      next unless body.matches?(/\b(?:const|let|var)\s+#{m[2]}\s*=[^;]*reflector/)
      skips << SkipBranch.new(m[3]?.try { |prop| /\b#{prop}\s*:\s*true\b/ }, m[1] == "!")
    end
    return if skips.empty?

    decorators = Hash(String, MetadataDecorator).new
    sources.each do |source|
      decls = source.scan(TOP_LEVEL_DECL)
      source.scan(SET_METADATA) do |m|
        next unless keys.includes?(m[1].delete("'\""))
        next unless decl = decls.reverse_each.find { |d| d.begin < m.begin }
        param = decl[2]
        literal = m[2] == param && !param.empty? ? nil : m[2]
        decorators[decl[1]] ||= MetadataDecorator.new(literal, decl[3]?.try(&.strip) || "")
      end
    end
    GuardMetadata.new(skips, decorators)
  end

  # The decorator, its arguments and the metadata value a route sets
  # through one of the guard's decorators, method level first (it overrides
  # the class), or nil when it sets none.
  private def route_metadata(metadata : GuardMetadata, decorator_lines : Array(String)) : {String, String, String}?
    decorator_lines.each do |line|
      line.scan(DECORATOR_CALL) do |m|
        next unless decorator = metadata.decorators[m[1]]?
        args = m[2].strip
        return {m[1], args, decorator.literal || (args.empty? ? decorator.default : args)}
      end
    end
  end

  # Whether one of the guard's skip branches lets a route whose metadata is
  # `value` (nil: none) through.
  private def admits_anonymous?(metadata : GuardMetadata, value : String?) : Bool
    metadata.skips.any? do |skip|
      set = if value.nil?
              false
            elsif prop = skip.prop
              value.matches?(prop)
            else
              !{"", "false", "null", "undefined", "0"}.includes?(value)
            end
      set != skip.negated
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

      # Collect method- and class-level evidence without short-circuiting.
      # A method @Roles used to return before class @UseGuards(JwtAuthGuard),
      # so authz was stored as auth_guard and class authn was dropped.
      class_decorators = class_decorator_lines(path_info.path, lines, line_idx)
      method_decorators = method_decorator_lines(lines, line_idx)
      authn_descs = [] of String
      authz_descs = [] of String
      method_decorators.each { |line| collect_decorator_line(line, authn_descs, authz_descs) }
      collect_class_decorators(class_decorators, authn_descs, authz_descs)

      root = nearest_project_root(path_info.path, PACKAGE_JSON)
      guard = @global_guards[root]? if authn_descs.empty?
      metadata = @guard_metadata[root]? if guard
      call = metadata.try { |meta| route_metadata(meta, method_decorators + class_decorators) }
      # The global guard returns true on this route's metadata before it
      # authenticates anyone.
      if metadata && authz_descs.empty? && admits_anonymous?(metadata, call.try(&.[2]))
        reason = call ? "@#{call[0]}(#{call[1]})" : "routes without its metadata"
        endpoint.add_tag(Tag.new("anonymous", "NestJS global APP_GUARD (#{guard}) admits anonymous callers on #{reason}", "nestjs_auth"))
        return
      end

      # Check if endpoint (or its whole controller) is explicitly public
      if public?(lines, line_idx) || class_decorators.any? { |line| PUBLIC_PATTERNS.any? { |pattern| line.matches?(pattern) } }
        return
      end

      if guard
        # The metadata the guard still authenticates under: authz keys
        # (`admin`, `permission`) on top of login become an authz guard;
        # any other flag (a `sharedLink` that also takes a share key) is
        # named on the auth guard.
        desc = "NestJS global APP_GUARD (#{guard})"
        if call && !(pairs = call[2].scan(FLAG_PAIR)).empty?
          authz = pairs.select { |pair| pair[1].matches?(AUTHZ_KEY) && pair[2].strip != "false" }
          authz_descs << "NestJS @#{call[0]}({ #{authz.join(", ") { |pair| "#{pair[1]}: #{pair[2].strip}" }} })" unless authz.empty?
          flags = pairs.compact_map { |pair| "#{pair[1]}: true" if pair[2].strip == "true" && !pair[1].matches?(AUTHZ_KEY) }
          desc += " with @#{call[0]}({ #{flags.join(", ")} })" unless flags.empty?
        end
        authn_descs << desc
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

  # The decorator lines of the handler at `method_line`, above and below it.
  private def method_decorator_lines(lines : Array(String), method_line : Int32) : Array(String)
    decorators = [] of String
    idx = method_line - 1
    while idx >= 0 && idx >= method_line - 8
      current = lines[idx].strip
      break if current.empty? && idx < method_line - 1
      # Stop if we hit another method: its signature, or the end of a
      # non-async one, which the signature test does not catch.
      break if current.includes?("async ") && current.includes?("(") && idx < method_line - 1
      break if member_end?(current)

      decorators << current

      idx -= 1
    end

    # `@Get()` then `@UseGuards(...)` guards the handler exactly as the
    # reverse order does, and the walk above only sees the latter.
    decorators.concat(annotation_lines_below(lines, method_line, "@"))
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
  private def class_decorator_lines(path : String, lines : Array(String), method_line : Int32) : Array(String)
    decorators = [] of String
    idx = nearest_match_above(@class_lines, path, lines) { |line| current = line.strip; current.includes?("class ") && current.includes?("{") }[method_line]
    return decorators if idx < 0

    class_idx = idx - 1
    while class_idx >= 0 && class_idx >= idx - 10
      decorator = lines[class_idx].strip
      break if decorator.empty? && class_idx < idx - 1
      decorators << decorator
      class_idx -= 1
    end
    decorators
  end
end
