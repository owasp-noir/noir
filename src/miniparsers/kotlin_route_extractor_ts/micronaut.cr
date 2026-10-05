# Part of Noir::TreeSitterKotlinRouteExtractor: Micronaut `@Controller`
# classes written in Kotlin. Emits the same
# `TreeSitterMicronautExtractor::Route` the Java walker does, with its
# annotation tables and URI-template handling.
#
# ponytail: routes inherited from a non-`@Controller` API interface are
# Java-only so far.
module Noir
  module TreeSitterKotlinRouteExtractor
    # `Flow<Book>` is the coroutine spelling of `Publisher<Book>`.
    MICRONAUT_BODY_WRAPPER_TYPES = TreeSitterMicronautExtractor::REACTIVE_BODY_WRAPPER_TYPES | Set{"flow"}

    def extract_micronaut_routes(source : String,
                                 dto_index : KotlinDtoIndex = KotlinDtoIndex.new,
                                 *,
                                 include_callees : Bool = false) : Array(TreeSitterMicronautExtractor::Route)
      routes = [] of TreeSitterMicronautExtractor::Route
      Noir::TreeSitter.parse_kotlin(source) do |root|
        routes = extract_micronaut_routes_from(root, source, dto_index, include_callees: include_callees)
      end
      routes
    end

    def extract_micronaut_routes_from(root : LibTreeSitter::TSNode,
                                      source : String,
                                      dto_index : KotlinDtoIndex = KotlinDtoIndex.new,
                                      *,
                                      include_callees : Bool = false) : Array(TreeSitterMicronautExtractor::Route)
      routes = [] of TreeSitterMicronautExtractor::Route
      constants = expand_constant_interpolations(extract_string_constants(source))
      each_annotated_class(root, source) do |decl, annotations|
        collect_micronaut_class_routes(decl, annotations, source, dto_index, constants, routes, include_callees)
      end
      routes
    end

    private def collect_micronaut_class_routes(decl : LibTreeSitter::TSNode,
                                               annotations : Array(ResourceAnnotation),
                                               source : String,
                                               dto_index : KotlinDtoIndex,
                                               constants : Hash(String, String),
                                               routes : Array(TreeSitterMicronautExtractor::Route),
                                               include_callees : Bool)
      class_name = type_identifier_text(decl, source)
      controller_paths : Array(String)? = nil
      class_consumes : String? = nil
      annotations.each do |(name, args, line)|
        case name
        when "ServerWebSocket"
          paths = annotation_values(args, source, constants, constants)
          (paths.empty? ? ["/ws"] : paths).each do |path|
            routes << TreeSitterMicronautExtractor::Route.new("GET", path, class_name, "", line,
              [] of Param, [] of Tuple(String, Int32), "ws")
          end
        when "Controller"
          paths = annotation_values(args, source, constants, constants)
          controller_paths = paths.empty? ? [""] : paths
        when "Consumes"
          class_consumes = args && Noir::JvmMediaType.body_format(Noir::TreeSitter.node_text(args, source))
        end
      end
      # A class-level `@Controller` is what makes a class a Micronaut
      # endpoint host; verb-annotated helpers elsewhere are not routes.
      return unless controller_paths
      body = class_body(decl)
      return unless body

      Noir::TreeSitter.each_named_child(body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "function_declaration"

        verb : String? = nil
        verb_line = 0
        verb_args : LibTreeSitter::TSNode? = nil
        method_consumes : String? = nil
        each_annotation(member, source) do |name, args, line|
          if verb.nil? && (mapped = micronaut_verb(name, args, source, constants))
            verb = mapped
            verb_line = line
            verb_args = args
          elsif name == "Consumes" && args
            method_consumes = Noir::JvmMediaType.body_format(Noir::TreeSitter.node_text(args, source))
          end
        end
        next unless verb

        method_paths = annotation_values(verb_args, source, constants, constants, {"value", "uri", "uris"})
        method_paths = [""] if method_paths.empty?
        consumes = method_consumes || micronaut_consumes_argument(verb_args, source) || class_consumes
        callees = include_callees ? function_callees(member, source) : [] of Tuple(String, Int32)
        method_name = function_name(member, source)

        controller_paths.each do |class_path|
          method_paths.each do |method_path|
            full_path = Noir::URLPath.join_trimmed(class_path, method_path)
            normalized_path = TreeSitterMicronautExtractor.strip_uri_template_query(full_path)
            query_vars = TreeSitterMicronautExtractor.uri_template_query_vars(full_path)
            path_vars = TreeSitterMicronautExtractor.uri_template_path_vars(normalized_path)
            params = micronaut_params(member, source, consumes, dto_index, constants, query_vars, path_vars)
            routes << TreeSitterMicronautExtractor::Route.new(verb, normalized_path, class_name, method_name,
              verb_line, params, callees)
          end
        end
      end
    end

    private def micronaut_verb(name : String,
                               args : LibTreeSitter::TSNode?,
                               source : String,
                               constants : Hash(String, String)) : String?
      if mapped = TreeSitterMicronautExtractor::HTTP_VERB_ANNOTATIONS[name]?
        return mapped
      end
      return unless name == "CustomHttpMethod"
      annotation_values(args, source, constants, constants, {"method"}, positional: false).first?.try(&.upcase)
    end

    # `@Post(consumes = [MediaType.APPLICATION_FORM_URLENCODED])`
    private def micronaut_consumes_argument(args : LibTreeSitter::TSNode?, source : String) : String?
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        kind, key, value = classify_value_argument(arg, source)
        next unless kind == :keyword && {"consumes", "processes"}.includes?(key) && value
        if format = Noir::JvmMediaType.body_format(Noir::TreeSitter.node_text(value, source))
          return format
        end
      end
      nil
    end

    private def micronaut_params(func : LibTreeSitter::TSNode,
                                 source : String,
                                 consumes : String?,
                                 dto_index : KotlinDtoIndex,
                                 constants : Hash(String, String),
                                 query_vars : Array(String),
                                 path_vars : Array(String)) : Array(Param)
      params = [] of Param
      bound_names = [] of String
      each_function_parameter(func, source) do |param_name, type_node, annotations|
        bound_names << param_name
        type_name = resource_type_name(type_node, source, MICRONAUT_BODY_WRAPPER_TYPES)
        body_name : String? = nil
        handled = false
        annotations.each do |(name, args, _line)|
          case name
          when "PathVariable"
            handled = true
          when "Body"
            body_name = annotation_values(args, source, constants, constants, {"value"}).first? || ""
          when "RequestBean"
            handled = true
            params.concat(dto_body_params(type_name, dto_index, "query") || [Param.new(param_name, type_name, "query")])
          else
            if format = TreeSitterMicronautExtractor::PARAM_ANNOTATION_FORMAT[name]?
              handled = true
              bound = annotation_values(args, source, constants, constants, {"value", "name"}).first? || ""
              default_value = annotation_values(args, source, constants, constants, {"defaultValue"}, positional: false).first? || ""
              params << Param.new(bound.presence || param_name, default_value, format)
            end
          end
        end
        next if handled
        next if path_vars.includes?(param_name)

        if query_vars.includes?(param_name)
          params.concat(dto_body_params(type_name, dto_index, "query") || [Param.new(param_name, "", "query")])
          next
        end

        # `@Body` and un-annotated complex parameters both bind the body.
        format = consumes || "json"
        name = body_name.try(&.presence) || param_name
        lower = type_name.downcase
        if KOTLIN_SCALAR_TYPES.includes?(lower)
          params << Param.new(name, "", format) if body_name
          next
        end
        next if TreeSitterMicronautExtractor::INJECTED_PARAM_TYPES.includes?(lower)
        if format == "form" && TreeSitterMicronautExtractor::FORM_FILE_PARAM_TYPES.includes?(lower)
          params << Param.new(name, "", "form")
          next
        end
        params.concat(dto_body_params(type_name, dto_index, format) || [Param.new(name, type_name, format)])
      end
      TreeSitterMicronautExtractor.merge_query_template_params(params, query_vars.reject { |var| bound_names.includes?(var) })
      params
    end
  end
end
