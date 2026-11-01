require "../../../models/analyzer"
require "../../../miniparsers/csharp_decl_parser"
require "./common"

module Analyzer::CSharp
  class FastEndpoints < Analyzer
    analyzer_for "cs_fastendpoints"

    include Common

    alias RequestTypeKey = Tuple(String, String)

    # One `class Request { … }` declaration: where it was found and the
    # request properties it contributes.
    private record RequestTypeDef, file : String, params : Array(Param)

    # `Endpoint<TRequest>`, `Endpoint<TRequest, TResponse>`,
    # `EndpointWithoutRequest`, `EndpointWithoutRequest<TResponse>`,
    # and the `Ep` short alias all subclass the FastEndpoints
    # endpoint primitive. Any class matching one of these as a
    # base is a candidate.
    BASE_TYPE_REGEX = /:\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*,\s*)*(Endpoint(?:WithoutRequest)?(?:<[^>]*>)?|Ep<[^>]*>)/

    # Whole-file gate. One JIT-compiled union beats the two `String#includes?`
    # scans it replaces, and it also refuses files that merely mention the word
    # "Endpoint" without declaring a FastEndpoints class.
    ENDPOINT_SOURCE_RE = /\bFastEndpoints\b|:\s*(?:[A-Za-z_][\w.]*\s*,\s*)*(?:Endpoint(?:WithoutRequest)?\b|Ep\s*<)/

    # `Post("/a", "/b")` registers every literal, not just the first.
    VERB_CALL_REGEX       = /\b(Get|Post|Put|Patch|Delete|Options|Head)\s*\(\s*("[^)]*)\)/m
    GROUP_CALL_REGEX      = /\bGroup\s*<\s*(?:[\w.]+\.)?(\w+)\s*>\s*\(\s*\)/
    PREFIX_OVERRIDE_REGEX = /\bRoutePrefixOverride\s*\(\s*@?"([^"]*)"/
    # `app.UseFastEndpoints(c => c.Endpoints.RoutePrefix = "api")`.
    ROUTE_PREFIX_REGEX = /\.\s*Endpoints\s*\.\s*RoutePrefix\s*=\s*@?"([^"]*)"/
    # `sealed class Admin : Group { public Admin() { Configure("admin", ...); } }`
    # and the nested `class Sub : SubGroup<Admin>`.
    GROUP_CLASS_REGEX     = /\bclass\s+(\w+)\s*:\s*(?:Group\b|SubGroup\s*<\s*(?:[\w.]+\.)?(\w+)\s*>)/
    GROUP_PREFIX_REGEX    = /\bConfigure\s*\(\s*@?"([^"]*)"/
    VERBS_CALL_REGEX      = /\bVerbs\s*\(\s*([^)]*)\)/m
    ROUTES_CALL_REGEX     = /\bRoutes\s*\(\s*([^)]*)\)/m
    HTTP_VERB_TOKEN_REGEX = /(?:Http\.)?(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)/

    def analyze
      include_callee = callees_needed?

      cs_files = get_files_by_extension(".cs").reject { |f| Common.csharp_test_path?(base_relative_path(f)) }
      # One pass picks the FastEndpoints sources and, from the same content,
      # the request-DTO names their `Endpoint<TRequest>` bases refer to. Only
      # those DTOs are worth indexing: the old code extracted the property
      # list of *every* type declaration in the scan — ~28k of them in
      # dotnet/aspnetcore, none of which FastEndpoints ever looks up.
      endpoint_files = [] of Tuple(String, Noir::CSharpLexer, Noir::CSharpDecl::Unit)
      wanted = Set(String).new
      cs_files.each do |file|
        next unless File.exists?(file)
        content = read_file_content(file)
        # Same literal prerequisite the old gate had, kept as a cheap
        # short-circuit ahead of the structural union.
        next unless content.includes?("Endpoint")
        next unless content_matches?(content, ENDPOINT_SOURCE_RE)

        lexer = Noir::CSharpLexer.new(content)
        unit = Noir::CSharpDeclParser.parse(lexer)
        endpoint_files << {file, lexer, unit}
        endpoint_types(unit).each do |_, base|
          next if base.starts_with?("EndpointWithoutRequest")
          extract_request_type(base).try { |type_name| wanted << type_name }
        end
      end
      return @result if endpoint_files.empty?

      request_types = build_request_type_index(cs_files, wanted)
      route_prefixes, groups = collect_route_prefixes(cs_files)

      endpoint_files.each do |file, lexer, unit|
        analyze_file(file, lexer, unit, include_callee, request_types, route_prefixes, groups)
      end

      @result
    end

    # The global `RoutePrefix` per scan base, and each endpoint group's own
    # `Configure("prefix")` with its `SubGroup<T>` parent.
    private def collect_route_prefixes(files : Array(String)) : Tuple(Hash(String, String), Hash(String, Tuple(String, String?)))
      route_prefixes = Hash(String, String).new
      groups = Hash(String, Tuple(String, String?)).new
      files.each do |file|
        next unless File.exists?(file)
        content = read_file_content(file)
        next unless content.includes?("RoutePrefix") || content.includes?("Group")
        code = Noir::CSharpLexer.new(content).code_source
        if match = ROUTE_PREFIX_REGEX.match(code)
          route_prefixes[configured_base_for(file)] ||= match[1]
        end
        code.scan(GROUP_CLASS_REGEX) do |group|
          prefix = GROUP_PREFIX_REGEX.match(code, group.end).try(&.[1]) || ""
          groups[group[1]] = {prefix, group[2]?}
        end
      end
      {route_prefixes, groups}
    end

    private def group_prefix(name : String, groups : Hash(String, Tuple(String, String?)), depth = 0) : String
      group = groups[name]?
      return "" unless group && depth < 8
      prefix, parent = group
      return prefix unless parent
      [group_prefix(parent, groups, depth + 1), prefix].reject(&.empty?).join('/')
    end

    # The classes of `unit` deriving a FastEndpoints endpoint primitive, with
    # that base (`Endpoint<Req, Res>`).
    private def endpoint_types(unit : Noir::CSharpDecl::Unit) : Array(Tuple(Noir::CSharpDecl::TypeDecl, String))
      unit.types.compact_map do |type|
        next if type.kind != "class" || type.bases.empty?
        base = BASE_TYPE_REGEX.match(": #{type.bases.join(", ")}").try(&.[1]) || next
        {type, base}
      end
    end

    # Indexes every request-DTO candidate by `{base, type name}` — but keeps
    # the *declarations* apart instead of unioning their properties.
    #
    # FastEndpoints' idiomatic vertical-slice layout gives every feature
    # folder its own `Request`/`Response` pair, so a repo-wide union of
    # everything named `Request` is catastrophic: FastEndpoints' own test
    # harness holds 55 distinct `class Request`, and each of its endpoints was
    # emitted with the ~110-property union of all of them. `resolve_request_params`
    # picks one declaration per lookup instead.
    private def build_request_type_index(files : Array(String), wanted : Set(String)) : Hash(RequestTypeKey, Array(RequestTypeDef))
      index = Hash(RequestTypeKey, Array(RequestTypeDef)).new
      return index if wanted.empty?

      wanted_re = Regex.union(wanted.to_a.map { |name| /\b#{Regex.escape(name)}\b/ })
      files.each do |file|
        next unless File.exists?(file)
        content = read_file_content(file)
        next unless content_matches?(content, wanted_re)
        base_path = configured_base_for(file)
        Noir::CSharpDeclParser.parse(Noir::CSharpLexer.new(content)).types.each do |type|
          next unless type.kind.in?("class", "record", "struct") && wanted.includes?(type.name)
          params = request_props(type)
          next if params.empty?
          key = {base_path, type.name}
          defs = index[key] ||= [] of RequestTypeDef
          # A type declared twice in one file (partial class, or the same
          # name in two namespaces of one file) is still one declaration
          # site; union those.
          if existing_idx = defs.index { |d| d.file == file }
            merged = defs[existing_idx].params.dup
            params.each { |p| merged << p unless merged.any? { |e| e.name == p.name } }
            defs[existing_idx] = RequestTypeDef.new(file, merged)
          else
            defs << RequestTypeDef.new(file, params)
          end
        end
      end
      index
    end

    # Resolves `Endpoint<TRequest>` to one declaration of `TRequest`, nearest
    # first: the endpoint's own file, then its directory (the vertical-slice
    # feature folder), then a repo-unique declaration. When several unrelated
    # declarations share the name and none is nearby, the type is ambiguous —
    # emitting nothing beats emitting every candidate's properties at once.
    private def resolve_request_params(index : Hash(RequestTypeKey, Array(RequestTypeDef)),
                                       base_path : String,
                                       type_name : String?,
                                       file : String) : Array(Param)
      return [] of Param unless type_name
      defs = index[{base_path, type_name}]?
      return [] of Param if defs.nil? || defs.empty?

      if same_file = defs.find { |d| d.file == file }
        return same_file.params
      end

      dir = File.dirname(file)
      same_dir = defs.select { |d| File.dirname(d.file) == dir }
      return same_dir.first.params if same_dir.size == 1

      return defs.first.params if defs.size == 1

      [] of Param
    end

    private def analyze_file(file : String, lexer : Noir::CSharpLexer, unit : Noir::CSharpDecl::Unit, include_callee : Bool,
                             request_types : Hash(RequestTypeKey, Array(RequestTypeDef)),
                             route_prefixes : Hash(String, String), groups : Hash(String, Tuple(String, String?)))
      base_path = configured_base_for(file)
      global_prefix = route_prefixes[base_path]? || ""
      lines = lexer.code_lines
      endpoint_types(unit).each do |type, base|
        configure = type.methods.find { |method| method.name == "Configure" && method.params.empty? } || next
        configure_block = lines[configure.line..configure.end_line].join('\n')
        routes, methods = parse_configure(configure_block)
        next if routes.empty? || methods.empty?
        # `EndpointWithoutRequest<TResponse>` is response-only — the
        # generic arg is the response shape, not a request DTO.
        request_type = base.starts_with?("EndpointWithoutRequest") ? nil : extract_request_type(base)
        request_params = resolve_request_params(request_types, base_path, request_type, file)
        prefix = PREFIX_OVERRIDE_REGEX.match(configure_block).try(&.[1]) || global_prefix
        group = GROUP_CALL_REGEX.match(configure_block).try { |m| group_prefix(m[1], groups) } || ""
        class_block = lines[type.line..type.end_line].join('\n')
        routes.each do |raw_route|
          # FastEndpoints builds `{RoutePrefix}/{group prefix}/{route}`.
          route = [prefix, group, raw_route].map(&.strip('/')).reject(&.empty?).join('/')
          methods.each do |http_method|
            endpoint = build_endpoint(route, http_method, file, type.line + 1, request_params) || next
            attach_csharp_callees(endpoint, class_block, file, type.line + 1, include_callee)
            @result << endpoint
          end
        end
      end
    end

    # Walks the first generic argument with balanced angle brackets so
    # `Endpoint<Page<User>, Res>` resolves to `Page<User>` instead of
    # collapsing to `Page` at the first inner `<`.
    private def extract_request_type(base : String) : String?
      start = base.index('<')
      return unless start
      depth = 0
      io = String::Builder.new
      i = start
      while i < base.size
        char = base[i]
        case char
        when '<'
          depth += 1
          io << char unless depth == 1
        when '>'
          depth -= 1
          break if depth == 0
          io << char
        when ','
          break if depth == 1
          io << char
        else
          io << char
        end
        i += 1
      end
      arg = io.to_s.strip
      return if arg.empty?
      # Look up by the outer type name when the request is generic
      # (e.g. `Page<User>` → index entry for `Page`).
      outer = arg.split('<').first.strip
      outer.empty? ? nil : outer
    end

    private def parse_configure(configure_block : String) : Tuple(Array(String), Array(String))
      routes = [] of String
      methods = [] of String

      # Verb-style: Get("/users/{id}")
      configure_block.scan(VERB_CALL_REGEX) do |match|
        verb = match[1].upcase
        match[2].scan(/"([^"]+)"/) do |literal|
          methods << verb
          routes << literal[1]
        end
      end

      # Routes("/a", "/b") additional/alternative paths
      configure_block.scan(ROUTES_CALL_REGEX) do |match|
        args = match[1]?.to_s
        args.scan(/"([^"]+)"/) do |literal|
          path = literal[1]?.to_s
          routes << path unless path.empty?
        end
      end

      # Verbs(Http.GET, Http.POST, ...) needs separate path declaration
      configure_block.scan(VERBS_CALL_REGEX) do |match|
        args = match[1]?.to_s
        args.scan(HTTP_VERB_TOKEN_REGEX) do |token|
          name = token[1]?.to_s.upcase
          methods << name unless name.empty?
        end
      end

      {routes.uniq, methods.uniq}
    end

    private def build_endpoint(raw_route : String, http_method : String, file : String, line : Int32, request_params : Array(Param)) : Endpoint?
      return if raw_route.empty?

      route = normalize_route(raw_route)
      path_params = build_path_params(route)
      default_type = default_param_type(http_method)

      collected = [] of Param
      path_params.each { |param| collected << param }

      request_params.each do |param|
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
        cleaned = Common.route_placeholder_name(raw)
        next if cleaned.empty?
        params << Param.new(cleaned, "", "path") unless params.any? { |p| p.name == cleaned }
      end
      params
    end

    private def default_param_type(http_method : String) : String
      case http_method
      when "POST", "PUT", "PATCH"
        "json"
      else
        "query"
      end
    end

    # How a request DTO's property attribute binds it (`""`: by the verb's
    # default); `service` is never request input.
    FROM_ATTRIBUTES = {
      "FromQuery"  => "query",
      "FromRoute"  => "path",
      "FromBody"   => "json",
      "FromHeader" => "header",
      "FromForm"   => "form",
      "FromCookie" => "cookie",
      # `[FromClaim]` reads from the auth principal's JWT claims —
      # not a request-side binding, so skip rather than mis-tag as
      # `header`.
      "FromClaim"         => "service",
      "BindFrom"          => "",
      "QueryParam"        => "query",
      "RouteParam"        => "path",
      "FromKeyedServices" => "service",
      "FromServices"      => "service",
    }

    # A public auto-property's accessor list (`{ get; set; }`).
    AUTO_ACCESSORS_RE = /\A\{\s*get\s*;/

    # The request properties of DTO `type`: its positional-record members and
    # public auto-properties, named and bound by their attributes.
    private def request_props(type : Noir::CSharpDecl::TypeDecl) : Array(Param)
      params = [] of Param
      type.params.try &.each { |param| params << Param.new(param.name, "", "") } if type.kind.in?("record", "struct")
      type.members.each do |member|
        next unless member.kind == :property && member.public?
        next unless member.accessors.try(&.matches?(AUTO_ACCESSORS_RE))
        bound = ""
        name = member.name
        skip = false
        member.attributes.each do |attr|
          ptype = FROM_ATTRIBUTES[attr.name]? || next
          if ptype == "service"
            skip = true
            next
          end
          bound = ptype unless ptype.empty?
          # `[BindFrom("last_name")]` / `[FromHeader("X-Tenant")]` bind the
          # property under that name.
          attr.positional.first?.try(&.literal).presence.try { |literal| name = literal }
        end
        params << Param.new(name, "", bound) unless skip
      end
      params.uniq(&.name)
    end
  end
end
