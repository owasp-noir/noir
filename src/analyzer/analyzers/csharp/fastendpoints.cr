require "../../../models/analyzer"
require "./common"

module Analyzer::CSharp
  class FastEndpoints < Analyzer
    include Common

    alias RequestTypeKey = Tuple(String, String)

    # `Endpoint<TRequest>`, `Endpoint<TRequest, TResponse>`,
    # `EndpointWithoutRequest`, `EndpointWithoutRequest<TResponse>`,
    # and the `Ep` short alias all subclass the FastEndpoints
    # endpoint primitive. Any class matching one of these as a
    # base is a candidate.
    BASE_TYPE_REGEX = /:\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*,\s*)*(Endpoint(?:WithoutRequest)?(?:<[^>]*>)?|Ep<[^>]*>)/

    VERB_CALL_REGEX       = /\b(Get|Post|Put|Patch|Delete|Options|Head)\s*\(\s*"([^"]+)"/m
    VERBS_CALL_REGEX      = /\bVerbs\s*\(\s*([^)]*)\)/m
    ROUTES_CALL_REGEX     = /\bRoutes\s*\(\s*([^)]*)\)/m
    HTTP_VERB_TOKEN_REGEX = /(?:Http\.)?(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)/

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      cs_files = get_files_by_extension(".cs").reject { |f| Common.csharp_test_path?(f) }
      request_types = build_request_type_index(cs_files)

      cs_files.each do |file|
        next unless File.exists?(file)

        content = read_file_content(file)
        next unless content.includes?("Endpoint") || content.includes?("FastEndpoints")

        analyze_file(file, content, include_callee, request_types)
      end

      @result
    end

    private def build_request_type_index(files : Array(String)) : Hash(RequestTypeKey, Array(Param))
      index = Hash(RequestTypeKey, Array(Param)).new
      type_decl_regex = /(?:class|record(?:\s+struct)?|struct)\s+([A-Za-z_][A-Za-z0-9_]*)\b/
      files.each do |file|
        next unless File.exists?(file)
        content = read_file_content(file)
        base_path = configured_base_for(file)
        lines = content.lines
        i = 0
        while i < lines.size
          line = lines[i]
          if match = type_decl_regex.match(line)
            type_name = match[1]
            block, end_index = extract_request_type_block(lines, i)
            params = extract_props_from_block(block)
            if !params.empty?
              key = {base_path, type_name}
              existing = index[key]? || [] of Param
              merged = existing.dup
              params.each do |p|
                merged << p unless merged.any? { |e| e.name == p.name }
              end
              index[key] = merged
            end
            i = end_index
          end
          i += 1
        end
      end
      index
    end

    private def analyze_file(file : String, content : String, include_callee : Bool, request_types : Hash(RequestTypeKey, Array(Param)))
      base_path = configured_base_for(file)
      lines = content.lines
      i = 0
      while i < lines.size
        line = lines[i]
        if class_declaration_with_endpoint_base?(line)
          base_match = BASE_TYPE_REGEX.match(line)
          if base_match
            base = base_match[1]
            # `EndpointWithoutRequest<TResponse>` is response-only — the
            # generic arg is the response shape, not a request DTO.
            request_type = base.starts_with?("EndpointWithoutRequest") ? nil : extract_request_type(base)
            class_block, end_index = extract_class_block(lines, i)
            configure_block = extract_configure_block(class_block)
            if configure_block
              routes, methods = parse_configure(configure_block)
              if !routes.empty? && !methods.empty?
                request_params = request_type ? (request_types[{base_path, request_type}]? || [] of Param) : [] of Param
                routes.each do |route|
                  methods.each do |http_method|
                    endpoint = build_endpoint(route, http_method, file, i + 1, request_params)
                    next if endpoint.nil?
                    attach_csharp_callees(endpoint.as(Endpoint), class_block, file, i + 1, include_callee)
                    @result << endpoint.as(Endpoint)
                  end
                end
              end
            end
            i = end_index
          end
        end
        i += 1
      end
    end

    private def class_declaration_with_endpoint_base?(line : String) : Bool
      return false unless line.includes?("class ")
      return false unless line.includes?(":")
      line.includes?("Endpoint") || line.includes?("Ep<")
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

    private def extract_class_block(lines : Array(String), start_index : Int32) : Tuple(String, Int32)
      io = String::Builder.new
      brace = 0
      started = false
      i = start_index
      while i < lines.size
        line = lines[i]
        io << line
        io << '\n'
        brace += line.count('{') - line.count('}')
        started ||= brace > 0
        if started && brace <= 0
          break
        end
        i += 1
      end
      {io.to_s, i}
    end

    private def extract_configure_block(class_block : String) : String?
      lines = class_block.lines
      masked_lines = Noir::CSharpLexer.new(class_block).masked_lines
      lines.each_with_index do |line, index|
        next unless line.includes?("Configure") && line.includes?("(") && line.includes?(")")
        next unless line.includes?("override") || line.includes?("public") || line.includes?("protected")
        method_block = extract_method_block(lines, masked_lines, index)
        return method_block
      end
      nil
    end

    private def parse_configure(configure_block : String) : Tuple(Array(String), Array(String))
      routes = [] of String
      methods = [] of String
      configure_block = strip_csharp_comments(configure_block)

      # Verb-style: Get("/users/{id}")
      configure_block.scan(VERB_CALL_REGEX) do |match|
        verb = match[1]?.to_s.upcase
        path = match[2]?.to_s
        next if verb.empty? || path.empty?
        methods << verb
        routes << path
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

    # Strip `// line` and `/* block */` comments so commented-out
    # `Get("/x")` lines don't surface as endpoints. Keeps string
    # literals intact since the regex only fires inside `/* */`.
    private def strip_csharp_comments(block : String) : String
      no_block = block.gsub(/\/\*[\s\S]*?\*\//, " ")
      no_block.gsub(/\/\/[^\n]*/, "")
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
        cleaned = raw.split(":").first.gsub(/\?$/, "")
        cleaned = cleaned.lstrip("*")
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

    private def extract_request_type_block(lines : Array(String), start_index : Int32) : Tuple(String, Int32)
      io = String::Builder.new
      brace = 0
      started = false
      paren = 0
      i = start_index
      while i < lines.size
        line = lines[i]
        io << line
        io << '\n'
        brace += line.count('{') - line.count('}')
        paren += line.count('(') - line.count(')')
        started ||= brace > 0
        # Record / positional record - end on `);` outside any brace.
        if !started && line.includes?(";") && paren <= 0 && line.includes?(")")
          break
        end
        if started && brace <= 0
          break
        end
        i += 1
      end
      {io.to_s, i}
    end

    private def extract_props_from_block(block : String) : Array(Param)
      params = [] of Param
      from_attr_map = {
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
        "BindFrom"          => nil,
        "QueryParam"        => "query",
        "RouteParam"        => "path",
        "FromKeyedServices" => "service",
        "FromServices"      => "service",
      }
      lines = block.lines
      pending_type : String? = nil
      pending_skip = false

      lines.each do |raw_line|
        line = raw_line.strip
        next if line.empty?
        next if line.starts_with?("//")
        if line.starts_with?("[") && line.ends_with?("]")
          from_attr_map.each do |attr, ptype|
            if line.includes?("[#{attr}")
              if ptype.nil?
                pending_skip = true
              elsif ptype == "service"
                pending_skip = true
              else
                pending_type = ptype
              end
            end
          end
          next
        end

        if match = line.match(/public\s+(?:required\s+|virtual\s+|override\s+|static\s+)*[\w\?<>\[\],\s\.]+?\s+(\w+)\s*\{\s*get;/)
          name = match[1]
          unless pending_skip
            params << Param.new(name, "", pending_type || "")
          end
          pending_type = nil
          pending_skip = false
          next
        end

        # Positional record params: `public record GetUserRequest(int Id, string Name);`
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
  end
end
