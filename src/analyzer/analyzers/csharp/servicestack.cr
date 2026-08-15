require "../../../models/analyzer"
require "./common"

module Analyzer::CSharp
  # Extracts endpoints from ServiceStack (https://servicestack.net/) request
  # DTOs. Unlike ASP.NET (Core) MVC, the routable unit is the *request DTO
  # class itself*, not a controller method:
  #
  #   [Route("/hello/{Name}", "GET")]
  #   public class Hello : IReturn<HelloResponse>
  #   {
  #       public string Name { get; set; }
  #   }
  #
  # A DTO class can carry more than one `[Route(...)]` attribute (one per
  # path/verb combination it answers), and the verb list is a comma (or
  # space) delimited string on the attribute itself — omitted entirely means
  # "every verb". Because each attribute names its own verbs, routes are
  # *not* cross-multiplied against each other the way FastEndpoints'
  # independent `Routes()`/`Verbs()` calls are: `/movies` and `/movies/{Id}`
  # in the same class can (and in ServiceStack's own examples do) answer
  # completely different verb sets.
  #
  # ServiceStack also supports registering the same DTOs from code, inside
  # `AppHostBase.Configure()`:
  #
  #   Routes.Add<Hello>("/hello/{Name}");
  #   Routes.Add<GetContact>("/Contacts", "GET");
  #
  # which is handled separately: the call site (usually `AppHost.cs`) rarely
  # lives next to the DTO declaration, so resolving `Hello`'s properties
  # needs a small cross-file type index, similar in spirit to (but simpler
  # than) FastEndpoints' `Endpoint<TRequest>` resolution.
  #
  # `[Route]` is also a legal attribute on Controller actions in classic
  # ASP.NET MVC / Web API, and ASP.NET Core MVC controllers use it too. To
  # avoid stealing those routes (the concern the analyzer project-scoping
  # campaign fixed across the language), this analyzer only looks at files
  # carrying a genuine ServiceStack signal (`IReturn`/`IReturnVoid`, `using
  # ServiceStack`, or the fluent `Routes.Add` API) and additionally refuses
  # any class whose base list names `Controller`/`ControllerBase` — a
  # ServiceStack request DTO never derives from either.
  class ServiceStack < Analyzer
    analyzer_for "cs_servicestack"

    include Common

    # Whole-file gate: only files that show a real ServiceStack fingerprint
    # are scanned at all. `\bIReturn\b` also matches `IReturn<T>` (the `<` is
    # a non-word char, so `\b` still lands right after "IReturn").
    SERVICESTACK_SOURCE_RE = /\bIReturn(?:Void)?\b|using\s+ServiceStack\b|\bRoutes\.Add\b/

    # `[Route("/path")]`, `[Route("/path", "GET")]`, `[Route("/path", "GET,POST")]`,
    # or with other attributes stacked on the same line
    # (`[Route("/x", "POST"),SystemJson(...)]`). Deliberately does not match
    # `[FallbackRoute(...)]` — "Route" must immediately follow `[` and
    # optional whitespace.
    ROUTE_ATTR_REGEX = /\[\s*Route\s*\(\s*"([^"]*)"(?:\s*,\s*"([^"]*)")?/

    # `class Hello`, `record Hello(string Name)`, `record struct Hello`,
    # `struct Hello` — an optional generic parameter list, an optional
    # positional-record parameter list, then an optional base list up to the
    # first `{` (brace body) or `;` (positional record with no body).
    CLASS_DECL_REGEX = /\b(?:class|record(?:\s+struct)?|struct)\s+(\w+)(?:<[^>]*>)?(?:\s*\([^)]*\))?\s*(?::\s*([^{;]+))?/

    CONTROLLER_BASE_RE = /\bControllerBase\b|\bController\b/

    # `Routes.Add<Hello>("/hello/{Name}")`, possibly chained
    # (`Routes.Add<A>("/a").Add<B>("/b")`) or spread across a fluent call
    # chain starting from a bare `Routes` on its own line.
    FLUENT_CALL_RE = /\.Add<(\w+)>\s*\(\s*"([^"]*)"(?:\s*,\s*"([^"]*)")?\s*\)/

    private record FluentRegistration,
      file : String,
      line : Int32,
      type_name : String,
      path : String,
      verbs_raw : String?

    private record TypeDef, file : String, params : Array(Param)

    def analyze
      include_callee = callees_needed?

      cs_files = get_files_by_extension(".cs").reject { |f| Common.csharp_test_path?(base_relative_path(f)) }

      servicestack_files = [] of String
      fluent_registrations = [] of FluentRegistration
      wanted = Set(String).new

      cs_files.each do |file|
        next unless File.exists?(file)
        content = read_file_content(file)
        next unless content_matches?(content, SERVICESTACK_SOURCE_RE)

        servicestack_files << file
        collect_fluent_registrations(content, file).each do |reg|
          fluent_registrations << reg
          wanted << reg.type_name
        end
      end

      return @result if servicestack_files.empty?

      servicestack_files.each do |file|
        analyze_attribute_routes(file, read_file_content(file), include_callee)
      end

      unless fluent_registrations.empty?
        type_index = build_type_index(cs_files, wanted)
        fluent_registrations.each do |reg|
          analyze_fluent_registration(reg, type_index, include_callee)
        end
      end

      @result
    end

    # ---- attribute-routed DTOs ---------------------------------------------

    private def analyze_attribute_routes(file : String, content : String, include_callee : Bool)
      lexer = Noir::CSharpLexer.new(content)
      lines = lexer.code_lines
      masked_lines = lexer.masked_lines

      pending_routes = [] of Tuple(String, String?)
      i = 0
      while i < lines.size
        line = lines[i]
        trimmed = line.strip

        if trimmed.starts_with?("[") && (m = ROUTE_ATTR_REGEX.match(line))
          pending_routes << {m[1], m[2]?}
          i += 1
          next
        end

        unless pending_routes.empty?
          if class_match = CLASS_DECL_REGEX.match(line)
            base_list = class_match[2]? || ""
            block, end_index = extract_type_block(lines, masked_lines, i)
            unless base_list.matches?(CONTROLLER_BASE_RE)
              params = extract_props_from_block(block)
              pending_routes.each do |(raw_path, verbs_raw)|
                verbs(verbs_raw).each do |http_method|
                  endpoint = build_endpoint(raw_path, http_method, file, i + 1, params)
                  attach_csharp_callees(endpoint, block, file, i + 1, include_callee)
                  @result << endpoint
                end
              end
            end
            pending_routes = [] of Tuple(String, String?)
            i = end_index
          elsif trimmed.empty? || trimmed.starts_with?("[") || trimmed.starts_with?("//") || trimmed.starts_with?("*")
            # Doc-comment lines, blank separators, and other stacked
            # attributes between the [Route] attribute(s) and the DTO
            # declaration — keep accumulating.
          else
            # Some other statement appeared before a class/record/struct
            # declaration — most likely a method-level [Route] (legacy
            # ServiceStack SOAP-style services), which this analyzer does
            # not resolve. Drop the pending routes rather than mis-attach
            # them to an unrelated type further down.
            pending_routes = [] of Tuple(String, String?)
          end
        end

        i += 1
      end
    end

    # `verbs_raw` is a comma- or space-delimited verb list ("GET,POST",
    # "POST PUT"), or nil/blank meaning "every verb" — ServiceStack's own
    # semantics for an omitted second `[Route]` argument.
    private def verbs(verbs_raw : String?) : Array(String)
      return ["ANY"] if verbs_raw.nil? || verbs_raw.strip.empty?

      list = verbs_raw.split(/[,\s]+/).map(&.strip.upcase).reject(&.empty?)
      list.empty? ? ["ANY"] : list.uniq
    end

    # Counts braces (and, for positional records with no body, the
    # terminating `;`) over `masked_lines` so a `}`/`;` inside a string
    # literal can't end the block early. Mirrors
    # `Analyzer::CSharp::FastEndpoints#extract_request_type_block`.
    private def extract_type_block(lines : Array(String), masked_lines : Array(String), start_index : Int32) : Tuple(String, Int32)
      io = String::Builder.new
      brace = 0
      started = false
      paren = 0
      i = start_index
      while i < lines.size
        line = lines[i]
        masked = masked_lines[i]? || line
        io << line
        io << '\n'
        brace += masked.count('{') - masked.count('}')
        paren += masked.count('(') - masked.count(')')
        started ||= brace > 0 || masked.includes?("{")
        if !started && masked.includes?(";") && paren <= 0
          break
        end
        if started && brace <= 0
          break
        end
        i += 1
      end
      {io.to_s, i}
    end

    # Plain public auto-properties (`public string Name { get; set; }`) and
    # positional-record parameters. ServiceStack request DTOs bind
    # automatically from the route template / query string / body — unlike
    # ASP.NET or FastEndpoints there are no `[FromQuery]`/`[FromBody]`-style
    # binding attributes to key off, so every property is reported untyped
    # (`param_type` blank) and `build_endpoint` fills in path vs. the
    # verb-appropriate default.
    private def extract_props_from_block(block : String) : Array(Param)
      params = [] of Param
      block.each_line do |raw_line|
        line = raw_line.strip
        next if line.empty?
        next if line.starts_with?("//")
        next if line.starts_with?("[")

        if match = line.match(/public\s+(?:required\s+|virtual\s+|override\s+|static\s+|readonly\s+)*[\w\?<>\[\],\s\.]+?\s+(\w+)\s*\{\s*get;/)
          params << Param.new(match[1], "", "")
          next
        end

        # Positional record: `public record GetContact(string ContactId);`
        if positional_match = line.match(/^(?:public\s+)?(?:sealed\s+)?(?:record(?:\s+struct)?|struct)\s+\w+\s*\(([^)]*)\)/)
          arglist = positional_match[1]
          split_csharp_parameters(arglist).each do |arg|
            cleaned = arg.strip
            next if cleaned.empty?
            if name_match = cleaned.match(/(\w+)\s*(?:=\s*[^,]+)?\s*$/)
              params << Param.new(name_match[1], "", "")
            end
          end
        end
      end
      params.uniq(&.name)
    end

    # ---- fluent `Routes.Add<T>(...)` ---------------------------------------

    # Finds every `Routes...Add<T>("path"[, "verbs"])` call in `content`,
    # single-statement (`Routes.Add<Hello>("/hello");`) or chained
    # (`Routes\n    .Add<A>("/a")\n    .Add<B>("/b");`). Scoped to the text
    # between each bare `Routes` occurrence and the next `;` so unrelated
    # `.Add<T>(...)`-shaped calls elsewhere in the file aren't picked up.
    private def collect_fluent_registrations(content : String, file : String) : Array(FluentRegistration)
      registrations = [] of FluentRegistration
      return registrations unless content.includes?("Routes")

      lexer = Noir::CSharpLexer.new(content)
      code = lexer.code_source

      pos = 0
      while start = code.index(/\bRoutes\b/, pos)
        stop = code.index(';', start) || code.size
        statement = code[start...stop]
        line_no = code[0...start].count('\n') + 1

        statement.scan(FLUENT_CALL_RE) do |m|
          type_name = m[1]?
          path = m[2]?
          next if type_name.nil? || path.nil? || path.empty?
          registrations << FluentRegistration.new(file, line_no, type_name, path, m[3]?)
        end

        pos = stop + 1
      end

      registrations
    end

    # Small cross-file type index for the `wanted` DTO names referenced by a
    # `Routes.Add<T>(...)` call. Only the (few) referenced names are indexed
    # — see `Analyzer::CSharp::FastEndpoints#build_request_type_index` for
    # why a repo-wide union would be wrong (and slow).
    private def build_type_index(files : Array(String), wanted : Set(String)) : Hash(String, Array(TypeDef))
      index = Hash(String, Array(TypeDef)).new
      return index if wanted.empty?

      wanted_re = Regex.union(wanted.to_a.map { |name| /\b#{Regex.escape(name)}\b/ })
      type_decl_regex = /\b(?:class|record(?:\s+struct)?|struct)\s+([A-Za-z_]\w*)\b/

      files.each do |file|
        next unless File.exists?(file)
        content = read_file_content(file)
        next unless content_matches?(content, wanted_re)

        lexer = Noir::CSharpLexer.new(content)
        lines = lexer.code_lines
        masked_lines = lexer.masked_lines

        i = 0
        while i < lines.size
          if match = type_decl_regex.match(lines[i])
            type_name = match[1]
            block, end_index = extract_type_block(lines, masked_lines, i)
            if wanted.includes?(type_name)
              params = extract_props_from_block(block)
              unless params.empty?
                defs = index[type_name] ||= [] of TypeDef
                defs << TypeDef.new(file, params) unless defs.any? { |d| d.file == file }
              end
            end
            i = end_index
          end
          i += 1
        end
      end

      index
    end

    # Nearest-first resolution: the file the `Routes.Add<T>` call itself
    # lives in, then a repo-unique declaration. Ambiguous (several
    # unrelated same-named DTOs, none in the call's own file) resolves to no
    # extra params rather than guessing — path params still come through
    # from the route template regardless.
    private def resolve_fluent_params(type_index : Hash(String, Array(TypeDef)), type_name : String, file : String) : Array(Param)
      defs = type_index[type_name]?
      return [] of Param if defs.nil? || defs.empty?

      if same_file = defs.find { |d| d.file == file }
        return same_file.params
      end

      defs.size == 1 ? defs.first.params : [] of Param
    end

    private def analyze_fluent_registration(reg : FluentRegistration, type_index : Hash(String, Array(TypeDef)), include_callee : Bool)
      params = resolve_fluent_params(type_index, reg.type_name, reg.file)
      verbs(reg.verbs_raw).each do |http_method|
        endpoint = build_endpoint(reg.path, http_method, reg.file, reg.line, params)
        @result << endpoint
      end
    end

    # ---- shared endpoint construction --------------------------------------

    private def build_endpoint(raw_route : String, http_method : String, file : String, line : Int32, dto_params : Array(Param)) : Endpoint
      route = normalize_route(raw_route)
      path_params = build_path_params(route)
      default_type = default_param_type(http_method)

      collected = [] of Param
      path_params.each { |param| collected << param }

      dto_params.each do |param|
        next if collected.any? { |p| p.name == param.name }
        if path_params.any? { |p| p.name == param.name }
          collected << Param.new(param.name, "", "path")
        else
          ptype = param.param_type.empty? ? default_type : param.param_type
          collected << Param.new(param.name, param.value, ptype)
        end
      end

      details = Details.new(PathInfo.new(file, line))
      endpoint = Endpoint.new(route, http_method, details)
      collected.each { |param| endpoint.params << param }
      endpoint
    end

    private def normalize_route(route : String) : String
      normalized = route.strip
      normalized = normalized.gsub(/^\//, "").gsub(/\/+/, "/")
      normalized = "/" + normalized
      normalized = "/" if normalized == "//"
      normalized
    end

    private def build_path_params(route : String) : Array(Param)
      params = [] of Param
      route.scan(/\{([^}\/]+)\}/) do |match|
        raw = match[1]? || ""
        next if raw.empty?
        # `Common.route_placeholder_name` strips a *leading* `*` (ASP.NET
        # Core's `{*catchAll}` convention, which ServiceStack's newer
        # `{**Name}` multi-segment wildcard also satisfies). ServiceStack's
        # older/legacy wildcard syntax puts the `*` as a *suffix* instead
        # (`{ItemPath*}`, per `RouteAttribute`'s own doc comment), so strip
        # that side too.
        cleaned = Common.route_placeholder_name(raw).rstrip('*')
        next if cleaned.empty?
        params << Param.new(cleaned, "", "path") unless params.any? { |p| p.name == cleaned }
      end
      params
    end

    # GET/HEAD/OPTIONS/DELETE read from the query string; POST/PUT/PATCH and
    # the unspecified-verb `ANY` (ServiceStack itself treats "any verb" as
    # including body-carrying ones) bind from the JSON request body.
    private def default_param_type(http_method : String) : String
      case http_method
      when "GET", "HEAD", "OPTIONS", "DELETE"
        "query"
      else
        "json"
      end
    end
  end
end
