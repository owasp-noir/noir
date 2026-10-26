require "../../../miniparsers/csharp_callee_extractor"
require "../../../minilexers/csharp_lexer"
require "../../../utils/top_level_split"

module Analyzer::CSharp::Common
  # Longest method signature `build_signature` reads.
  MAX_SIGNATURE_LINES = 256

  # Standard .NET test-source conventions:
  #
  #   * `/test/` and `/tests/` parent directories — Microsoft's
  #     own repos park unit + integration tests under
  #     `src/<Project>/test/...` (aspnetcore) or `tests/...`
  #     (smaller solutions).
  #   * `/testassets/` — aspnetcore's helper-controller convention
  #     for spinning up a real server inside the test harness.
  #   * `Tests.cs` / `Test.cs` filename (`.vb` alike) — xUnit / NUnit /
  #     MSTest suffix convention.
  #
  # dotnet/aspnetcore alone parks ~3,600 phantom endpoints under
  # `src/Mvc/test/...` and similar trees. Production code never
  # adopts any of these.
  # Takes the scan-base-relative path (`Analyzer#base_relative_path`),
  # never the absolute one. The conventions describe a location inside
  # the solution, so on an absolute path a `test/` directory above the
  # scan base suppressed the whole project.
  def self.csharp_test_path?(relative_path : String) : Bool
    return true if relative_path.includes?("/test/")
    return true if relative_path.includes?("/tests/")
    return true if relative_path.includes?("/testassets/")
    File.basename(relative_path).matches?(/Tests?\.(?:cs|vb)\z/)
  end

  # ASP.NET Core and classic ASP.NET MVC 5 spell a controller almost
  # identically — `public class UserController : Controller` with `[HttpGet]`
  # action attributes — and both analyzers are handed every `.cs` file in the
  # scan. In a solution holding both (a migration in progress, the shape noir
  # gets pointed at) each read the other's controllers: 35 phantom
  # `cs_aspnet_core_mvc` endpoints out of the classic fixture, 6 the other way,
  # several with the wrong route template applied on the way out.
  #
  # The namespaces are unmistakable and mutually exclusive — a type can only
  # come from one of them — so each analyzer skips a file that names the
  # other's. Nothing positive is required, so a helper file that names neither
  # is still analyzed by both, exactly as before.
  ASPNET_CORE_NAMESPACE_RE      = /\bMicrosoft\.AspNetCore\b/
  ASPNET_FRAMEWORK_NAMESPACE_RE = /\bSystem\.Web\.(?:Mvc|Http|Routing)\b/

  def self.aspnet_core_source?(content : String) : Bool
    content.matches?(ASPNET_CORE_NAMESPACE_RE)
  end

  def self.aspnet_framework_source?(content : String) : Bool
    content.matches?(ASPNET_FRAMEWORK_NAMESPACE_RE)
  end

  # A Carter module is either `class X : ICarterModule` or
  # `class X : CarterModule` — the latter being Carter's abstract base, which
  # adds a constructor base path (`: base("/directors")`) and the request
  # filters. Both shapes own their `AddRoutes` body, so the Carter analyzer
  # claims them and the minimal-API analyzer skips them.
  #
  # `\bCarterModule\b` alone does not match inside `ICarterModule` (`I` and `C`
  # are both word characters), hence the explicit optional `I`.
  CARTER_MODULE_RE = /\bI?CarterModule\b/

  def self.carter_module_source?(content : String) : Bool
    content.matches?(CARTER_MODULE_RE)
  end

  # Directories that own a `.csproj`, longest first. A .NET *project* is the
  # unit that owns a routing table: `MapControllerRoute` in one project's
  # `Program.cs` says nothing about a controller compiled into a sibling
  # project, even though both sit under one configured scan base.
  def self.project_roots(csproj_paths : Array(String)) : Array(String)
    roots = csproj_paths.map { |path| File.dirname(path) }
    roots.uniq!
    roots.sort_by! { |dir| -dir.size }
    roots
  end

  # The longest project root containing `path`, or nil when the file sits
  # outside every discovered project (no `.csproj` in the scan at all, the
  # shape most fixtures and single-file samples have).
  def self.project_root_for(path : String, roots : Array(String)) : String?
    roots.find do |root|
      path == root || path.starts_with?("#{root}/")
    end
  end

  # A public auto-property (`public string Name { get; set; }`), its name in
  # group 1 — how request DTOs declare their bindable fields.
  AUTO_PROPERTY_RE = /public\s+(?:required\s+|virtual\s+|override\s+|static\s+|readonly\s+)*[\w\?<>\[\],\s\.]+?\s+(\w+)\s*\{\s*get;/

  # `[FromRoute(Name = "organizationId")] Guid sponsoringOrgId` binds the
  # *route* value `organizationId`; the C# identifier is only the local name.
  # Reporting the identifier invents a parameter the client cannot send and
  # hides the one it must.
  EXPLICIT_BINDING_NAME_RE = /\[From(?:Query|Route|Body|Header|Form|Cookie)\s*\(\s*(?:[A-Za-z]+\s*(?:=|:)\s*)?@?"([^"]+)"/

  def self.explicit_binding_name(param_def : String) : String?
    EXPLICIT_BINDING_NAME_RE.match(param_def).try(&.[1])
  end

  BINDING_ATTRIBUTES = {
    "FromQuery"         => "query",
    "FromRoute"         => "path",
    "FromBody"          => "json",
    "FromHeader"        => "header",
    "FromForm"          => "form",
    "FromServices"      => "service",
    "FromKeyedServices" => "service",
  }

  # The request source a `[FromX]` attribute binds a parameter from.
  def self.binding_attribute_type(param_def : String) : String?
    BINDING_ATTRIBUTES.each do |attr, param_type|
      return param_type if param_def.includes?("[#{attr}")
    end
    nil
  end

  # Strips a route-template placeholder down to its bare parameter name:
  # `{id:int}` → `id`, `{slug?}` → `slug`, `{*catchAll}` → `catchAll`,
  # `{id=5}` → `id` (a default value), `{**slug:regex(a=b)}` → `slug`.
  #
  # The `=default` form was previously kept verbatim, so a template like
  # `/items/{id=5}` emitted a parameter literally named `id=5`.
  def self.route_placeholder_name(raw : String) : String
    name = raw.split(':').first
    name = name.split('=').first
    name.strip.lstrip('*').rstrip('?')
  end

  # `IFormFile`/`IFormFileCollection`/`IFormCollection` are interfaces but
  # bind from the request body (file upload / form), not from DI — keep
  # them as request inputs even though they match the interface rule below.
  SERVICE_FORM_INPUT_TYPES = Set{"IFormFile", "IFormFileCollection", "IFormCollection"}

  # Concrete framework types that are always resolved from DI / the
  # request pipeline rather than bound from user input.
  KNOWN_SERVICE_TYPES = Set{
    "CancellationToken", "HttpContext", "HttpRequest", "HttpResponse",
    "ClaimsPrincipal", "IServiceProvider", "LinkGenerator", "ILoggerFactory",
    "IConfiguration", "IWebHostEnvironment", "IHostEnvironment",
  }

  # High-precision suffixes that mark a type as a dependency-injected
  # collaborator. Deliberately conservative: suffixes that collide with
  # common domain/entity names (e.g. `Client`, `Provider`, `Factory`) are
  # left out so request DTOs aren't dropped by mistake. Interface-typed
  # DI is caught separately by the `I<Pascal>` rule.
  #
  # `Handler` and `DataSource` joined the list after a minimal-API sweep:
  # Bitwarden injects `AccessRequestEndpointsHandler handler` straight into its
  # handler delegates and Carter's sample injects `EndpointDataSource`, both of
  # which surfaced as query parameters. Neither suffix names a request DTO in
  # practice. `Db` is the DbContext naming of Microsoft's own minimal-API
  # samples (`TodoDb : DbContext`, injected as `TodoDb db`).
  SERVICE_TYPE_SUFFIXES = %w[
    Repository Service Services Manager Mediator Mapper Accessor
    Dispatcher Publisher DbContext Context Logger Handler DataSource Db
  ]

  # Heuristic for whether a parameter's *type* names a dependency-injected
  # service (DbContext, repository, MediatR sender, mapper, …) rather than a
  # value bound from the request. ASP.NET Core can't be statically resolved
  # against its DI container, so we lean on near-universal naming
  # conventions in real code:
  #
  #   * Interfaces (`I` + PascalCase) are never deserialized from a request
  #     body and never bound from the query string — they're DI or special
  #     pipeline types. The `[a-z]` third-char guard keeps acronym value
  #     types like `IPAddress` (I-P-A) out of the net.
  #   * A small set of concrete framework types and service suffixes.
  #
  # Returns false for the form-upload interfaces, which *are* request inputs.
  def self.csharp_service_type?(type_name : String) : Bool
    base = type_name.gsub(/<.*>/, "").split('.').last.strip
    return false if base.empty?
    return false if SERVICE_FORM_INPUT_TYPES.includes?(base)
    return true if KNOWN_SERVICE_TYPES.includes?(base)
    return true if base.matches?(/\AI[A-Z][a-z]/)
    SERVICE_TYPE_SUFFIXES.any? { |suffix| base.ends_with?(suffix) }
  end

  # `masked` is the string/comment-blanked twin of `lines` (from
  # `CSharpLexer#masked_lines`). Delimiter counting runs over `masked` so a
  # `(` inside a string default (`expr = "2 * (3 + 4"`) can't keep the paren
  # counter open and run the signature away, while the returned text is built
  # from the real `lines`.
  protected def build_signature(lines : Array(String), masked : Array(String), start_index : Int32) : Tuple(String, Int32)
    # A caller can hand us a `start_index` that ran past the end of the file
    # (e.g. after folding an unbalanced multi-line attribute that consumed
    # every remaining line). Bail out instead of indexing out of bounds.
    return {"", start_index} if start_index < 0 || start_index >= lines.size

    start_mask = masked[start_index]?
    paren_count = start_mask ? start_mask.count('(') - start_mask.count(')') : 0
    index = start_index + 1

    # Parens still open after MAX_SIGNATURE_LINES never balance: without the
    # cap every declaration below an unbalanced one re-read the rest of the file.
    limit = Math.min(lines.size, start_index + MAX_SIGNATURE_LINES)
    while paren_count > 0 && index < limit
      if m = masked[index]?
        paren_count += m.count('(') - m.count(')')
      end
      index += 1
    end

    {lines[start_index...index].join(' '), index - 1}
  end

  protected def split_csharp_parameters(param_list : String) : Array(String)
    Noir::TopLevelSplit.split(param_list, ',', Noir::TopLevelSplit::Rules::CSHARP_PARAMS)
  end

  PARAM_LIST_CLAUSES = Set{"where", "As", "Handles", "Implements"}

  # Returns the substring inside the first balanced parameter-list parens of
  # a method signature. Unlike a greedy `\((.*)\)`, this stops at the matching
  # close paren so an expression body (`(int id) => Repo.Find(id)`) doesn't
  # leak the call's own arguments into the parameter list.
  protected def extract_balanced_param_list(signature : String) : String?
    # Count parens over the masked signature so a `(`/`)` inside a string
    # default value doesn't unbalance the parameter-list bounds. The masked
    # twin is character-aligned with `signature`, so the slice indices apply.
    masked = Noir::CSharpLexer.new(signature).masked
    # Skip leading `[Attr(...)]` groups sharing the line with the method
    # (`[HttpGet("b")] public IActionResult B(int k)`), so the attribute's
    # own parens aren't taken for the parameter list.
    start = 0
    loop do
      while start < masked.size && masked[start].whitespace?
        start += 1
      end
      break unless masked[start]? == '['
      depth = 0
      while start < masked.size
        depth += 1 if masked[start] == '['
        depth -= 1 if masked[start] == ']'
        start += 1
        break if depth == 0
      end
    end
    # A `(...)` group followed by more of the declaration (a name, `>`, `,`,
    # `?`, `[`) is a tuple type, not the parameter list: `static (A, B)
    # Post(Cmd c)`, `Task<(IResult, E)> Ship(...)`. C# `where` and VB
    # `As` / `Handles` / `Implements` follow a real parameter list.
    open = masked.index('(', start)
    while open
      depth = 0
      close = (open...masked.size).find do |i|
        depth += 1 if masked[i] == '('
        depth -= 1 if masked[i] == ')'
        depth == 0
      end
      return unless close
      k = close + 1
      while masked[k]?.try(&.whitespace?)
        k += 1
      end
      after = masked[k]?
      word_end = k
      while masked[word_end]?.try { |c| c.alphanumeric? || c == '_' }
        word_end += 1
      end
      clause = PARAM_LIST_CLAUSES.includes?(masked[k...word_end].join)
      type = after && (after.alphanumeric? || after.in?('_', '>', ',', '?', '[')) && !clause
      return signature[(open + 1)...close] unless type
      open = masked.index('(', close + 1)
    end
    nil
  end

  # Counts braces over `masked` (string/comment-blanked) so a `}` inside a
  # string literal (`var json = T("a } b");`) can't terminate the block early
  # and drop every callee below it. The emitted text comes from raw `lines`.
  protected def extract_method_block(lines : Array(String), masked : Array(String), start_index : Int32) : String
    io = String::Builder.new
    brace = 0
    started = false
    index = start_index

    while index < lines.size
      line = lines[index]
      m = masked[index]
      brace += m.count('{') - m.count('}')
      started ||= brace > 0 || m.includes?("{")
      io << line
      io << '\n'
      if started && brace <= 0 && m.includes?("}")
        break
      end
      # Expression-bodied member (`=> expr;`): there is no brace block, so the
      # statement terminator ends it. Without this guard the scanner would run
      # to end-of-file and swallow every following member.
      if !started && m.includes?(";")
        break
      end
      index += 1
    end

    io.to_s
  end

  # Extracts a method's body starting from the line where its signature
  # closes. Handles both brace bodies (`{ ... }`) and expression bodies
  # (`=> expr;`). Returns `{block, start_line_index, skip_first_line}` —
  # the caller passes `skip_first_line` through to the callee scanner so a
  # brace body's own declaration line isn't recorded as a self-callee.
  protected def extract_callable_body(lines : Array(String), masked : Array(String), start_index : Int32) : Tuple(String, Int32, Bool)
    i = start_index
    while i < lines.size
      m = masked[i]
      if m.includes?("{")
        # Brace body: hand the `{`-line to the scanner with skip_first so
        # the method name on that line isn't recorded as its own callee.
        return {extract_method_block(lines, masked, i), i, true}
      elsif arrow = m.index("=>")
        # Expression body: crop everything up to and including `=>` on the
        # first line, then read until the statement terminator. Delimiter
        # depth and the `;` terminator are read from `masked` so braces/parens
        # and semicolons inside string literals don't end the body early.
        io = String::Builder.new
        depth = 0
        j = i
        while j < lines.size
          raw = lines[j]
          mraw = masked[j]
          text = j == i ? raw[(arrow + 2)..]? || "" : raw
          io << text << '\n'
          depth += mraw.count('(') - mraw.count(')') + mraw.count('{') - mraw.count('}')
          break if depth <= 0 && mraw.includes?(";")
          j += 1
        end
        return {io.to_s, i, false}
      elsif m.includes?(";")
        # Abstract/interface declaration with no body.
        return {"", i, false}
      end
      i += 1
    end
    {"", start_index, false}
  end

  # A type declaration's name, for the cross-file type index.
  TYPE_DECLARATION_RE = /\b(?:class|record|struct)\s+(?:class\s+|struct\s+)?([A-Z]\w*)/

  # A public property with the attributes above it (`[JsonIgnore]`,
  # `[FromHeader(Name = "X-Tenant")]`): `{attributes, type, name, "{"}`, the
  # last group marking where the accessor list opens.
  PUBLIC_PROPERTY_RE = /((?:\[[^\]]*\]\s*)*)(?:public|internal)\s+(?:(?:required|virtual|override|new)\s+)*([\w<>\[\]\?\.,]+)\s+([A-Za-z_]\w*)\s*(\{)\s*(?:get|init|set)\b/

  # A public `set`/`init` accessor: what a binder or serializer writes.
  PUBLIC_SETTER_RE = /(?<!private |protected |internal )\b(?:set|init)\b/

  # Opts a member without a public setter into deserialization.
  SERIALIZER_INCLUDE_RE = /\b(?:JsonInclude|JsonProperty|DataMember)(?:Attribute)?\s*[\](,]/

  # An attribute list (`[FromBody]`, `[property: JsonPropertyName("x")]`),
  # not an array rank (`int[]`, `int[,]`).
  ATTRIBUTE_LIST_RE = /\[(?=\s*[A-Za-z_@])[^\]]*\]\s*/

  # What a type declares: the members a request can set, its base class,
  # and every property or positional member it names (set or not), which
  # hides a base member of the same name.
  record TypeMembers, defs : Array(String), base : String?, names : Set(String)

  # A `[JsonIgnore]` that also skips the member on read (`Condition =
  # WhenWritingNull` only affects writing).
  JSON_IGNORE_RE        = /\bJsonIgnore(?:Attribute)?\s*(?:[\],]|\(\s*\))|JsonIgnoreCondition\.Always/
  JSON_PROPERTY_NAME_RE = /\bJsonPropertyName(?:Attribute)?\s*\(\s*"([^"]+)"/

  @csharp_type_files : Hash(String, Array(String))? = nil
  # Project root ("" outside any `.csproj`) => namespaces its `global using`s import.
  @csharp_global_usings = Hash(String, Array(String)).new
  @csharp_project_roots = [] of String

  # A one-element collection type a JSON array deserializes into, or an
  # array of one: the element type is group 1 or 2.
  JSON_COLLECTION_BODY_RE = /\A(?:System\.Collections\.Generic\.)?(?:IEnumerable|ICollection|IList|List|IReadOnlyList|IReadOnlyCollection|ISet|HashSet)<\s*([A-Za-z_][\w.]*)\s*\??\s*>\z|\A([A-Za-z_][\w.]*)\??\[\]\z/

  # Deepest base-class chain followed.
  MAX_BASE_DEPTH = 8

  # A file's `namespace X.Y;` / `namespace X.Y {` and its `using X.Y;`
  # imports (an alias or `using static` imports no namespace).
  NAMESPACE_DECL_RE = /^\s*namespace\s+([\w.]+)/m
  USING_DECL_RE     = /^\s*(?:global\s+)?using\s+([\w.]+)\s*;/m

  # The member definitions (positional-record parameters, or public
  # properties with their attributes) of request type `type_name`, declared
  # in `lines` (the file at `file`) or else in the scanned `.cs` file that
  # shares the most of `file`'s path, followed by the members it inherits
  # from base classes the scan declares. Empty when the scan does not
  # declare it.
  protected def type_member_defs(type_name : String, file : String, lines : Array(String), masked_lines : Array(String)) : Array(String)
    if decl = member_defs_in(type_name, lines, masked_lines)
      return with_inherited_members(decl, file, masked_lines)
    end
    candidates = csharp_type_files[type_name]? || return [] of String
    # The declaration the name reaches through namespaces and `using`s; else
    # (an import the scan cannot see, e.g. a project-file `<Using>`) the one
    # sharing the most of the handler's path.
    path, namespace = resolve_type_file(type_name, file, masked_lines) ||
                      {candidates.max_by? { |candidate| common_prefix_size(candidate, file) } || return([] of String), nil}
    lexer = Noir::CSharpLexer.new(read_file_content(path))
    decl = member_defs_in(type_name, lexer.code_lines, lexer.masked_lines, namespace) || return [] of String
    with_inherited_members(decl, path, lexer.masked_lines)
  end

  # Appends the members of each class on `decl`'s base chain. A base is the
  # type its name reaches from the deriving file (that file's namespaces and
  # their parents, its `using`s, its project's `global using`s), never a
  # same-named type elsewhere; the walk stops at a type the scan does not
  # declare (a framework base such as `ControllerBase`) and at a cycle. A
  # base member the deriving type redeclares (`override`, `new`) is the
  # deriving type's: its attributes win, even a `[JsonIgnore]`.
  private def with_inherited_members(decl : TypeMembers, file : String, masked_lines : Array(String)) : Array(String)
    defs = decl.defs.dup
    names = decl.names.dup
    base = decl.base
    seen = Set(String).new
    MAX_BASE_DEPTH.times do
      break unless base
      name = base.split('.').last
      path, namespace = resolve_type_file(base, file, masked_lines) || break
      break unless seen.add?("#{path}\0#{base}")
      lexer = Noir::CSharpLexer.new(read_file_content(path))
      inherited = member_defs_in(name, lexer.code_lines, lexer.masked_lines, namespace) || break
      inherited.defs.each { |member| defs << member unless names.includes?(Common.member_name(member)) }
      names.concat(inherited.names)
      base = inherited.base
      file = path
      masked_lines = lexer.masked_lines
    end
    defs
  end

  # The C# name a member definition declares (`[Attr] string Name = "x"`).
  def self.member_name(member_def : String) : String
    member_def.sub(/=.*/m, "").match(/([A-Za-z_]\w*)\s*\z/).try(&.[1]) || ""
  end

  # `{file, namespace}` of the scanned declaration type `base` reaches from
  # `file`, or nil when none sits in a namespace it can see. Scopes are
  # tried in C#'s lookup order: the file's namespace, then each enclosing
  # one outwards, then the global namespace and the `using`s. A qualified
  # name whose qualifier is a type (`Outer.Inner`) resolves to that type's
  # file. The namespace is nil when the declaring file is `file` itself.
  private def resolve_type_file(base : String, file : String, masked_lines : Array(String)) : Tuple(String, String?)?
    parts = base.split('.')
    candidates = csharp_type_files[parts.last]? || return
    return {file, nil} if parts.size == 1 && candidates.includes?(file)
    masked = masked_lines.join('\n')
    enclosing = [] of String
    masked.scan(NAMESPACE_DECL_RE) do |m|
      segments = m[1].split('.')
      segments.size.downto(1) { |n| enclosing << segments[0, n].join('.') }
    end
    qualifier = parts[0...-1].join('.')
    scopes = if parts.size > 1
               enclosing.map { |ns| "#{ns}.#{qualifier}" } << qualifier
             else
               # "" is the global namespace: a file with no namespace declares into it.
               project = Common.project_root_for(file, @csharp_project_roots) || ""
               enclosing + [""] + masked.scan(USING_DECL_RE).map(&.[1]) + (@csharp_global_usings[project]? || [] of String)
             end
    declared = candidates.to_h do |path|
      namespaces = read_file_content(path).scan(NAMESPACE_DECL_RE).map(&.[1])
      {path, namespaces.empty? ? [""] : namespaces}
    end
    scopes.each do |scope|
      in_scope = candidates.select { |path| declared[path].includes?(scope) }
      return {in_scope.max_by { |path| common_prefix_size(path, file) }, scope} unless in_scope.empty?
    end
    if parts.size > 1 && (outer = resolve_type_file(qualifier, file, masked_lines))
      return {outer[0], nil} if candidates.includes?(outer[0])
    end
    nil
  end

  # The namespace each line of a file sits in (`""` for the global one),
  # following file-scoped and nested block `namespace` declarations.
  private def line_namespaces(masked_lines : Array(String)) : Array(String)
    file_scoped = [] of String
    stack = [] of Tuple(String, Int32)
    pending = nil
    depth = 0
    masked_lines.map do |line|
      if m = line.match(/^\s*namespace\s+([\w.]+)\s*(;)?/)
        m[2]? ? (file_scoped << m[1]) : (pending = m[1])
      end
      current = (file_scoped + stack.map(&.[0])).join('.')
      line.each_char do |char|
        if char == '{'
          if name = pending
            stack << {name, depth}
            pending = nil
            current = (file_scoped + stack.map(&.[0])).join('.')
          end
          depth += 1
        elsif char == '}'
          depth -= 1
          while (last = stack.last?) && last[1] >= depth
            stack.pop
          end
        end
      end
      current
    end
  end

  private def common_prefix_size(a : String, b : String) : Int32
    size = 0
    a.each_char_with_index do |char, i|
      break unless b[i]? == char
      size += 1
    end
    size
  end

  # Type name => the non-test `.cs` files declaring it, built on first use
  # (with the namespaces each project's `global using`s import).
  private def csharp_type_files : Hash(String, Array(String))
    @csharp_type_files ||= begin
      index = Hash(String, Array(String)).new
      @csharp_project_roots = Common.project_roots(get_files_by_extension(".csproj"))
      get_files_by_extension(".cs").each do |path|
        next if Common.csharp_test_path?(base_relative_path(path))
        content = read_file_content(path)
        content.scan(TYPE_DECLARATION_RE) do |m|
          files = index[m[1]] ||= [] of String
          files << path unless files.includes?(path)
        end
        next unless content.includes?("global using")
        usings = @csharp_global_usings[Common.project_root_for(path, @csharp_project_roots) || ""] ||= [] of String
        content.scan(USING_DECL_RE) { |m| usings << m[1] if m[0].includes?("global") }
      end
      index
    end
  end

  # After a declared type's name: its generic parameters and primary
  # constructor / positional-record parameters, then `:` and the first
  # base-list entry, which for a class or record is its base class.
  BASE_AFTER_NAME_RE = /\A\s*(?:<(?:[^<>]|<[^<>]*>)*>)?\s*(?:\((?:[^()]|\([^()]*\))*\))?\s*:\s*(?:global::)?([A-Za-z_][\w.]*)/

  # What `lines` declares for `type_name` (in `namespace` when given and the
  # file declares the name more than once), or nil when it does not.
  private def member_defs_in(type_name : String, lines : Array(String), masked_lines : Array(String),
                             namespace : String? = nil) : TypeMembers?
    # Hoisted out of the loop: an interpolated regex literal recompiles
    # (PCRE2 JIT) on every evaluation, i.e. once per line.
    type_decl_regex = /\b(?:record|class|struct)\s+(?:class\s+|struct\s+)?#{Regex.escape(type_name)}\b/
    decl_lines = (0...lines.size).select do |i|
      lines[i].includes?(type_name) && lines[i].matches?(type_decl_regex)
    end
    def_idx = decl_lines.first? || return
    if namespace && decl_lines.size > 1
      namespaces = line_namespaces(masked_lines)
      def_idx = decl_lines.find { |i| namespaces[i] == namespace } || def_idx
    end
    base = declared_base(masked_lines, def_idx, type_decl_regex)
    defline = lines[def_idx]
    name_pos = defline.index(/\b#{Regex.escape(type_name)}\b/)
    paren = defline.index('(', name_pos || 0)
    # A positional record's parameters are its properties; a class's primary
    # constructor parameters are not members at all.
    if name_pos && paren && paren > name_pos && defline.matches?(/\brecord\b/)
      defs = split_csharp_parameters(gather_balanced_parens(lines, masked_lines, def_idx, paren))
      return TypeMembers.new(defs, base, defs.map { |member| Common.member_name(member) }.to_set)
    end

    block = extract_method_block(lines, masked_lines, def_idx)
    masked = extract_method_block(masked_lines, masked_lines, def_idx).chars
    depth_at = type_body_depths(masked, masked_lines[def_idx].index(type_decl_regex) || 0)
    defs = [] of String
    names = Set(String).new
    ctors = nil
    block.scan(PUBLIC_PROPERTY_RE) do |m|
      next unless depth_at[m.begin(3)]? == 1
      names << m[3]
      attrs = m[1].gsub(/\s+/, " ").strip
      open = m.begin(4)
      accessors, close = accessor_list(masked, open)
      # A getter-only or privately-set property is never written from the
      # request, unless a serializer attribute opts it in, a constructor
      # parameter of the same name (which the deserializer binds) sets it,
      # or it is initialized (`{ get; } = new()`), which Json.NET and form
      # binding fill in place.
      unless accessors.matches?(PUBLIC_SETTER_RE) || attrs.matches?(SERIALIZER_INCLUDE_RE) ||
             (masked[close + 1, 40]? || [] of Char).join.matches?(/\A\s*=\s*(?:new\b|\[)/)
        ctors ||= constructors(type_name, masked)
        next unless ctors.any? { |params| params.any? { |param| Common.member_name(param).compare(m[3], case_insensitive: true) == 0 } }
      end
      defs << "#{attrs} #{m[2].strip} #{m[3]}".strip
    end
    # A `[JsonConstructor]` binds its parameters by name: each is a key.
    (ctors || constructors(type_name, masked)).each do |params|
      next unless params.first? == "[JsonConstructor]"
      params[1..].each do |param|
        name = Common.member_name(param)
        defs << param unless name.empty? || defs.any? { |member| Common.member_name(member).compare(name, case_insensitive: true) == 0 }
      end
    end
    TypeMembers.new(defs, base, names)
  end

  # Brace depth per char of a type's declaration block (masked), counted
  # from the declaration at `start`: 1 inside the type's own body, deeper in
  # a nested type, and 0 before it or after it closes (the block may run
  # past it when the type shares a line with `namespace X {`).
  private def type_body_depths(masked : Array(Char), start : Int32) : Array(Int32)
    depth = 0
    opened = false
    masked.map_with_index do |char, i|
      next 0 if i < start || (opened && depth == 0)
      at = depth
      if char == '{'
        depth += 1
        opened = true
      elsif char == '}'
        depth -= 1
      end
      at
    end
  end

  # The accessor list of a property whose `{` is at `open` (accessor
  # bodies dropped, so `{ get { … } set { … } }` reads `get set`), and the
  # index of its closing `}`.
  private def accessor_list(masked : Array(Char), open : Int32) : Tuple(String, Int32)
    io = String::Builder.new
    depth = 0
    (open...masked.size).each do |i|
      char = masked[i]
      depth += 1 if char == '{'
      depth -= 1 if char == '}'
      return {io.to_s, i} if depth == 0
      io << char if depth == 1 && char != '{'
    end
    {io.to_s, masked.size - 1}
  end

  # The parameter definitions of every constructor (or primary constructor)
  # of `type_name` in its masked declaration block, each list led by
  # `"[JsonConstructor]"` when that attribute marks it.
  private def constructors(type_name : String, masked : Array(Char)) : Array(Array(String))
    text = masked.join
    lists = [] of Array(String)
    text.scan(/\b#{Regex.escape(type_name)}\s*\(/) do |m|
      before = text[0, m.begin(0)]
      next if before.matches?(/\bnew\s*\z/)
      depth = 0
      close = (m.end(0) - 1...text.size).find do |i|
        depth += 1 if text[i] == '('
        depth -= 1 if text[i] == ')'
        depth == 0
      end || next
      params = split_csharp_parameters(text[m.end(0)...close]).map(&.strip).reject(&.empty?)
      # The attributes between the previous member and this one.
      attrs = before[(before.rindex(/[;{}]/) || -1) + 1..]
      params.unshift("[JsonConstructor]") if attrs.matches?(/\bJsonConstructor(?:Attribute)?\b/)
      lists << params
    end
    lists
  end

  # The base class named by the declaration at `def_idx` (read up to its
  # body or `;`), or nil when it declares none.
  private def declared_base(masked_lines : Array(String), def_idx : Int32, type_decl_regex : Regex) : String?
    head = masked_lines[def_idx, 6].join(' ')
    decl = head.match(type_decl_regex) || return
    head = head[decl.end..]
    head[0, head.index(/[{;]/) || head.size].match(BASE_AFTER_NAME_RE).try(&.[1])
  end

  # Collects the text inside a parenthesised group that opens at `open_pos`
  # on `lines[start_index]`, spanning subsequent lines until balanced.
  protected def gather_balanced_parens(lines : Array(String), masked : Array(String), start_index : Int32, open_pos : Int32) : String
    io = String::Builder.new
    depth = 0
    i = start_index
    started = false
    while i < lines.size
      # Index over `Array(Char)` (O(1)) rather than `String#[](Int)`, which is
      # O(n) per access on multi-byte lines and made this O(n^2) on long
      # CJK signatures — the very regression the lexer work targets.
      line_chars = lines[i].chars
      mline_chars = masked[i].chars
      from = i == start_index ? open_pos : 0
      (from...line_chars.size).each do |k|
        # Count over the masked twin so a `(`/`)` inside a string default
        # value (`prop = "f(x"`) can't unbalance the group; emit raw text.
        masked_char = k < mline_chars.size ? mline_chars[k] : ' '
        raw_char = line_chars[k]
        if masked_char == '('
          depth += 1
          started = true
          next if depth == 1
        elsif masked_char == ')'
          depth -= 1
          return io.to_s if depth == 0
        end
        io << raw_char if started && depth >= 1
      end
      io << ' '
      break if started && depth <= 0
      i += 1
    end
    io.to_s
  end

  # The members of the body type of handler parameter `param_def` bound
  # from `param_type` (`json`/`form`), or nil when its type is not a plain
  # type the scan declares (a primitive, a generic). A JSON collection body
  # (`IEnumerable<EventModel>`, `EventModel[]`) is an array of that element,
  # so its inputs are the element's members.
  protected def body_type_params(param_def : String, param_type : String, file : String,
                                 lines : Array(String), masked_lines : Array(String)) : Array(Param)?
    decl = param_def.gsub(ATTRIBUTE_LIST_RE, "").sub(/=.*/m, "").gsub(/\b(?:ref|out|in|params|this)\s+/, "").strip
    type = decl.sub(/\s*[A-Za-z_]\w*\z/, "").rchop('?')
    if param_type == "json" && (element = type.match(JSON_COLLECTION_BODY_RE))
      type = element[1]? || element[2]
    end
    return unless type.matches?(/\A[A-Za-z_][\w.]*\z/)
    params = type_member_defs(type.split('.').last, file, lines, masked_lines).compact_map do |member|
      body_member_param(member, param_type)
    end
    params.uniq(&.name) unless params.empty?
  end

  # A body member's request name: `[JsonPropertyName]`, else the member
  # name, camelCased for JSON as ASP.NET Core's web serializer defaults
  # write it (reads are case-insensitive). nil for a `[JsonIgnore]` member.
  private def body_member_param(member_def : String, param_type : String) : Param?
    return if member_def.matches?(JSON_IGNORE_RE)
    cleaned = member_def.gsub(ATTRIBUTE_LIST_RE, "").sub(/=.*/m, "").strip
    name = cleaned.match(/([A-Za-z_]\w*)\s*\z/).try(&.[1]) || return
    if explicit = member_def.match(JSON_PROPERTY_NAME_RE)
      name = explicit[1]
    elsif param_type == "json"
      name = Common.json_camel_case(name)
    end
    Param.new(name, "", param_type)
  end

  # The JSON camelCase naming policy (System.Text.Json and Json.NET agree):
  # lower the leading run of capitals, except the one that starts the next
  # word, so `OTP` → `otp`, `URLValue` → `urlValue`, `Id` → `id`.
  def self.json_camel_case(name : String) : String
    return name unless name[0]?.try(&.uppercase?)
    chars = name.chars
    chars.each_index do |i|
      break if i == 1 && !chars[i].uppercase?
      break if i > 0 && i + 1 < chars.size && !chars[i + 1].uppercase?
      chars[i] = chars[i].downcase
    end
    chars.join
  end

  PARAM_ATTRIBUTE_NAME_RE = /[\[,]\s*([A-Z]\w*)\s*(?=[\(\],])/
  BINDER_TYPEOF_RE        = /\btypeof\s*\(\s*([\w.]+)\s*\)/
  MODEL_BINDER_TYPEOF_RE  = /\bModelBinder(?:Attribute)?\s*\([^\]]*?\btypeof\s*\(\s*([\w.]+)\s*\)/

  # Request access in a model binder's source: the value posted under the
  # parameter's own name, a value provider, or the raw request.
  BINDER_PARAM_NAME_READ_RE = /\b(?:ModelName|FieldName)\b/
  BINDER_REQUEST_READ_RE    = /\bValueProvider\b|\bRequest\s*\./
  BINDER_FIXED_KEY_RE       = /\bValueProvider\s*\.\s*GetValue\s*\(\s*"([^"]+)"\s*\)/

  # How a parameter's custom binding changes what the request sends:
  # `{drop, key}`. `drop` when the request never supplies it: `[BindNever]`,
  # or a custom model binder (`[ModelBinder(typeof(B))]`, or an attribute
  # whose scanned definition derives from `ModelBinderAttribute` naming B)
  # whose scanned source, base classes included, reads nothing from the
  # request — it builds the value server-side, e.g. loading an entity by a
  # route id. `key` when the binder reads one fixed value-provider key
  # (`ValueProvider.GetValue("sort")`) instead of the parameter's name. A
  # binder the scan does not declare is assumed to read the request as
  # usual.
  protected def custom_binding(param_def : String) : Tuple(Bool, String?)
    return {false, nil} unless param_def.includes?('[')
    names = param_def.scan(PARAM_ATTRIBUTE_NAME_RE).map(&.[1])
    return {true, nil} if names.any?(&.in?("BindNever", "BindNeverAttribute"))
    binder = param_def.match(MODEL_BINDER_TYPEOF_RE).try(&.[1])
    binder ||= names.compact_map { |attr| attribute_binder_type(attr) }.first?
    return {false, nil} unless binder
    source = binder_source(binder.split('.').last) || return({false, nil})
    return {false, nil} if source.matches?(BINDER_PARAM_NAME_READ_RE)
    keys = source.scan(BINDER_FIXED_KEY_RE).map(&.[1]).uniq!
    return {false, keys.first} if keys.size == 1
    {!source.matches?(BINDER_REQUEST_READ_RE), nil}
  end

  # The binder type a custom `ModelBinderAttribute` subclass names.
  private def attribute_binder_type(attr : String) : String?
    return if attr.starts_with?("From") || attr.starts_with?("ModelBinder")
    block, _ = type_block(attr.ends_with?("Attribute") ? attr : "#{attr}Attribute") || return
    return unless block.matches?(/:\s*(?:[\w.]+\.)?ModelBinderAttribute\b/)
    block.match(BINDER_TYPEOF_RE).try(&.[1])
  end

  # A binder's source with its scanned base classes'; nil when the scan
  # does not declare it.
  private def binder_source(type_name : String) : String?
    block, base = type_block(type_name) || return
    io = String::Builder.new(block)
    seen = Set{type_name}
    MAX_BASE_DEPTH.times do
      name = base.try(&.split('.').last) || break
      break unless seen.add?(name)
      base_block, base = type_block(name) || break
      io << '\n' << base_block
    end
    io.to_s
  end

  # The declaration block and base class of a type the scan declares once,
  # or nil.
  private def type_block(type_name : String) : Tuple(String, String?)?
    files = csharp_type_files[type_name]?
    return unless files && files.size == 1
    lexer = Noir::CSharpLexer.new(read_file_content(files.first))
    lines = lexer.code_lines
    decl_regex = /\b(?:class|record|struct)\s+#{Regex.escape(type_name)}\b/
    def_idx = lines.index(&.matches?(decl_regex)) || return
    {extract_method_block(lines, lexer.masked_lines, def_idx), declared_base(lexer.masked_lines, def_idx, decl_regex)}
  end

  protected def attach_csharp_callees(endpoint : Endpoint,
                                      block : String,
                                      file : String,
                                      start_line : Int32,
                                      include_callee : Bool,
                                      *,
                                      skip_first_line : Bool = false)
    return unless include_callee

    callees = Noir::CSharpCalleeExtractor.callees_for_block(block, file, start_line, skip_first_line: skip_first_line)
    Noir::CSharpCalleeExtractor.attach_to(endpoint, callees)
  end
end
