require "../../../models/analyzer"
require "../../../miniparsers/csharp_type_extractor"
require "./common"

module Analyzer::CSharp
  class AspNetCoreMvc < Analyzer
    analyzer_for "cs_aspnet_core_mvc"

    include Common

    DEFAULT_ROUTE = "{controller=Home}/{action=Index}/{id?}"

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). The `[FromX]` attribute set is fixed, so
    # precompile its markers and strippers once at load time; the
    # param-name regex interpolates a discovered name and is memoized.
    FROM_ATTRIBUTE_PATTERNS = {
      "FromQuery"         => "query",
      "FromRoute"         => "path",
      "FromBody"          => "json",
      "FromHeader"        => "header",
      "FromForm"          => "form",
      "FromCookie"        => "cookie",
      "FromServices"      => "service",
      "FromKeyedServices" => "service",
    }.map do |attr, type|
      {"[#{attr}", /\[#{attr}[^\]]*\]/, type}
    end
    @param_name_strip_regexes = Hash(String, Regex).new

    def analyze
      include_callee = callees_needed?
      project_roots = Common.project_roots(get_files_by_extension(".csproj"))
      route_patterns_by_scope = load_route_patterns_by_scope(project_roots)
      analyze_controllers(route_patterns_by_scope, project_roots, include_callee)
      @result
    end

    # Conventional routing is declared per project, so scope the collected
    # `MapControllerRoute` templates to the `.csproj` directory that owns the
    # declaring `Program.cs`/`Startup.cs`, falling back to the configured scan
    # base for files outside any project.
    #
    # Keying on the scan base alone cross-products every template in a
    # solution with every controller in it: dotnet/aspnetcore, scanned as one
    # project, produced routes like
    # `/ConventionalTransformerRoute/{controller}/Login` by applying one
    # sample's template to another sample's controller — 138 of its 738
    # `cs_aspnet_core_mvc` endpoints were such phantoms.
    private def route_scope_for(file : String, project_roots : Array(String)) : String
      Common.project_root_for(file, project_roots) || configured_base_for(file)
    end

    private def extract_params_from_block(block : String) : Array(Param)
      params = [] of Param
      query_regex = /Request\.Query\["([^"]+)"\]/
      header_regex = /Request\.Headers\["([^"]+)"\]/
      cookie_regex = /Request\.Cookies\["([^"]+)"\]/
      form_regex = /Request\.Form\["([^"]+)"\]/
      json_property_regex = /GetProperty\s*\(\s*"([^"]+)"\s*\)/

      block.scan(query_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "query") if key && !key.empty?
      end
      block.scan(header_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "header") if key && !key.empty?
      end
      block.scan(cookie_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "cookie") if key && !key.empty?
      end
      block.scan(form_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "form") if key && !key.empty?
      end
      block.scan(json_property_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "json") if key && !key.empty?
      end

      params.uniq(&.name)
    end

    private def load_route_patterns_by_scope(project_roots : Array(String)) : Hash(String, Array(String))
      patterns_by_scope = Hash(String, Array(String)).new do |hash, key|
        hash[key] = [] of String
      end
      files = get_files_by_extension(".cs").select do |file|
        base = File.basename(file)
        base == "Program.cs" || base == "Startup.cs"
      end

      files.each do |file|
        content = read_file_content(file)
        patterns_by_scope[route_scope_for(file, project_roots)].concat(extract_route_patterns(content))
      rescue e
        logger.debug "Failed to read #{file}: #{e.message}"
      end

      @base_paths.each do |base_path|
        patterns_by_scope[base_path] << DEFAULT_ROUTE if patterns_by_scope[base_path].empty?
      end

      patterns_by_scope.each do |scope, patterns|
        patterns << DEFAULT_ROUTE if patterns.empty?
        patterns_by_scope[scope] = patterns.uniq
      end

      patterns_by_scope
    end

    private def extract_route_patterns(content : String) : Array(String)
      patterns = [] of String

      route_regex = /Map[A-Za-z]*ControllerRoute\s*\((.*?)\)/m
      pattern_regex = /pattern\s*:\s*"([^"]+)"/m
      literal_regex = /"([^"]*\{[^}]+\}[^"]*)"/m

      content.scan(route_regex) do |match|
        call_content = match[1]? || ""

        found_pattern = false
        call_content.scan(pattern_regex) do |pattern_match|
          value = pattern_match[1]?
          patterns << value if value
          found_pattern = true
        end

        # Handle overloads like MapControllerRoute("default", "{controller=Home}/{action=Index}/{id?}")
        unless found_pattern
          call_content.scan(literal_regex) do |literal_match|
            candidate = literal_match[1]?
            patterns << candidate if candidate && !candidate.empty?
          end
        end
      end

      if content.includes?("MapDefaultControllerRoute")
        patterns << DEFAULT_ROUTE
      end

      patterns
    end

    # Discovery reads the whole solution, so the gate in front of `CSharpLexer`
    # decides what the analyzer costs: bitwarden/server ships 5,512 `.cs` files
    # and 277 controllers, and lexing all of them is a 5-6x scan.
    #
    # Every intrinsic controller marker is visible in the declaring source —
    # the `*Controller` name suffix, `[Controller]`/`[ApiController]`, and the
    # `Controller`/`ControllerBase` framework bases. Those files are lexed
    # up front. A type can still inherit a marker from a local base
    # (`class Users : BaseApiEndpoint`), so the files that name one of the
    # marked types are pulled in afterwards, and those that never spell
    # `Controller` at all only have to be checked against marked names that
    # do not spell it either — in practice none, so the bulk of a solution is
    # never read past the substring test.
    CONTROLLER_MARKER          = "Controller"
    FRAMEWORK_CONTROLLER_BASES = {"Controller", "ControllerBase"}
    CONTROLLER_SUFFIX_RE       = /Controller$/i
    CONTROLLER_MARKER_RE       = /Controller/
    CONTROLLER_DECLARATION_RE  = /\bclass\s+\w*Controller\b|[\[,]\s*(?:global::)?(?:\w+\.)*(?:Api)?Controller(?:Attribute)?\s*[\]\(,]|:\s*(?:global::)?(?:\w+\.)*Controller(?:Base)?\b/
    # Only a class with a base list can inherit a marker it does not declare.
    DERIVED_CLASS_RE = /\bclass\s+\w+[^{};]*+:/

    private def analyze_controllers(route_patterns_by_scope : Hash(String, Array(String)),
                                    project_roots : Array(String), include_callee : Bool)
      queue = [] of String  # declares an intrinsic marker — lex now
      marked = [] of String # mentions `Controller`; may derive from a marked type
      plain = [] of String  # never mentions it; only a marker-free base can reach it
      get_files_by_extension(".cs").each do |file|
        next if Common.csharp_test_path?(base_relative_path(file))
        source = file_source(file)
        # `Controller` gates the expensive test: an intrinsic marker always
        # contains it, so a file without it can only ever be reached through a
        # marker-free base, and most of a solution stops here.
        if source.matches?(CONTROLLER_MARKER_RE)
          if source.matches?(CONTROLLER_DECLARATION_RE)
            queue << file
            next
          end
          marked << file if source.matches?(DERIVED_CLASS_RE)
        elsif source.matches?(DERIVED_CLASS_RE)
          plain << file
        end
      end

      types_by_scope = Hash(String, Array(Tuple(String, Noir::CSharpType))).new do |hash, key|
        hash[key] = [] of Tuple(String, Noir::CSharpType)
      end
      extracted = Set(String).new
      all_types = [] of Noir::CSharpType

      until queue.empty?
        queue.each do |file|
          next unless extracted.add?(file)
          lexer = file_lexer(file)
          next unless lexer
          next if Common.aspnet_framework_source?(lexer.code_source)
          scope = route_scope_for(file, project_roots)
          Noir::CSharpTypeExtractor.extract(lexer).each do |type|
            types_by_scope[scope] << {file, type}
            all_types << type
          end
        end

        queue = [] of String
        names = marker_base_names(all_types)
        next if names.empty?
        queue.concat(take_files_naming(marked, names))
        queue.concat(take_files_naming(plain, names.reject(&.includes?(CONTROLLER_MARKER))))
      end

      # Selected controllers grouped by file so a file holding several of them
      # is lexed once, not once per class.
      selected = Hash(String, Array(Tuple(Noir::CSharpType, Array(String)))).new do |hash, key|
        hash[key] = [] of Tuple(Noir::CSharpType, Array(String))
      end
      types_by_scope.each do |scope, entries|
        index = Hash(String, Array(Noir::CSharpType)).new
        entries.each { |_, type| (index[type.name] ||= [] of Noir::CSharpType) << type }
        route_patterns = route_patterns_by_scope[scope]? || [DEFAULT_ROUTE]
        entries.each do |file, type|
          # A `partial` controller splits its modifiers, base list and
          # attributes across files: only one part carries `public class
          # FooController : ControllerBase`, the rest are bare `partial class
          # FooController`. Decide on the union, then analyze this part.
          parts = declaration_parts(type, index)
          modifiers = parts.flat_map(&.modifiers)
          next unless modifiers.includes?("public")
          next if parts.any?(&.generic) || modifiers.includes?("abstract") || modifiers.includes?("static")
          attributes = controller_attributes(parts, index)
          next if attributes.includes?("NonController")
          next unless CONTROLLER_SUFFIX_RE.matches?(type.name) ||
                      attributes.includes?("Controller") || attributes.includes?("ApiController")
          selected[file] << {type, route_patterns}
        end
      end

      selected.each do |file, controllers|
        lexer = file_lexer(file)
        next unless lexer
        controllers.each do |type, route_patterns|
          analyze_controller(file, lexer, type, route_patterns, include_callee)
        end
      end
    end

    # Moves the files naming one of `names` out of `pool` and returns them.
    private def take_files_naming(pool : Array(String), names : Array(String)) : Array(String)
      return [] of String if pool.empty? || names.empty?
      referenced = Regex.union(names.map { |name| /\b#{Regex.escape(name)}\b/ })
      hits = [] of String
      keep = [] of String
      pool.each do |file|
        if file_source(file).matches?(referenced)
          hits << file
        else
          keep << file
        end
      end
      pool.replace(keep)
      hits
    end

    private def file_source(file : String) : String
      read_file_content(file)
    rescue e
      logger.debug "Failed to read #{file}: #{e.message}"
      ""
    end

    private def file_lexer(file : String) : Noir::CSharpLexer?
      Noir::CSharpLexer.new(read_file_content(file))
    rescue e
      logger.debug "Failed to read #{file}: #{e.message}"
      nil
    end

    # Names whose subclasses inherit a controller marker. The `*Controller`
    # name suffix is deliberately absent: ASP.NET Core reads it off the
    # candidate type itself, never off a base (`class Unmarked :
    # UnmarkedController` is not a controller).
    private def marker_base_names(types : Array(Noir::CSharpType)) : Array(String)
      names = Set(String).new
      types.each do |type|
        base = type.base_name
        names << type.name if type.attributes.includes?("Controller") ||
                              type.attributes.includes?("ApiController") ||
                              (base && FRAMEWORK_CONTROLLER_BASES.includes?(base))
      end
      loop do
        added = false
        types.each do |type|
          next if names.includes?(type.name)
          base = type.base_name
          next unless base && names.includes?(base)
          names << type.name
          added = true
        end
        break unless added
      end
      names.to_a
    end

    # The parts of one `partial` declaration, or just the type itself. Parts
    # are matched by simple name, so only `partial` types are grouped: two
    # unrelated `Helper` classes in different namespaces must not merge.
    private def declaration_parts(type : Noir::CSharpType,
                                  index : Hash(String, Array(Noir::CSharpType))) : Array(Noir::CSharpType)
      return [type] unless type.modifiers.includes?("partial")
      parts = (index[type.name]? || [type]).select(&.modifiers.includes?("partial"))
      parts.empty? ? [type] : parts
    end

    private def controller_attributes(parts : Array(Noir::CSharpType),
                                      index : Hash(String, Array(Noir::CSharpType)),
                                      visited = Set(String).new) : Array(String)
      attributes = [] of String
      parts.each { |part| attributes.concat(part.attributes) }
      return attributes unless visited.add?(parts.first.name)

      parts.each do |part|
        next unless base = part.base_name
        candidates = index[base]?
        if candidates.nil? || candidates.empty?
          attributes << "Controller" if FRAMEWORK_CONTROLLER_BASES.includes?(base)
          next
        end
        # More than one local declaration of the same simple name is ambiguous
        # without namespace resolution — unless they are the parts of one
        # `partial` type.
        next unless candidates.size == 1 || candidates.all?(&.modifiers.includes?("partial"))
        attributes.concat(controller_attributes(candidates, index, visited))
      end
      attributes
    end

    private def analyze_controller(file : String, lexer : Noir::CSharpLexer, type : Noir::CSharpType,
                                   route_patterns : Array(String), include_callee : Bool)
      controller_name = type.name.sub(CONTROLLER_SUFFIX_RE, "")
      # Slice the file's already-lexed views down to this class. `line_offset`
      # puts the reported line back in file coordinates.
      line_offset = type.start_line
      lines = lexer.code_lines[type.start_line..type.end_line]
      masked_lines = lexer.masked_lines[type.start_line..type.end_line]
      controller_route = extract_controller_route(lines)

      # Accumulate every `[Http<Verb>(...)]` on the pending action so a method
      # carrying more than one (`[HttpGet(...)]` + `[HttpHead(...)]` for image/
      # file serving, GET+POST, …) emits an endpoint per verb instead of only
      # the last attribute. `route_attr` holds a verb-less `[Route(...)]` base
      # that a bare `[HttpGet]` (no path of its own) inherits.
      verb_routes = [] of Tuple(String, String)
      route_attr = ""
      explicit_endpoint_attribute = false
      non_action_attribute = false
      depth = 0

      i = 0
      while i < lines.size
        start_index = i
        line = lines[i]

        if depth == 1
          # Stitch together a multi-line `[Http<Verb>(\n   "/path",\n
          # Order = 1\n)]` attribute before running the
          # single-line matcher. The `[Http*]` opener arrives without
          # a closing paren on the same line, the path literal lives
          # on a subsequent line; the per-line matcher only
          # saw `[HttpPost(` and recorded POST with an empty path.
          attr_line, advance = stitch_multiline_attribute(lines, masked_lines, i)
          line = attr_line if advance > 0

          if accept = collect_accept_verbs(line, route_attr)
            accept_verbs, accept_route = accept
            accept_verbs.each { |accept_verb| verb_routes << {accept_verb, accept_route} }
            explicit_endpoint_attribute = true
          else
            verb, verb_route, route_attr, found_attribute = collect_verb_route(line, route_attr)
            explicit_endpoint_attribute ||= found_attribute
            verb_routes << {verb, verb_route} if verb
          end
          non_action_attribute = true if line.includes?("[NonAction")

          # Skip the continuation lines we just consumed; they're
          # already folded into `line`.
          i += advance if advance > 0
        end

        if depth == 1 && potential_member_signature?(masked_lines[i])
          signature, end_index = build_signature(lines, masked_lines, i)
          if signature.matches?(/\bpublic\b/) && !non_action_attribute && action_method?(signature, explicit_endpoint_attribute)
            action_name = extract_action_name(signature)
            unless action_name.empty?
              body_block, body_line, skip_first = extract_callable_body(lines, masked_lines, end_index)
              body_params = extract_params_from_block(body_block)

              # No `[Http*]` attribute → convention-based (verb GET, route from
              # any `[Route]` base or the controller convention).
              emit_pairs = verb_routes.empty? ? [{"GET", route_attr}] : verb_routes
              emit_pairs.each do |emit_verb, emit_route|
                # A bare `[HttpGet]` whose `[Route("x")]` base arrived on a
                # later line collected an empty route — fall back to the base
                # so verb-then-`[Route]` ordering matches `[Route]`-then-verb.
                emit_route = route_attr if emit_route.empty? && !route_attr.empty?
                parameters = extract_parameters(signature, emit_verb)
                parameters = merge_params(parameters, body_params, emit_verb)
                effective_action_route = emit_route
                if !controller_route.empty? && controller_route == effective_action_route
                  effective_action_route = ""
                end
                routes = resolve_routes(controller_route, effective_action_route, controller_name, action_name, parameters, route_patterns)

                routes.each do |route|
                  details = Details.new(PathInfo.new(file, line_offset + i + 1))
                  endpoint = Endpoint.new(route, emit_verb, details)

                  align_params_with_route(parameters, route).each do |param|
                    endpoint.params << param
                  end

                  attach_csharp_callees(endpoint, body_block, file, line_offset + body_line + 1, include_callee, skip_first_line: skip_first)
                  @result << endpoint
                end
              end
            end
          end
          verb_routes.clear
          route_attr = ""
          explicit_endpoint_attribute = false
          non_action_attribute = false
          i = end_index
        end

        (start_index..i).each do |index|
          depth += masked_lines[index].count('{') - masked_lines[index].count('}')
        end
        i += 1
      end
    end

    # Collapses a `[Http<Verb>(...)` / `[Route(...)]` attribute that
    # was split across multiple lines into a single logical line so
    # the single-line attribute regexes in `extract_attribute_route`
    # can find the path literal. Returns `{joined_line, advance}`
    # where `advance` is the number of *extra* lines consumed; the
    # caller adds that to its loop index. A non-multi-line case
    # returns `{line, 0}` so the existing fast path is preserved.
    private def stitch_multiline_attribute(lines : Array(String), masked : Array(String), start : Int32) : Tuple(String, Int32)
      line = lines[start]
      return {line, 0} unless line =~ /\[(Http(Post|Get|Put|Delete|Patch|Head|Options)|Route|AcceptVerbs)\b/

      # The attribute closes when paren+bracket depth returns to zero. Depth is
      # counted over `masked` — a route template is free to carry a literal
      # `(` or `[` (`[HttpGet("smile-(-face")]`), and counting those as
      # structure leaves the attribute permanently unbalanced, swallowing every
      # remaining line of the class. If the opening line is already balanced,
      # no stitching is needed.
      paren = delimiter_depth(masked, start, '(', ')')
      bracket = delimiter_depth(masked, start, '[', ']')
      return {line, 0} if paren <= 0 && bracket <= 0

      joined = line.rstrip
      idx = start + 1
      # Cap the read-ahead at 8 lines — far beyond what a real-world
      # attribute spans, but tight enough that a runaway file with
      # unbalanced brackets can't blow up the scan.
      max_read = (start + 8).clamp(0, lines.size - 1)
      while idx <= max_read
        joined += " " + lines[idx].strip
        paren += delimiter_depth(masked, idx, '(', ')')
        bracket += delimiter_depth(masked, idx, '[', ']')
        break if paren <= 0 && bracket <= 0
        idx += 1
      end

      # An attribute that never balances runs `idx` one past `max_read`, which
      # is the last line. The caller indexes `lines`/`masked_lines` with the
      # advanced cursor, so it must stay in range.
      {joined, idx.clamp(start, lines.size - 1) - start}
    end

    private def delimiter_depth(masked : Array(String), index : Int32, open : Char, close : Char) : Int32
      line = masked[index]?
      return 0 unless line
      line.count(open) - line.count(close)
    end

    # `[AcceptVerbs("PUT", "PATCH")]` / `[AcceptVerbs("PUT", Route = "Bank")]`
    # declares an action answering several verbs at one route — the MVC
    # equivalent of stacking `[HttpPut]` and `[HttpPatch]`. It was ignored
    # entirely, so such actions fell back to the conventional GET route.
    ACCEPT_VERBS_RE       = /\[AcceptVerbs\s*\(([^\]]*)\)\s*\]/
    ACCEPT_VERBS_ROUTE_RE = /\bRoute\s*=\s*@?"([^"]+)"/
    # ASP.NET Core routing has always accepted an arbitrary method string
    # through `[AcceptVerbs(...)]`; QUERY (RFC 10008) ships natively as
    # `HttpMethods.Query` starting with .NET 10.
    ACCEPT_VERB_TOKENS = %w[GET POST PUT DELETE PATCH HEAD OPTIONS QUERY]

    private def collect_accept_verbs(line : String, route_attr : String) : Tuple(Array(String), String)?
      match = ACCEPT_VERBS_RE.match(line)
      return unless match

      args = match[1]
      route = ACCEPT_VERBS_ROUTE_RE.match(args).try(&.[1]) || route_attr
      verbs = [] of String
      args.scan(/@?"([^"]+)"/) do |literal|
        token = literal[1].upcase
        next unless ACCEPT_VERB_TOKENS.includes?(token)
        verbs << token unless verbs.includes?(token)
      end
      # `HttpMethods.Put`-style arguments carry the verb as an identifier.
      args.scan(/\bHttpMethods\s*\.\s*([A-Za-z]+)/) do |token|
        upcased = token[1].upcase
        next unless ACCEPT_VERB_TOKENS.includes?(upcased)
        verbs << upcased unless verbs.includes?(upcased)
      end
      return if verbs.empty?

      {verbs, route}
    end

    # Attribute name carrying each verb, for `extract_attribute_route`.
    VERB_ATTRIBUTES = {
      "[HttpPost"    => {"POST", "HttpPost"},
      "[HttpGet"     => {"GET", "HttpGet"},
      "[HttpPut"     => {"PUT", "HttpPut"},
      "[HttpDelete"  => {"DELETE", "HttpDelete"},
      "[HttpPatch"   => {"PATCH", "HttpPatch"},
      "[HttpHead"    => {"HEAD", "HttpHead"},
      "[HttpOptions" => {"OPTIONS", "HttpOptions"},
    }

    # Classify one attribute line. Returns `{verb, verb_route, route_attr, found}`:
    # for an `[Http<Verb>(...)]` the verb + its route (falling back to the
    # `[Route]` base for a path-less attribute), with `route_attr` left
    # unchanged; for a verb-less `[Route("x")]` the new base in `route_attr`
    # (verb `nil`); for any other line, no change and `found = false`. Keeping
    # the verb separate lets the caller accumulate several verbs on one method.
    private def collect_verb_route(line : String, route_attr : String) : Tuple(String?, String, String, Bool)
      VERB_ATTRIBUTES.each do |marker, pair|
        next unless line.includes?(marker)
        verb, attr = pair
        return {verb, extract_attribute_route(line, attr, route_attr), route_attr, true}
      end

      if line.includes?("[Route")
        return {nil, route_attr, extract_attribute_route(line, "Route", route_attr), true}
      end

      {nil, route_attr, route_attr, false}
    end

    ACCESS_MODIFIER_RE = /\b(?:public|private|protected|internal)\b/
    # `class`/`struct`/`interface`/`enum` are reserved, so their presence alone
    # marks a type declaration. `record` is contextual and a perfectly legal
    # parameter name (`Save(AuditRecord record)`) — it only declares a type
    # when an identifier follows it.
    TYPE_DECLARATION_RE = /\b(?:class|struct|interface|enum)\b|\brecord\s+(?:class\s+|struct\s+)?\w+\s*[<({]/

    private def potential_member_signature?(line : String) : Bool
      line.matches?(ACCESS_MODIFIER_RE) && line.includes?("(") && !line.matches?(TYPE_DECLARATION_RE)
    end

    private def action_method?(signature : String, explicit_endpoint_attribute : Bool) : Bool
      return true if explicit_endpoint_attribute

      signature.includes?("ActionResult") ||
        signature.includes?("IActionResult") ||
        signature.includes?("JsonResult") ||
        signature.includes?("ViewResult") ||
        signature.includes?("IResult") ||
        signature.matches?(/Task\s*<\s*(?:IEnumerable|List|PagedResult|Result|Response|[A-Z]\w*)/)
    end

    private def extract_action_name(signature : String) : String
      # `.` and `?` belong in the return type: `Task<long?>`,
      # `ActionResult<UserItemDataDto?>` and
      # `Task<Bit.HttpExtensions.ListResponseModel<T>>` are all real action
      # signatures that a `[\w<>\[\],\s]` class cannot span.
      match = signature.match(/public\s+(?:async\s+)?(?:override\s+)?(?:virtual\s+)?[\w<>\[\],\s.?]+\s+(\w+)\s*\(/)
      return "" unless match
      match[1]
    end

    private def extract_parameters(signature : String, http_method : String) : Array(Param)
      parameters = [] of Param

      param_list = extract_balanced_param_list(signature)
      return parameters unless param_list

      param_list = param_list.strip
      return parameters if param_list.empty?

      default_param_type = default_param_type(http_method)

      split_csharp_parameters(param_list).each do |param_def|
        explicit_name = Common.explicit_binding_name(param_def)
        cleaned_def, param_type = normalize_param_definition(param_def)
        next if cleaned_def.empty?
        next if param_type == "service"

        if match = cleaned_def.match(/(\w+)\s*(?:=\s*[^,]+)?\s*$/)
          param_name = match[1]

          # A complex/interface action parameter with no explicit `[FromX]`
          # attribute that names a DI service (an injected repository, the
          # DbContext, a MediatR sender, …) is not request input — model
          # binding never produces one. Dropping it removes a recurring FP.
          if param_type.nil?
            strip_regex = @param_name_strip_regexes[param_name] ||= /\b#{Regex.escape(param_name)}\b\s*(?:=\s*[^,]+)?\s*$/
            type_token = cleaned_def.sub(strip_regex, "").strip.split(/\s+/).last?
            next if type_token && Common.csharp_service_type?(type_token)
          end

          parameters << Param.new(explicit_name || param_name, "", param_type || default_param_type)
        end
      end

      parameters
    end

    private def default_param_type(http_method : String) : String
      case http_method
      when "POST", "PUT", "PATCH", "QUERY"
        # QUERY (RFC 10008) carries its criteria in the request body, same as
        # POST — an unattributed complex-type parameter binds from there, not
        # the URL query string.
        "form"
      else
        "query"
      end
    end

    private def normalize_param_definition(param_def : String) : Tuple(String, String?)
      param_type = nil
      cleaned = param_def.strip

      FROM_ATTRIBUTE_PATTERNS.each do |marker, attr_regex, type|
        if cleaned.includes?(marker)
          param_type = type
          cleaned = cleaned.gsub(attr_regex, "")
        end
      end

      {cleaned.strip, param_type}
    end

    private def merge_params(signature_params : Array(Param), body_params : Array(Param), http_method : String) : Array(Param)
      merged = signature_params.map { |p| Param.new(p.name, p.value, p.param_type) }
      default_type = default_param_type(http_method)

      body_params.each do |extra|
        if idx = merged.index { |p| p.name == extra.name }
          existing = merged[idx]
          if existing.param_type == default_type || existing.param_type == "query" || existing.param_type == "form"
            merged[idx] = extra
          end
        else
          merged << extra
        end
      end

      merged
    end

    private def extract_controller_route(lines : Array(String)) : String
      lines.each_with_index do |line, index|
        if line =~ /\bclass\s+\w+/
          search_index = index - 1
          while search_index >= 0 && search_index >= index - 5
            candidate_line = lines[search_index]
            if candidate_line.includes?("[Route")
              route = extract_attribute_route(candidate_line, "Route", "")
              return route unless route.empty?
            end
            search_index -= 1
          end
          break
        end
      end
      ""
    end

    private ATTRIBUTE_REGEXES = {
      "HttpPost"    => /\[HttpPost[^(]*+\(\s*"([^"]+)"/,
      "HttpGet"     => /\[HttpGet[^(]*+\(\s*"([^"]+)"/,
      "HttpPut"     => /\[HttpPut[^(]*+\(\s*"([^"]+)"/,
      "HttpDelete"  => /\[HttpDelete[^(]*+\(\s*"([^"]+)"/,
      "HttpPatch"   => /\[HttpPatch[^(]*+\(\s*"([^"]+)"/,
      "HttpHead"    => /\[HttpHead[^(]*+\(\s*"([^"]+)"/,
      "HttpOptions" => /\[HttpOptions[^(]*+\(\s*"([^"]+)"/,
      "Route"       => /\[Route[^(]*+\(\s*"([^"]+)"/,
    }

    private TEMPLATE_REGEX = /Template\s*=\s*"([^"]+)"/

    private def extract_attribute_route(line : String, attribute : String, current_route : String) : String
      # Try to extract the first string literal inside the attribute
      regex_with_value = ATTRIBUTE_REGEXES[attribute]? || Regex.new("\\[#{attribute}[^(]*+\\(\\s*\"([^\"]+)\"")

      if match = regex_with_value.match(line)
        return match[1]
      end

      if match = TEMPLATE_REGEX.match(line)
        return match[1]
      end

      current_route
    end

    private def resolve_routes(controller_route : String, action_route : String, controller_name : String, action_name : String, parameters : Array(Param), route_patterns : Array(String)) : Array(String)
      routes = build_attribute_routes(controller_route, action_route, controller_name, action_name, parameters)

      if routes.empty?
        route_patterns.each do |pattern|
          raw_route = replace_tokens(pattern, controller_name, action_name)
          raw_route = prune_optional_placeholders(raw_route, parameters)
          routes << normalize_route(raw_route)
        end
      end

      routes.uniq
    end

    private def build_attribute_routes(controller_route : String, action_route : String, controller_name : String, action_name : String, parameters : Array(Param)) : Array(String)
      routes = [] of String
      has_controller_route = !controller_route.empty?
      has_action_route = !action_route.empty?

      return routes unless has_controller_route || has_action_route

      base_route = replace_tokens(controller_route, controller_name, action_name)
      action_part = replace_tokens(action_route, controller_name, action_name)

      if !has_action_route
        raw_route = prune_optional_placeholders(base_route, parameters)
        routes << normalize_route(raw_route) unless raw_route.empty?
      elsif action_part.starts_with?("/")
        raw_route = prune_optional_placeholders(action_part, parameters)
        routes << normalize_route(raw_route)
      else
        combined = [base_route, action_part].reject(&.empty?).join("/")
        raw_route = prune_optional_placeholders(combined, parameters)
        routes << normalize_route(raw_route)
      end

      routes
    end

    private def replace_tokens(route : String, controller_name : String, action_name : String) : String
      return "" if route.empty?

      normalized = route.strip
      normalized = normalized.gsub("[controller]", controller_name)
      normalized = normalized.gsub("{controller}", controller_name)
      normalized = normalized.gsub(/{controller=[^}]+}/, controller_name)
      normalized = normalized.gsub("[action]", action_name)
      normalized = normalized.gsub("{action}", action_name)
      normalized = normalized.gsub(/{action=[^}]+}/, action_name)

      normalized
    end

    private def normalize_route(route : String) : String
      normalized = route.strip
      normalized = normalized.gsub(/^\//, "").gsub(/\/+/, "/")
      normalized = "/" + normalized unless normalized.starts_with?("/")
      normalized = "/" if normalized == "//" || normalized == "/"
      normalized
    end

    private def prune_optional_placeholders(route : String, parameters : Array(Param)) : String
      param_names = parameters.map(&.name)
      result = route.dup

      placeholder_regex = /\{([^}]+)\}/
      route.scan(placeholder_regex) do |match|
        raw = match[1]? || match[0]
        next unless raw

        optional = raw.ends_with?("?")
        name = Common.route_placeholder_name(raw)

        if optional && !param_names.includes?(name)
          result = result.gsub("/{#{raw}}", "")
          result = result.gsub("{#{raw}}/", "")
          result = result.gsub("{#{raw}}", "")
        elsif optional || raw.includes?('=')
          # `{id?}` -> `{id}` and `{id=5}` -> `{id}`: a default value belongs
          # to the route template, not to the URL a client sends.
          result = result.gsub("{#{raw}}", "{#{raw.split('=').first.rstrip('?')}}")
        end
      end

      result
    end

    private def align_params_with_route(params : Array(Param), route : String) : Array(Param)
      path_keys = extract_route_placeholders(route)

      mapped = params.map do |param|
        param_copy = Param.new(param.name, param.value, param.param_type)
        if path_keys.includes?(param.name)
          param_copy.param_type = "path"
        end
        param_copy
      end

      path_keys.each do |key|
        unless mapped.any? { |param| param.name == key }
          mapped << Param.new(key, "", "path")
        end
      end

      mapped
    end

    private def extract_route_placeholders(route : String) : Array(String)
      keys = [] of String
      placeholder_regex = /\{([^}]+)\}/

      route.scan(placeholder_regex) do |match|
        raw = match[1]? || match[0]
        next unless raw
        keys << Common.route_placeholder_name(raw)
      end

      keys.uniq
    end
  end
end
