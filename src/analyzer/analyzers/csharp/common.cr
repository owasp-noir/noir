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
  # `[FromHeader(Name = "X-Tenant")]`): `{attributes, type, name}`.
  PUBLIC_PROPERTY_RE = /((?:\[[^\]]*\]\s*)*)(?:public|internal)\s+(?:(?:required|virtual|override|new)\s+)*([\w<>\[\]\?\.]+)\s+([A-Za-z_]\w*)\s*\{\s*(?:get|init|set)\b/

  # A `[JsonIgnore]` that also skips the member on read (`Condition =
  # WhenWritingNull` only affects writing).
  JSON_IGNORE_RE        = /\bJsonIgnore(?:Attribute)?\s*(?:[\],]|\(\s*\))|JsonIgnoreCondition\.Always/
  JSON_PROPERTY_NAME_RE = /\bJsonPropertyName(?:Attribute)?\s*\(\s*"([^"]+)"/

  @csharp_type_files : Hash(String, Array(String))? = nil

  # The member definitions (positional-record parameters, or public
  # properties with their attributes) of request type `type_name`, declared
  # in `lines` (the file at `file`) or else in the scanned `.cs` file that
  # shares the most of `file`'s path. Empty when the scan does not declare it.
  protected def type_member_defs(type_name : String, file : String, lines : Array(String), masked_lines : Array(String)) : Array(String)
    if defs = member_defs_in(type_name, lines, masked_lines)
      return defs
    end
    candidates = csharp_type_files[type_name]? || return [] of String
    other = candidates.max_by? { |path| common_prefix_size(path, file) } || return [] of String
    lexer = Noir::CSharpLexer.new(read_file_content(other))
    member_defs_in(type_name, lexer.code_lines, lexer.masked_lines) || [] of String
  end

  private def common_prefix_size(a : String, b : String) : Int32
    size = 0
    a.each_char_with_index do |char, i|
      break unless b[i]? == char
      size += 1
    end
    size
  end

  # Type name => the non-test `.cs` files declaring it, built on first use.
  private def csharp_type_files : Hash(String, Array(String))
    @csharp_type_files ||= begin
      index = Hash(String, Array(String)).new
      get_files_by_extension(".cs").each do |path|
        next if Common.csharp_test_path?(base_relative_path(path))
        read_file_content(path).scan(TYPE_DECLARATION_RE) do |m|
          files = index[m[1]] ||= [] of String
          files << path unless files.includes?(path)
        end
      end
      index
    end
  end

  # nil when `lines` does not declare `type_name`.
  private def member_defs_in(type_name : String, lines : Array(String), masked_lines : Array(String)) : Array(String)?
    # Hoisted out of the loop: an interpolated regex literal recompiles
    # (PCRE2 JIT) on every evaluation, i.e. once per line.
    type_decl_regex = /\b(?:record|class|struct)\s+(?:class\s+|struct\s+)?#{Regex.escape(type_name)}\b/
    def_idx = lines.index do |l|
      l.includes?(type_name) && l.matches?(type_decl_regex)
    end
    return unless def_idx
    defline = lines[def_idx]
    name_pos = defline.index(/\b#{Regex.escape(type_name)}\b/)
    paren = defline.index('(', name_pos || 0)
    # A positional record's parameters are its properties; a class's primary
    # constructor parameters are not members at all.
    if name_pos && paren && paren > name_pos && defline.matches?(/\brecord\b/)
      return split_csharp_parameters(gather_balanced_parens(lines, masked_lines, def_idx, paren))
    end

    defs = [] of String
    extract_method_block(lines, masked_lines, def_idx).scan(PUBLIC_PROPERTY_RE) do |m|
      attrs = m[1].gsub(/\s+/, " ").strip
      defs << "#{attrs} #{m[2].strip} #{m[3]}".strip
    end
    defs
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
  # type the scan declares (a primitive, a collection, a generic).
  protected def body_type_params(param_def : String, param_type : String, file : String,
                                 lines : Array(String), masked_lines : Array(String)) : Array(Param)?
    decl = param_def.gsub(/\[[^\]]*\]\s*/, "").sub(/=.*/m, "").gsub(/\b(?:ref|out|in|params|this)\s+/, "").strip
    type = decl.sub(/\s*[A-Za-z_]\w*\z/, "").rchop('?')
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
    cleaned = member_def.gsub(/\[[^\]]*\]\s*/, "").sub(/=.*/m, "").strip
    name = cleaned.match(/([A-Za-z_]\w*)\s*\z/).try(&.[1]) || return
    if explicit = member_def.match(JSON_PROPERTY_NAME_RE)
      name = explicit[1]
    elsif param_type == "json"
      name = name[0].downcase + name[1..]
    end
    Param.new(name, "", param_type)
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
