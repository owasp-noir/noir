require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../utils/c_comments"
require "../../../minilexers/csharp_lexer"

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
  FALLBACK_POLICY    = /FallbackPolicy\s*=[^;]*RequireAuthenticatedUser\s*\(/
  CONTROLLERS_GLOBAL = /MapControllers\s*\(\s*\)\s*\.RequireAuthorization\s*\(|Filters\.Add\s*(?:<\s*AuthorizeFilter\s*>|\(\s*new\s+AuthorizeFilter\b)|filters\.Add\s*\(\s*new\s+(?:System\.Web\.Mvc\.)?AuthorizeAttribute\b/
  CONTROLLER_TECHS   = %w[cs_aspnet_mvc cs_aspnet_core_mvc]
  CSPROJ             = /\.csproj\z/
  # Test hosts (`WebApplicationFactory`, a `Foo.Tests` project's Startup)
  # configure their own auth, which must not leak onto the app. The
  # conventions of `Analyzer::CSharp::Common.csharp_test_path?`, plus the
  # `*.Tests` project directory.
  TEST_PATH            = %r{/(?:[Tt]ests?|testassets|[^/]+\.\w*Tests?)/|Tests?\.cs\z}
  MINIMAL_API_RECEIVER = /^\s*(\w+)\s*\.\s*Map(?:Get|Post|Put|Delete|Patch|Methods|Group)\b/
  # `var v1 = api.MapGroup("/v1")`: a nested group, which inherits `api`'s.
  GROUP_DECLARATION_RECEIVER = /=\s*(\w+)\s*\.\s*MapGroup\b/

  # A route-builder extension method, `static RouteGroupBuilder
  # MapOrdersApi(this IEndpointRouteBuilder app)`: its name and the name of
  # its `this` builder.
  ROUTE_BUILDER_EXTENSION = /\bstatic\s[^;{}()=]*?\b(\w+)\s*(?:<[^<>()]*>\s*)?\(\s*this\s+(?:RouteGroupBuilder|IEndpointRouteBuilder|WebApplication)\s+(\w+)/

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
    @fallback_roots = Set(String?).new
    @controllers_global_roots = Set(String?).new
    @class_lines = Hash(String, Array(Int32)).new
    @extension_auth = Hash(String, Tuple(Bool, Bool)).new
  end

  # Collects the project roots (nearest `.csproj`) whose live, non-test
  # code turns on app-wide authorization.
  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @fallback_roots.clear
    @controllers_global_roots.clear
    collect_files_by_extension(".cs").each do |path|
      content = read_file(path)
      next unless content
      fallback = content.includes?("FallbackPolicy") && content.matches?(FALLBACK_POLICY)
      controllers = content.includes?("Authorize") && content.matches?(CONTROLLERS_GLOBAL)
      next unless fallback || controllers
      next if base_relative_path(path).matches?(TEST_PATH)
      code = Noir::CComments.strip(content)
      next if code.includes?("WebApplicationFactory")
      root = nearest_project_root(path, CSPROJ)
      @fallback_roots << root if fallback && code.matches?(FALLBACK_POLICY)
      @controllers_global_roots << root if controllers && code.matches?(CONTROLLERS_GLOBAL)
    end
    collect_extension_auth
    super
  end

  # For every route-builder extension method, whether all of its call sites
  # authorize `{the builder it returns, its this-builder}`:
  #
  #   orders.MapOrdersApi().RequireAuthorization();          # returned builder
  #   app.MapGroup("/x").RequireAuthorization().MapTodos();  # both
  #
  # A convention on a group applies to every group made from it, so a
  # `.RequireAuthorization()` ahead of the call covers everything the
  # extension maps; one after it covers only the builder it returns.
  private def collect_extension_auth
    @extension_auth.clear
    sources = [] of Tuple(String, String)
    names = Set(String).new
    collect_files_by_extension(".cs").each do |path|
      content = read_file(path)
      next unless content && content.includes?("Map")
      next if base_relative_path(path).matches?(TEST_PATH)
      code = Noir::CComments.strip(content)
      sources << {path, code}
      code.scan(ROUTE_BUILDER_EXTENSION) { |m| names << m[1] }
    end
    return if names.empty?

    sites = Hash(String, Array(Tuple(Bool, Bool))).new
    call_re = /\.\s*(#{names.map { |n| Regex.escape(n) }.join('|')})\s*\(/
    sources.each do |_, code|
      next unless code.matches?(call_re)
      statements = code.split(/[;{}]/)
      statements.each do |statement|
        statement.scan(call_re) do |m|
          before = statement[0...m.begin]
          after = statement[m.end..]
          next if after.matches?(MINIMAL_API_ALLOW_ANON)
          before_auth = before.matches?(MINIMAL_API_REQUIRE_AUTH)
          if !before_auth && (receiver = before.match(/\A\s*(\w+)\s*\z/))
            declaration = /\b#{Regex.escape(receiver[1])}\s*=[^=]/
            before_auth = statements.any? { |s| s.matches?(declaration) && s.matches?(MINIMAL_API_REQUIRE_AUTH) && !s.matches?(MINIMAL_API_ALLOW_ANON) }
          end
          (sites[m[1]] ||= [] of Tuple(Bool, Bool)) << {before_auth || after.matches?(MINIMAL_API_REQUIRE_AUTH), before_auth}
        end
      end
    end
    sites.each do |name, calls|
      @extension_auth[name] = {calls.all?(&.[0]), calls.all?(&.[1])}
    end
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
      class_attrs = class_attribute_lines(path_info.path, lines, line_idx)
      # `[Authorize]`/`[AllowAnonymous]` are inherited: a controller takes
      # them from its base classes too.
      chain = class_chain(path_info.path, lines, line_idx)
      if has_allow_anonymous?(lines, line_idx) || class_attrs.any?(&.matches?(ALLOW_ANONYMOUS_PATTERN)) ||
         chain.any? { |decl| decl.attributes.matches?(ALLOW_ANONYMOUS_PATTERN) }
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
      chain.each_with_index do |decl, level|
        description ||= AUTHORIZE_PATTERNS.find { |pattern, _| decl.attributes.matches?(pattern) }.try(&.[1])
        if description
          endpoint.add_tag(Tag.new("auth", "Protected by #{description} (#{level == 0 ? "class-level" : "inherited from #{decl.name}"})", "aspnet_auth"))
          return
        end
      end

      # A filter attribute the scan declares, judged by its definition.
      # One that configuration can open (`authz`) leaves the harder checks
      # below to be read too.
      if tag = filter_attribute_guard(lines, line_idx, chain)
        endpoint.add_tag(tag)
        return unless tag.name == "authz"
      end

      root = nearest_project_root(path_info.path, CSPROJ)
      if @fallback_roots.includes?(root)
        endpoint.add_tag(Tag.new("auth", "Protected by ASP.NET FallbackPolicy (RequireAuthenticatedUser)", "aspnet_auth"))
        return
      end
      if @controllers_global_roots.includes?(root) && CONTROLLER_TECHS.includes?(endpoint.details.technology)
        endpoint.add_tag(Tag.new("auth", "Protected by ASP.NET global authorization for controllers", "aspnet_auth"))
        return
      end

      # Check action body for auth checks
      description = check_action_body(lines, line_idx) || action_refusal(path_info.path, lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "aspnet_auth"))
        return
      end
    end
  end

  # ---- inherited attributes and custom filters ---------------------------

  # A class declaration the scan holds: its attribute list (comments
  # stripped) and its base class.
  record ClassDecl, name : String, attributes : String, base : String?

  CLASS_DECL_NAME_RE = /\bclass\s+([A-Z]\w*)/
  CLASS_MODIFIERS    = /(?:(?:public|internal|private|protected|abstract|sealed|static|partial|new)\s+)*/
  DECL_BASE_RE       = /\A\s*(?:<[^{};]*?>)?\s*(?:\([^)]*\))?\s*:\s*(?:global::)?(?:\w+\.)*(\w+)/
  # One `[Name(args)]` entry of an attribute list.
  ATTRIBUTE_ENTRY_RE = /(?:\[|,)\s*(?:global::)?(?:\w+\.)*(\w+)\s*(?:\(((?:[^()]|\([^()]*\))*)\))?\s*(?=[\],])/
  # An MVC filter refusing the request: an authentication challenge, a
  # forbid, or a 401/403 status.
  FILTER_REFUSAL_RE = /\b\w+\.Result\s*=\s*new\s+(?:ChallengeResult|ForbidResult|UnauthorizedResult|UnauthorizedObjectResult)\b|\b\w+\.Result\s*=\s*new\s+StatusCodeResult\s*\(\s*(?:40[13]\b|StatusCodes\.Status40[13]|\(int\)\s*HttpStatusCode\.(?:Unauthorized|Forbidden))/
  # A permission lookup on an injected service: which roles hold the
  # permission is data, so configuration decides who gets through.
  PERMISSION_CHECK_RE = /\b_\w+\s*\.\s*(\w*(?:Authorize|Permission|Access)\w*)\s*\(([^()]*)\)/
  TYPEOF_RE           = /\btypeof\s*\(\s*(\w+)\s*\)/

  @class_files : Hash(String, Array(String))? = nil
  @class_decls = Hash(String, Array(ClassDecl)).new
  @class_bodies = Hash(String, String?).new
  @filter_guards = Hash(String, Tuple(String, Bool)?).new
  @lexers = Hash(String, Noir::CSharpLexer).new

  private def class_files : Hash(String, Array(String))
    @class_files ||= begin
      index = Hash(String, Array(String)).new
      collect_files_by_extension(".cs").each do |path|
        next if base_relative_path(path).matches?(TEST_PATH)
        content = read_file(path) || next
        next unless content.includes?("class")
        content.scan(CLASS_DECL_NAME_RE) do |m|
          files = index[m[1]] ||= [] of String
          files << path unless files.includes?(path)
        end
      end
      index
    end
  end

  private def lexer_for(path : String) : Noir::CSharpLexer?
    @lexers[path] ||= Noir::CSharpLexer.new(read_file(path) || return)
  end

  # Every declaration of `name` in `path` (or in every file declaring it),
  # with the position of its body's `{` (or -1 for a `;`-terminated one).
  private def declarations(name : String, paths : Array(String)) : Array(Tuple(ClassDecl, Bool, Int32, Int32))
    decl_re = /((?:\[[^\]]*\]\s*)*)#{CLASS_MODIFIERS.source}class\s+#{Regex.escape(name)}\b([^{};]*)([{;])/
    found = [] of Tuple(ClassDecl, Bool, Int32, Int32)
    paths.each do |path|
      lexer = lexer_for(path) || next
      code = lexer.code_source
      lexer.masked_source.scan(decl_re) do |m|
        attributes = code[m.begin(1), m[1].size]
        base = m[2].match(DECL_BASE_RE).try(&.[1])
        partial = m[0][m[1].size..].includes?("partial")
        found << {ClassDecl.new(name, attributes, base), partial, m.begin(0), m[3] == "{" ? m.end(0) - 1 : -1}
      end
    end
    found
  end

  # The scanned declarations of `name`, parts of one `partial` type merged;
  # empty when the scan does not declare it or declares unrelated types of
  # that name.
  private def class_decls(name : String) : Array(ClassDecl)
    @class_decls[name] ||= begin
      found = declarations(name, class_files[name]? || [] of String)
      found.size == 1 || found.all?(&.[1]) ? found.map(&.[0]) : [] of ClassDecl
    end
  end

  # The class enclosing `method_line`, then each base class the scan
  # declares, nearest first.
  private def class_chain(path : String, lines : Array(String), method_line : Int32) : Array(ClassDecl)
    idx = nearest_match_above(@class_lines, path, lines) { |line| current = line.strip; current.includes?("class ") && (current.includes?(":") || current.includes?("{")) }[method_line]
    return [] of ClassDecl if idx < 0
    name = lines[idx].match(CLASS_DECL_NAME_RE).try(&.[1]) || return [] of ClassDecl
    own = declarations(name, [path]).map(&.[0])
    chain = own.dup
    base = own.compact_map(&.base).first?
    seen = Set{name}
    8.times do
      break unless base && seen.add?(base)
      decls = class_decls(base)
      break if decls.empty?
      chain.concat(decls)
      base = decls.compact_map(&.base).first?
    end
    chain
  end

  # The attributes stacked on the action at `method_line`.
  private def action_attributes(lines : Array(String), method_line : Int32) : String
    attrs = [] of String
    idx = method_line - 1
    while idx >= 0 && idx >= method_line - 12
      current = lines[idx].strip
      break if current.empty? || current.ends_with?(';') || current.ends_with?('}') || current.ends_with?('{')
      attrs.unshift(current) unless current.starts_with?("//")
      idx -= 1
    end
    attrs.join(' ')
  end

  # The nearest instance of each attribute on the action, its class or a
  # base class whose definition refuses the caller. An action-level
  # instance replaces the class-level one (`[CheckAccess(ignore: true)]`
  # opting one action out), and an instance passing `true` to a `bool`
  # constructor parameter of the attribute is an opt-out.
  # ponytail: "nearest instance wins" and "`true` disables" are the common
  # filter override conventions; a filter that combines its instances some
  # other way is read the same.
  private def filter_attribute_guard(lines : Array(String), method_line : Int32, chain : Array(ClassDecl)) : Tag?
    seen = Set(String).new
    ([action_attributes(lines, method_line)] + chain.map(&.attributes)).each do |list|
      list.scan(ATTRIBUTE_ENTRY_RE) do |m|
        name = m[1].rchop("Attribute")
        next unless seen.add?(name)
        verdict = filter_guard(name) || next
        description, configurable = verdict
        next if opt_out?(name, m[2]?)
        return Tag.new(configurable ? "authz" : "auth", "Protected by [#{name}] (#{description})", "aspnet_auth")
      end
    end
    nil
  end

  private def opt_out?(name : String, args : String?) : Bool
    return false unless args && args.matches?(/(?:\A|[,:])\s*true\s*(?:,|\z)/)
    decl = attribute_decl(name) || return false
    body = class_body(decl[0], decl[1]) || return false
    body.matches?(/\b#{Regex.escape(decl[0])}\s*\([^)]*\bbool\s+\w+/)
  end

  private def attribute_decl(name : String) : Tuple(String, String)?
    {"#{name}Attribute", name}.each do |candidate|
      paths = class_files[candidate]? || next
      return {candidate, paths.first} if paths.size == 1
    end
    nil
  end

  private def class_body(name : String, path : String) : String?
    @class_bodies["#{path}\0#{name}"] ||= begin
      entry = declarations(name, [path]).find { |found| found[3] >= 0 }
      if entry && (lexer = lexer_for(path)) && (close = lexer.matching_delimiter(entry[3]))
        lexer.code_source[entry[3]..close]
      end
    end
  end

  # `{description, configurable}` when the attribute `name` is a filter the
  # scan declares whose definition (or the filter type it instantiates via
  # `typeof(...)`) refuses the request; nil otherwise.
  private def filter_guard(name : String) : Tuple(String, Bool)?
    return @filter_guards[name] if @filter_guards.has_key?(name)
    @filter_guards[name] = begin
      if decl = attribute_decl(name)
        body = class_body(decl[0], decl[1]) || ""
        body.scan(TYPEOF_RE) do |m|
          next if body.includes?("class #{m[1]}")
          body += (class_files[m[1]]?.try { |paths| paths.size == 1 ? class_body(m[1], paths.first) : nil } || "")
        end
        if refusal = body.match(FILTER_REFUSAL_RE)
          result = refusal[0].sub(/\A\w+\.Result\s*=\s*new\s+/, "").split(/[\s(]/).first
          if check = body.match(PERMISSION_CHECK_RE)
            {"refuses with #{result} unless `#{check[1]}(#{check[2].strip})` grants it; which roles hold that permission is configuration, so a setting can admit anonymous callers", true}
          else
            {"filter refuses with #{result}", false}
          end
        end
      end
    end
  end

  # ---- refusals in the action body ---------------------------------------

  # `return Challenge();` / `Forbid()` / `Unauthorized()` / a 401/403 status.
  ACTION_REFUSAL_RE = /\breturn\s+(?:(?:base|this)\.)?(?:Challenge|Forbid|Unauthorized)\s*\(|\breturn\s+new\s+(?:ChallengeResult|ForbidResult|UnauthorizedResult)\b|\breturn\s+StatusCode\s*\(\s*(?:40[13]\b|StatusCodes\.Status40[13]|\(int\)\s*HttpStatusCode\.(?:Unauthorized|Forbidden))/
  # An expression reading who the caller is.
  CALLER_RE           = /\bUser\b|\bIsAuthenticated\b|\bIs(?:Registered|Guest|SignedIn)\w*\s*\(|\bGet(?:Current|Authenticated|Signed)\w*\s*\(|\bGetUser(?:Id)?(?:Async)?\s*\(|\bCurrent(?:User|Principal|Customer|Account|Member)\b/
  LOCAL_ASSIGNMENT_RE = /\b(?:var|[A-Z]\w*\??)\s+(\w+)\s*=\s*([^;]+);/

  # A refusal under a condition that reads the caller (directly or through
  # a local assigned from the caller), in the action body or in a helper of
  # the same file whose result the action returns. A refusal on a bad
  # input (`if (!valid) return Unauthorized();` in a login action) is not
  # a guard.
  private def action_refusal(path : String, lines : Array(String), method_line : Int32) : String?
    body = action_body(lines, method_line)
    if found = caller_refusal(body)
      return "an in-action #{found} when the caller does not qualify"
    end
    file = lines.join('\n')
    body.scan(/(?:\b(\w+)\s*=\s*)?(?:await\s+)?\b([A-Z]\w*)\s*\(/) do |call|
      helper = call[2]
      returned = body.matches?(/\breturn\s+(?:await\s+)?#{Regex.escape(helper)}\s*\(/) ||
                 (call[1]? && body.matches?(/\breturn\s+#{Regex.escape(call[1])}\s*;/))
      next unless returned
      definition = file.match(/\b(?:private|protected|internal|public)\b[^;{}=()]*\bIActionResult\b[^;{}=()]*\b#{Regex.escape(helper)}\s*\([^)]*\)\s*\{/) || next
      helper_line = file[0, definition.begin(0)].count('\n')
      if found = caller_refusal(action_body(lines, helper_line))
        return "#{helper}() (#{found} when the caller does not qualify)"
      end
    end
    nil
  end

  private def caller_refusal(body : String) : String?
    callers = body.scan(LOCAL_ASSIGNMENT_RE).select(&.[2].matches?(CALLER_RE)).map(&.[1])
    body.scan(ACTION_REFUSAL_RE) do |refusal|
      before = body[0, refusal.begin(0)]
      condition_at = before.rindex(/\bif\s*\(/) || next
      condition = before[condition_at..]
      next unless condition.matches?(CALLER_RE) || callers.any? { |name| condition.matches?(/\b#{Regex.escape(name)}\b/) }
      return refusal[0].sub(/\Areturn\s+(?:new\s+)?/, "").rstrip(" (")
    end
    nil
  end

  # The text of the member declared at `method_line`, through the brace
  # that closes its body (or its expression body's `;`).
  private def action_body(lines : Array(String), method_line : Int32) : String
    idx = method_line
    end_idx = [method_line + 400, lines.size - 1].min
    depth = 0
    opened = false
    String.build do |io|
      while idx <= end_idx
        current = lines[idx]
        io << current << '\n'
        depth += current.count('{') - current.count('}')
        opened ||= current.includes?('{')
        break if opened ? depth <= 0 : current.strip.ends_with?(';')
        idx += 1
      end
    end
  end

  private def has_allow_anonymous?(lines : Array(String), method_line : Int32) : Bool
    return true if minimal_api_statement(lines, method_line).try(&.matches?(ALLOW_ANONYMOUS_PATTERN))
    idx = method_line - 1
    while idx >= 0 && idx >= method_line - 5
      current = lines[idx].strip
      break if current.empty? && idx < method_line - 1
      break if current.ends_with?(';')
      return true if current.matches?(ALLOW_ANONYMOUS_PATTERN)
      idx -= 1
    end
    false
  end

  private def check_method_attributes(lines : Array(String), method_line : Int32) : String?
    if statement = minimal_api_statement(lines, method_line)
      AUTHORIZE_PATTERNS.each do |pattern, desc|
        return desc if statement.matches?(pattern)
      end
    end

    idx = method_line - 1
    while idx >= 0 && idx >= method_line - 8
      current = lines[idx].strip
      break if current.empty? && idx < method_line - 1
      # The end of the previous statement: what sits above it decorates
      # something else (`app.MapGet("/a", [Authorize] () => ...);`).
      break if current.ends_with?(';')

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
  #
  # Inside a route-builder extension method, the chain reaching the builder
  # the method returns, or its `this` builder, inherits the authorization
  # its call sites chain on (`orders.MapOrdersApi().RequireAuthorization()`).
  private def check_minimal_api_fluent(lines : Array(String), route_line : Int32, depth : Int32 = 0,
                                       chain : Array(String) = [] of String, origin : Int32 = route_line) : String?
    statement = statement_at(lines, route_line)

    return "" if statement.matches?(MINIMAL_API_ALLOW_ANON)
    return "ASP.NET .RequireAuthorization()" if statement.matches?(MINIMAL_API_REQUIRE_AUTH)
    return if depth >= 5

    receiver = (statement.match(MINIMAL_API_RECEIVER) || statement.match(GROUP_DECLARATION_RECEIVER)).try(&.[1])
    return unless receiver
    chain << receiver
    unless receiver == "app"
      declaration = /\b#{Regex.escape(receiver)}\s*=\s*[\w.]*MapGroup\s*\(/
      (0...route_line).reverse_each do |idx|
        next unless lines[idx].matches?(declaration)
        return check_minimal_api_fluent(lines, idx, depth + 1, chain, origin)
      end
    end
    extension_auth(lines, origin, chain)
  end

  # The authorization a route mapped through `chain` (route receiver first,
  # root builder last) inherits from the call sites of the route-builder
  # extension method enclosing `route_line`.
  private def extension_auth(lines : Array(String), route_line : Int32, chain : Array(String)) : String?
    return if @extension_auth.empty?
    decl_idx = (0..route_line).reverse_each.find { |idx| lines[idx].includes?("this") && lines[idx].matches?(ROUTE_BUILDER_EXTENSION) } || return
    decl = lines[decl_idx].match(ROUTE_BUILDER_EXTENSION) || return
    result_auth, receiver_auth = @extension_auth[decl[1]]? || return

    # The route must sit inside the method body, and the `return x;` of
    # that body names the builder the call sites' chain applies to.
    depth = 0
    opened = false
    returned = nil
    (decl_idx...lines.size).each do |idx|
      line = lines[idx]
      return if opened && depth <= 0 && idx <= route_line
      # Only the method's own `return`, not one inside a handler lambda.
      returned ||= line.match(/\breturn\s+(\w+)\s*;/).try(&.[1]) if opened && depth == 1
      depth += line.count('{') - line.count('}')
      opened ||= line.includes?('{')
      break if opened && depth <= 0
    end

    root = chain.last
    if (receiver_auth && root == decl[2]) || (result_auth && returned && chain.includes?(returned))
      "ASP.NET .RequireAuthorization() (route group)"
    end
  end

  # A minimal API route carries its attributes on the handler lambda inside
  # its own statement (`app.MapGet("/x", [Authorize] () => ...)`), never on
  # the lines above it.
  private def minimal_api_statement(lines : Array(String), line_idx : Int32) : String?
    statement_at(lines, line_idx) if lines[line_idx].matches?(MINIMAL_API_RECEIVER)
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
  private def class_attribute_lines(path : String, lines : Array(String), method_line : Int32) : Array(String)
    attrs = [] of String
    idx = nearest_match_above(@class_lines, path, lines) { |line| current = line.strip; current.includes?("class ") && (current.includes?(":") || current.includes?("{")) }[method_line]
    return attrs if idx < 0

    attr_idx = idx - 1
    while attr_idx >= 0 && attr_idx >= idx - 5
      attr = lines[attr_idx].strip
      break if attr.empty? && attr_idx < idx - 1
      # The end of the previous declaration: its attributes are not ours.
      break if attr.ends_with?('}') || attr.ends_with?(';') || attr.ends_with?('{')
      attrs << attr
      attr_idx -= 1
    end
    attrs
  end

  # Scans the action from its declaration to its end: the brace that closes
  # its body, or the `;` of an expression body (`Public() => Ok("x");`) or
  # one-statement route, so the next action's checks are never read.
  private def check_action_body(lines : Array(String), method_line : Int32) : String?
    idx = method_line
    # ponytail: braces inside strings/comments skew the depth; the cap bounds it.
    end_idx = [method_line + 200, lines.size - 1].min
    depth = 0
    opened = false

    while idx <= end_idx
      current = lines[idx].strip

      ACTION_AUTH_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      depth += current.count('{') - current.count('}')
      opened ||= current.includes?('{')
      break if opened ? depth <= 0 : current.ends_with?(';')
      idx += 1
    end

    nil
  end
end
