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
    METHOD_RE      = /^\s*public\s+(?:(?:virtual|override|async|new|sealed)\s+)*(?!static\b|abstract\b|class\b|event\b|const\b|delegate\b)[\w<>\[\],.?\s]+?\s+(\w+)\s*(?:<[^()]*>)?\s*\(/

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
      get_files_by_extension(".cs").each do |file|
        next if Common.csharp_test_path?(base_relative_path(file))
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

      # Project root (nil = no `.csproj`) → rootPaths; an unresolvable module
      # type covers every project.
      scoped = Hash(String?, Array(String)).new { |h, k| h[k] = [] of String }
      global = [] of String
      creates.each do |(module_type, root_path)|
        if entry = classes[module_type]?
          scoped[Common.project_root_for(entry[1], roots)] << root_path
        else
          global << root_path
        end
      end

      services = [] of Tuple(Service, Array(String))
      wanted = Set(String).new
      all.each do |(type, file, lexer)|
        next unless service?(type, classes)
        root_paths = scoped.fetch(Common.project_root_for(file, roots), [] of String) + global
        next if root_paths.empty?
        declared = collect_methods(type, lexer, include_callee)
        # `CrudAppService<...>` inherits the five CRUD actions unless the body
        # overrides them (an override carrying `[RemoteService(false)]` hides it).
        methods = declared.reject { |m| m.attributes.matches?(REMOTE_OFF_RE) || m.attributes.matches?(NON_ACTION_RE) }
        service = Service.new(type, file, methods + crud_methods(type, declared))
        service.methods.each { |m| m.params.each { |(_, ptype, _)| wanted << ptype unless primitive?(ptype) } }
        services << {service, root_paths.uniq}
      end

      dtos = build_dto_index(wanted)
      services.each do |(service, root_paths)|
        root_paths.each { |root_path| emit_service(service, root_path, dtos, include_callee) }
      end
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
      attributes = ""
      i = header_end
      while i <= type.end_line && i < lines.size
        m = masked[i]
        if i > header_end && depth == 1 && !m.blank?
          if m.lstrip.starts_with?('[')
            attributes += lines[i]
          elsif match = METHOD_RE.match(m)
            unless match[1] == type.name
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
          else
            attributes = ""
          end
        end
        depth += m.count('{') - m.count('}')
        i += 1
      end
      methods
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

    private def primitive?(type_name : String) : Bool
      PRIMITIVE_TYPES.includes?(type_name.split('.').last)
    end

    private def emit_service(service : Service, root_path : String, dtos : Hash(String, DtoDef), include_callee : Bool)
      type = service.type
      controller = type.name
      CONTROLLER_POSTFIXES.each do |postfix|
        if controller.ends_with?(postfix) && controller.size > postfix.size
          controller = controller.rchop(postfix)
          break
        end
      end
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
        if method.params.any? { |(name, _, _)| name == "id" }
          url += "/{id}"
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
      method.params.each do |(name, ptype, binding)|
        if path_names.includes?(name)
          params << Param.new(name, "", "path")
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

    # Classes named by `wanted` (and their local bases), read from the files
    # that mention them.
    private def build_dto_index(wanted : Set(String)) : Hash(String, DtoDef)
      index = {} of String => DtoDef
      pending = wanted.map { |name| name.gsub(/<.*>/, "").split('.').last }.to_set
      files = get_files_by_extension(".cs").reject { |f| Common.csharp_test_path?(base_relative_path(f)) }
      3.times do
        pending.reject! { |name| index.has_key?(name) || ABP_DTO_FIELDS.has_key?(name) || name.empty? }
        break if pending.empty?
        names_re = Regex.union(pending.map { |name| /\bclass\s+#{Regex.escape(name)}\b/ })
        searched = pending
        pending = Set(String).new
        files.each do |file|
          content = read_file_content(file)
          next unless content_matches?(content, names_re)
          lexer = Noir::CSharpLexer.new(content)
          lines = lexer.code_lines
          Noir::CSharpTypeExtractor.extract(lexer).each do |type|
            next unless searched.includes?(type.name) && !index.has_key?(type.name)
            fields = (type.start_line..type.end_line).compact_map { |i| lines[i]?.try { |l| Common::AUTO_PROPERTY_RE.match(l).try(&.[1]) } }
            index[type.name] = DtoDef.new(fields, type.base_name)
            type.base_name.try { |base| pending << base }
          end
        end
      end
      index
    end
  end
end
