require "../../../models/analyzer"
require "../../../miniparsers/csharp_type_extractor"
require "./common"

module Analyzer::CSharp
  # ABP Framework conventional ("auto API") controllers. ABP turns every
  # application service in an assembly registered with
  # `options.ConventionalControllers.Create(typeof(XModule).Assembly)` into an
  # MVC controller, so an ABP app has almost no hand-written controllers and
  # the attribute-routed ASP.NET analyzer sees none of its API.
  #
  # The route mirrors ABP's `ConventionalRouteBuilder`:
  #
  #   /api/<rootPath>/<service>[/{id}][/<action>[/{xId}]]
  #
  # `rootPath` defaults to `app`; `<service>` is the class name minus its
  # `AppService`/`ApplicationService`/`Service` postfix, kebab-cased; the verb
  # comes from the method-name prefix (`HttpMethodHelper.ConventionalPrefixes`)
  # and whatever is left of the name becomes the `<action>` segment.
  #
  # Services in a project no `Create` call covers are left alone: ABP modules
  # ship hand-written controllers for their app services, and reporting the
  # conventional route as well would invent a second, unreachable endpoint.
  class Abp < Analyzer
    analyzer_for "cs_abp"

    include Common

    SOURCE_GATE = /AppService|ApplicationService|ConventionalControllers|AbpModule/

    # Framework bases (and the marker interfaces) that make a class an
    # application service.
    SERVICE_ROOTS = Set{
      "ApplicationService", "CrudAppService", "ReadOnlyAppService",
      "AbstractKeyCrudAppService", "AbstractKeyReadOnlyAppService",
      "IApplicationService", "IRemoteService",
    }
    SERVICE_INTERFACE_RE = /\AI\w*(?:AppService|ApplicationService)\z/
    CRUD_BASE_RE         = /\b(Crud|ReadOnly|AbstractKeyCrud|AbstractKeyReadOnly)AppService\s*</

    # `ApplicationService.CommonPostfixes`, in ABP's removal order.
    CONTROLLER_POSTFIXES = %w[AppService ApplicationService IntegrationService Service]

    # `HttpMethodHelper.ConventionalPrefixes`; the verb test is a
    # case-insensitive `StartsWith`, anything unmatched is POST.
    VERB_PREFIXES = {
      "GET"    => %w[GetList GetAll Get],
      "PUT"    => %w[Put Update],
      "DELETE" => %w[Delete Remove],
      "POST"   => %w[Create Add Insert Post],
      "PATCH"  => %w[Patch],
    }
    # Verbs whose complex parameters ABP does *not* bind from the body.
    NO_BODY_VERBS = Set{"GET", "DELETE", "HEAD", "TRACE"}

    CREATE_CALL_RE = /ConventionalControllers\s*\.\s*Create\s*\(\s*typeof\s*\(\s*(?:global::)?(?:\w+\.)*(\w+)\s*\)/
    ROOT_PATH_RE   = /\bRootPath\s*=\s*@?"([^"]*)"/
    REMOTE_OFF_RE  = /\bRemoteService(?:Attribute)?\s*\(\s*(?:isEnabled\s*:\s*)?false\b|\bRemoteService(?:Attribute)?\s*\([^)]*\bIsEnabled\s*=\s*false\b/
    NON_ACTION_RE  = /\[\s*NonAction\b/
    HTTP_ATTR_RE   = /\bHttp(Get|Post|Put|Delete|Patch|Head|Options)(?:Attribute)?\s*(?:\(\s*@?"([^"]*)")?/
    ROUTE_ATTR_RE  = /\bRoute(?:Attribute)?\s*\(\s*@?"([^"]*)"/
    METHOD_RE      = /^\s*public\s+(?:(?:virtual|override|async|new|sealed)\s+)*(?!static\b|abstract\b|class\b|record\b|struct\b|interface\b|enum\b|event\b|const\b|delegate\b)[\w<>\[\],.?\s]+?\s+(\w+)\s*(?:<[^()]*>)?\s*\(/

    PRIMITIVE_TYPES = Set{
      "string", "int", "long", "short", "byte", "sbyte", "uint", "ulong", "ushort",
      "bool", "char", "decimal", "double", "float", "Guid", "DateTime",
      "DateTimeOffset", "TimeSpan", "String", "Int32", "Int64", "Boolean",
    }

    # Request DTO bases from `Volo.Abp.Application.Dtos`, which are never in
    # the scanned project.
    ABP_DTO_FIELDS = {
      "PagedAndSortedResultRequestDto"           => %w[Sorting SkipCount MaxResultCount],
      "ExtensiblePagedAndSortedResultRequestDto" => %w[Sorting SkipCount MaxResultCount],
      "PagedResultRequestDto"                    => %w[SkipCount MaxResultCount],
      "ExtensiblePagedResultRequestDto"          => %w[SkipCount MaxResultCount],
      "LimitedResultRequestDto"                  => %w[MaxResultCount],
      "EntityDto"                                => %w[Id],
    }

    private record Method, name : String, params : Array(Tuple(String, String, String)),
      attributes : String, line : Int32, body : String = "", body_line : Int32 = 0, skip_first : Bool = false

    private record Service, type : Noir::CSharpType, file : String, methods : Array(Method)

    private record DtoDef, fields : Array(String), base : String?

    def analyze
      include_callee = callees_needed?
      roots = Common.project_roots(get_files_by_extension(".csproj"))

      all = [] of Tuple(Noir::CSharpType, String, Noir::CSharpLexer)
      creates = [] of Tuple(String, String) # {module type, rootPath}
      files = get_files_by_extension(".cs").reject { |file| Common.csharp_test_path?(base_relative_path(file)) }
      files.each do |file|
        content = read_file_content(file)
        next unless content_matches?(content, SOURCE_GATE)
        lexer = Noir::CSharpLexer.new(content)
        collect_creates(lexer, creates)
        Noir::CSharpTypeExtractor.extract(lexer).each { |type| all << {type, file, lexer} }
      end
      # By simple name, for base-chain and module lookups (first declaration wins).
      classes = {} of String => Tuple(Noir::CSharpType, String, Noir::CSharpLexer)
      all.each { |entry| classes[entry[0].name] ||= entry }
      return @result if creates.empty?

      # Project root (nil = no `.csproj`) → rootPath; an unresolvable module
      # type covers every project. ABP resolves a controller to the *first*
      # setting whose assembly holds it, so a repeated `Create` doesn't add
      # a second route.
      scoped = {} of String? => String
      global = nil
      creates.each do |(module_type, root_path)|
        if entry = classes[module_type]?
          scoped[Common.project_root_for(entry[1], roots)] ||= root_path
        else
          global ||= root_path
        end
      end

      services = [] of Tuple(Service, String)
      wanted = Set(String).new
      all.each do |(type, file, lexer)|
        next unless service?(type, classes)
        root_path = scoped[Common.project_root_for(file, roots)]? || global
        next unless root_path
        declared = collect_methods(type, lexer, include_callee)
        # `CrudAppService<...>` inherits the five CRUD actions unless the body
        # overrides them (an override carrying `[RemoteService(false)]` hides it).
        methods = declared.reject { |m| m.attributes.matches?(REMOTE_OFF_RE) || m.attributes.matches?(NON_ACTION_RE) }
        service = Service.new(type, file, methods + crud_methods(type, declared))
        service.methods.each { |m| m.params.each { |(_, ptype, _)| wanted << ptype unless primitive?(ptype) } }
        services << {service, root_path}
      end

      dtos = build_dto_index(files, wanted)
      services.each { |(service, root_path)| emit_service(service, root_path, dtos, include_callee) }
      @result
    end

    private def collect_creates(lexer : Noir::CSharpLexer, creates : Array(Tuple(String, String)))
      lexer.masked_source.scan(CREATE_CALL_RE) do |match|
        open = lexer.masked_source.index('(', match.begin(0)) || next
        close = lexer.matching_delimiter(open) || next
        call = lexer.code_source[open..close]
        creates << {match[1], ROOT_PATH_RE.match(call).try(&.[1]) || "app"}
      end
    end

    private def service?(type : Noir::CSharpType, classes) : Bool
      return false if type.generic || type.modifiers.includes?("abstract") || type.modifiers.includes?("static")
      return false if type.name.ends_with?("Controller")
      return false if type.attributes.includes?("IntegrationService") # not exposed by default
      return false if type.header.matches?(REMOTE_OFF_RE)

      base = type.base_name
      10.times do
        return false unless base
        return true if SERVICE_ROOTS.includes?(base) || base.matches?(SERVICE_INTERFACE_RE)
        base = classes[base]?.try(&.[0].base_name)
      end
      false
    end

    # Public instance methods declared directly in the class body, each with
    # its attribute lines and parameters `{name, type, binding}`.
    private def collect_methods(type : Noir::CSharpType, lexer : Noir::CSharpLexer, include_callee : Bool) : Array(Method)
      lines = lexer.code_lines
      masked = lexer.masked_lines
      methods = [] of Method
      header_end = type.start_line + type.header.count('\n')
      depth = 0
      bracket = 0 # an attribute list still open from a previous line
      attributes = ""
      i = header_end
      while i <= type.end_line && i < lines.size
        m = masked[i]
        if i > header_end && depth == 1 && !m.blank?
          code = m
          if bracket > 0 || m.lstrip.starts_with?('[')
            column, bracket = attribute_end(m, bracket)
            attributes += lines[i][0, column] + " "
            code = m[column..]
          end
          if bracket == 0 && !code.blank?
            match = METHOD_RE.match(code)
            if match && match[1] != type.name
              signature, sig_end = build_signature(lines, masked, i)
              params = parse_params(extract_balanced_param_list(signature) || "")
              method = Method.new(match[1], params, attributes, i + 1)
              if include_callee
                body, body_line, skip = extract_callable_body(lines, masked, sig_end)
                method = method.copy_with(body: body, body_line: body_line + 1, skip_first: skip)
              end
              methods << method
              (i..sig_end).each { |j| depth += masked[j].count('{') - masked[j].count('}') }
              i = sig_end + 1
              attributes = ""
              next
            end
            attributes = ""
          end
        end
        depth += m.count('{') - m.count('}')
        i += 1
      end
      methods
    end

    # `{column, open brackets}` just past the attribute groups on a masked
    # line, starting `bracket` deep (an attribute list continued from above).
    private def attribute_end(masked : String, bracket : Int32) : Tuple(Int32, Int32)
      masked.each_char_with_index do |char, column|
        case char
        when '[' then bracket += 1
        when ']' then bracket -= 1
        else
          return {column, 0} if bracket <= 0 && !char.ascii_whitespace?
        end
      end
      {masked.size, Math.max(bracket, 0)}
    end

    private def parse_params(list : String) : Array(Tuple(String, String, String))
      split_csharp_parameters(list).compact_map do |raw|
        binding = Common.binding_attribute_type(raw) || ""
        decl = raw.gsub(/\[[^\]]*\]/, "").split('=').first.strip
        parts = decl.split(/\s+/).reject { |word| %w[this params ref out in scoped].includes?(word) }
        next if parts.size < 2
        ptype = parts[0..-2].join.rstrip('?')
        next if binding == "service" || Common.csharp_service_type?(ptype)
        {Common.explicit_binding_name(raw) || parts.last.lstrip('@'), ptype, binding}
      end
    end

    # Enums bind like primitives (ABP's `IsPrimitiveExtended(includeEnums: true)`).
    @enums = Set(String).new

    private def primitive?(type_name : String) : Bool
      name = type_name.split('.').last
      PRIMITIVE_TYPES.includes?(name) || @enums.includes?(name)
    end

    private def emit_service(service : Service, root_path : String, dtos : Hash(String, DtoDef), include_callee : Bool)
      type = service.type
      postfix = CONTROLLER_POSTFIXES.find { |p| type.name.ends_with?(p) && type.name.size > p.size }
      controller = postfix ? type.name.rchop(postfix) : type.name
      base_url = "/api/#{root_path.strip('/')}/#{kebab(controller)}".gsub(%r{/+}, "/")

      emitted = Set(Tuple(String, String)).new
      service.methods.each do |method|
        endpoint = build_endpoint(method, base_url, service.file, dtos)
        next unless emitted.add?({endpoint.method, endpoint.url})
        attach_csharp_callees(endpoint, method.body, service.file, method.body_line, include_callee, skip_first_line: method.skip_first)
        @result << endpoint
      end
    end

    # Generic-argument positions per arity: `{key, list input, create, update}`
    # (nil list input = ABP's `PagedAndSortedResultRequestDto` default).
    CRUD_SHAPES = {
      3 => {2, nil, 1, 1},
      4 => {2, 3, 1, 1},
      5 => {2, 3, 4, 4},
      6 => {2, 3, 4, 5},
      7 => {3, 4, 5, 6},
    }
    READ_ONLY_SHAPES = {3 => {2, nil}, 4 => {2, 3}, 5 => {3, 4}}

    private def crud_methods(type : Noir::CSharpType, declared : Array(Method)) : Array(Method)
      match = CRUD_BASE_RE.match(type.header) || return [] of Method
      args = split_csharp_parameters(generic_arguments(type.header, match.end(0)))
      line = type.start_line + 1
      methods = [] of Method
      if match[1].includes?("ReadOnly")
        key, list = READ_ONLY_SHAPES[args.size]? || return methods
      else
        key, list, create, update = CRUD_SHAPES[args.size]? || return methods
        id = {"id", args[key], ""}
        methods << Method.new("Create", [{"input", args[create], ""}], "", line)
        methods << Method.new("Update", [id, {"input", args[update], ""}], "", line)
        methods << Method.new("Delete", [id], "", line)
      end
      methods << Method.new("Get", [{"id", args[key], ""}], "", line)
      methods << Method.new("GetList", [{"input", list ? args[list] : "PagedAndSortedResultRequestDto", ""}], "", line)
      methods.reject { |m| declared.any? { |d| d.name.rchop("Async") == m.name } }
    end

    # The text between the `<` just before `from` and its matching `>`.
    private def generic_arguments(text : String, from : Int32) : String
      depth = 1
      (from...text.size).each do |i|
        depth += 1 if text[i] == '<'
        depth -= 1 if text[i] == '>'
        return text[from...i] if depth == 0
      end
      ""
    end

    private def build_endpoint(method : Method, base_url : String, file : String, dtos : Hash(String, DtoDef)) : Endpoint
      action = method.name.rchop("Async")
      http_attr = HTTP_ATTR_RE.match(method.attributes)
      verb = http_attr.try(&.[1].upcase) || conventional_verb(action)
      template = http_attr.try(&.[2]?) || ROUTE_ATTR_RE.match(method.attributes).try(&.[1])

      params = [] of Param
      path_names = Set(String).new
      if template && !template.empty?
        url = "/" + template.lchop("~").lstrip('/')
        url.scan(/\{([^}]+)\}/) { |m| path_names << Common.route_placeholder_name(m[1]) }
      else
        url = base_url
        if id = method.params.find { |(name, _, _)| name == "id" }
          # A composite-key DTO contributes one segment per property.
          keys = (dto_fields(id[1], dtos) unless primitive?(id[1])) || [] of String
          keys = ["id"] if keys.empty?
          keys.each { |key| url += "/{#{key}}" }
          path_names.concat(keys)
          path_names << "id"
        end
        rest = remove_verb_prefix(action, verb)
        unless rest.empty?
          url += "/#{kebab(rest)}"
          secondary = method.params.select { |(name, ptype, _)| name.ends_with?("Id") && primitive?(ptype) }
          if secondary.size == 1
            url += "/{#{secondary[0][0]}}"
            path_names << secondary[0][0]
          end
        end
      end

      body_type = NO_BODY_VERBS.includes?(verb) ? "query" : "json"
      url.scan(/\{([^}]+)\}/) { |m| params << Param.new(Common.route_placeholder_name(m[1]), "", "path") }
      method.params.each do |(name, ptype, binding)|
        if path_names.includes?(name)
          next
        elsif !binding.empty?
          params << Param.new(name, "", binding)
        elsif ptype.includes?("RemoteStreamContent")
          params << Param.new(name, "", "form")
        elsif primitive?(ptype)
          params << Param.new(name, "", "query")
        elsif (fields = dto_fields(ptype, dtos)) && !fields.empty?
          fields.each { |field| params << Param.new(field, "", body_type) }
        else
          params << Param.new(name, "", body_type)
        end
      end

      endpoint = Endpoint.new(url, verb, Details.new(PathInfo.new(file, method.line)))
      params.uniq(&.name).each { |param| endpoint.params << param }
      endpoint
    end

    private def conventional_verb(action : String) : String
      VERB_PREFIXES.each do |verb, prefixes|
        return verb if prefixes.any? { |prefix| action.downcase.starts_with?(prefix.downcase) }
      end
      "POST"
    end

    private def remove_verb_prefix(action : String, verb : String) : String
      VERB_PREFIXES[verb]?.try &.each do |prefix|
        return action.lchop(prefix) if action.starts_with?(prefix)
      end
      action
    end

    # ABP's `ToKebabCase`: camelCase the first char, then `aB` → `a-b`.
    private def kebab(name : String) : String
      return name if name.empty?
      (name[0].downcase + name[1..]).gsub(/([a-z])([A-Z])/) { "#{$1}-#{$2.downcase}" }
    end

    private def dto_fields(type_name : String, dtos : Hash(String, DtoDef)) : Array(String)?
      fields = [] of String
      name = type_name.gsub(/<.*>/, "").split('.').last
      found = false
      10.times do
        if known = ABP_DTO_FIELDS[name]?
          fields.concat(known)
          found = true
          break
        end
        dto = dtos[name]? || break
        found = true
        fields.concat(dto.fields)
        name = dto.base || break
      end
      found ? fields : nil
    end

    POSITIONAL_RECORD_RE = /\brecord\s+(?:class\s+|struct\s+)?(\w+)\s*\(([^)]*)\)/
    ENUM_DECL_RE         = /\benum\s+(\w+)/

    # Classes and positional records named by `wanted` (and their local
    # bases), plus the enums among them, read from the files that declare them.
    private def build_dto_index(files : Array(String), wanted : Set(String)) : Hash(String, DtoDef)
      index = {} of String => DtoDef
      pending = wanted.map(&.gsub(/<.*>/, "").split('.').last).to_set
      3.times do
        pending.reject! { |name| index.has_key?(name) || ABP_DTO_FIELDS.has_key?(name) || name.empty? }
        break if pending.empty?
        names_re = /\b(?:class|record|enum)\s+(?:class\s+|struct\s+)?(?:#{pending.map { |name| Regex.escape(name) }.join('|')})\b/
        searched = pending
        pending = Set(String).new
        files.each do |file|
          content = read_file_content(file)
          next unless content_matches?(content, names_re)
          lexer = Noir::CSharpLexer.new(content)
          lines = lexer.code_lines
          Noir::CSharpTypeExtractor.extract(lexer).each do |type|
            next if index.has_key?(type.name) || !searched.includes?(type.name)
            fields = (type.start_line..type.end_line).compact_map { |i| lines[i]?.try { |l| Common::AUTO_PROPERTY_RE.match(l).try(&.[1]) } }
            index[type.name] = DtoDef.new(fields, type.base_name)
            type.base_name.try { |base| pending << base }
          end
          code = lexer.code_source
          code.scan(ENUM_DECL_RE) { |m| @enums << m[1] if searched.includes?(m[1]) }
          code.scan(POSITIONAL_RECORD_RE) do |m|
            next if index.has_key?(m[1]) || !searched.includes?(m[1])
            fields = split_csharp_parameters(m[2]).compact_map { |arg| arg.split('=').first.strip.split(/\s+/).last? }
            index[m[1]] = DtoDef.new(fields, nil)
          end
        end
      end
      index
    end
  end
end
