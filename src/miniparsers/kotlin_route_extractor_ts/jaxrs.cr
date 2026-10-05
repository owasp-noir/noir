# Part of Noir::TreeSitterKotlinRouteExtractor: JAX-RS / Jakarta REST
# resource classes written in Kotlin (plain JAX-RS and Quarkus). Emits
# the same `TreeSitterJaxRsExtractor::Route` the Java walker does, with
# the Java extractor's annotation tables, so the analyzers only pick the
# parser by file extension.
#
# ponytail: same-file sub-resource locators only; `@BeanParam`, interface /
# superclass inheritance and cross-file sub-resources are Java-only so far.
module Noir
  module TreeSitterKotlinRouteExtractor
    alias KotlinDtoIndex = Hash(String, Array(TreeSitterKotlinParameterExtractor::FieldInfo))

    def extract_jaxrs_routes(source : String,
                             dto_index : KotlinDtoIndex = KotlinDtoIndex.new,
                             *,
                             include_callees : Bool = false) : Array(TreeSitterJaxRsExtractor::Route)
      routes = [] of TreeSitterJaxRsExtractor::Route
      Noir::TreeSitter.parse_kotlin(source) do |root|
        routes = extract_jaxrs_routes_from(root, source, dto_index, include_callees: include_callees)
      end
      routes
    end

    def extract_jaxrs_routes_from(root : LibTreeSitter::TSNode,
                                  source : String,
                                  dto_index : KotlinDtoIndex = KotlinDtoIndex.new,
                                  *,
                                  include_callees : Bool = false) : Array(TreeSitterJaxRsExtractor::Route)
      routes = [] of TreeSitterJaxRsExtractor::Route
      constants = expand_constant_interpolations(extract_string_constants(source))
      classes = Hash(String, Tuple(LibTreeSitter::TSNode, Array(ResourceAnnotation))).new
      each_annotated_class(root, source) do |decl, annotations|
        # A `@Path` interface is a MicroProfile REST client (outbound
        # calls), not a resource; the Java walker takes classes only too.
        next if interface_keyword?(decl)
        name = type_identifier_text(decl, source)
        classes[name] ||= {decl, annotations} unless name.empty?
      end

      classes.each do |class_name, (decl, annotations)|
        class_path : String? = nil
        class_consumes : String? = nil
        annotations.each do |(name, args, line)|
          case name
          when "ServerEndpoint"
            if path = annotation_values(args, source, constants, constants).first?
              routes << TreeSitterJaxRsExtractor::Route.new("GET", path, class_name, "", line, nil,
                [] of Param, [] of Tuple(String, Int32), nil, "ws")
            end
          when "Path"
            class_path = annotation_values(args, source, constants, constants).first? || ""
          when "Consumes"
            class_consumes = args && Noir::JvmMediaType.body_format(Noir::TreeSitter.node_text(args, source))
          end
        end
        next unless class_path

        collect_jaxrs_class_routes(decl, class_name, class_path, class_consumes, source, dto_index,
          constants, classes, Set{class_name}, routes, include_callees)
      end
      routes
    end

    # `@ApplicationPath("/api")` on a Kotlin `Application` subclass.
    def extract_jaxrs_application_path_from(root : LibTreeSitter::TSNode, source : String) : String?
      constants = expand_constant_interpolations(extract_string_constants(source))
      application_path : String? = nil
      each_annotated_class(root, source) do |_decl, annotations|
        annotations.each do |(name, args, _line)|
          next unless name == "ApplicationPath"
          application_path ||= annotation_values(args, source, constants, constants).first? || ""
        end
      end
      application_path
    end

    # tree-sitter-kotlin parses `interface Foo` as a `class_declaration`
    # whose keyword token is `interface`. Reading the token, not the text,
    # keeps a class that merely mentions an interface in its body a class.
    private def interface_keyword?(decl : LibTreeSitter::TSNode) : Bool
      return true if Noir::TreeSitter.node_type(decl) == "interface_declaration"
      LibTreeSitter.ts_node_child_count(decl).times do |i|
        case Noir::TreeSitter.node_type(LibTreeSitter.ts_node_child(decl, i.to_u32))
        when "interface"           then return true
        when "class", "class_body" then return false
        end
      end
      false
    end

    private def collect_jaxrs_class_routes(decl : LibTreeSitter::TSNode,
                                           class_name : String,
                                           class_path : String,
                                           class_consumes : String?,
                                           source : String,
                                           dto_index : KotlinDtoIndex,
                                           constants : Hash(String, String),
                                           classes : Hash(String, Tuple(LibTreeSitter::TSNode, Array(ResourceAnnotation))),
                                           visited : Set(String),
                                           routes : Array(TreeSitterJaxRsExtractor::Route),
                                           include_callees : Bool)
      body = class_body(decl)
      return unless body

      Noir::TreeSitter.each_named_child(body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "function_declaration"

        verb : String? = nil
        verb_line = 0
        method_path : String? = nil
        method_consumes : String? = nil
        each_annotation(member, source) do |name, args, line|
          if mapped = TreeSitterJaxRsExtractor::HTTP_VERB_ANNOTATIONS[name]?
            verb ||= mapped
            verb_line = line
          elsif name == "Path"
            method_path = annotation_values(args, source, constants, constants).first? || ""
          elsif name == "Consumes" && args
            method_consumes = Noir::JvmMediaType.body_format(Noir::TreeSitter.node_text(args, source))
          end
        end

        full_path = Noir::URLPath.join_trimmed(class_path, method_path || "")
        consumes = method_consumes || class_consumes

        unless verb
          # A `@Path` method without a verb is a sub-resource locator: its
          # return type's routes hang under this method's path.
          next unless method_path
          sub_name = function_return_type_name(member, source)
          next unless (sub = classes[sub_name]?) && visited.add?(sub_name)
          collect_jaxrs_class_routes(sub[0], sub_name, full_path, consumes, source, dto_index,
            constants, classes, visited, routes, include_callees)
          visited.delete(sub_name)
          next
        end

        params = jaxrs_params(member, source, consumes, dto_index, constants)
        callees = include_callees ? function_callees(member, source) : [] of Tuple(String, Int32)
        routes << TreeSitterJaxRsExtractor::Route.new(verb, full_path, class_name, function_name(member, source),
          verb_line, consumes, params, callees)
      end
    end

    private def jaxrs_params(func : LibTreeSitter::TSNode,
                             source : String,
                             consumes : String?,
                             dto_index : KotlinDtoIndex,
                             constants : Hash(String, String)) : Array(Param)
      params = [] of Param
      each_function_parameter(func, source) do |param_name, type_node, annotations|
        skip = false
        bound_format : String? = nil
        bound_name = ""
        default_value = ""
        annotations.each do |(name, args, _line)|
          if TreeSitterJaxRsExtractor::PATH_PARAM_ANNOTATIONS.includes?(name) ||
             {"BeanParam", "Context", "Suspended"}.includes?(name)
            skip = true
          elsif name == "DefaultValue"
            default_value = annotation_values(args, source, constants, constants).first? || ""
          elsif format = TreeSitterJaxRsExtractor::PARAM_ANNOTATION_FORMAT[name]?
            bound_format = format
            bound_name = annotation_values(args, source, constants, constants).first? || ""
          end
        end
        next if skip

        if format = bound_format
          params << Param.new(bound_name.presence || param_name, default_value, format)
          next
        end

        # Un-annotated parameter: the request entity.
        type_name = resource_type_name(type_node, source)
        lower = type_name.downcase
        next if KOTLIN_SCALAR_TYPES.includes?(lower) || TreeSitterJaxRsExtractor::INJECTED_PARAM_TYPES.includes?(lower)
        if TreeSitterJaxRsExtractor::MULTIPART_FORM_PARAM_TYPES.includes?(lower)
          params << Param.new(param_name, "", "form")
          next
        end
        format = consumes || "json"
        params.concat(dto_body_params(type_name, dto_index, format) || [Param.new(param_name, type_name, format)])
      end
      params
    end
  end
end
