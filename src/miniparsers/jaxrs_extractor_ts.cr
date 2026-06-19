require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "./java_callee_extractor"
require "./java_parameter_extractor_ts"
require "./java_route_extractor_ts"
require "./import_graph"

module Noir
  # Tree-sitter-backed JAX-RS / Jakarta REST extractor.
  #
  # Walks `@Path` resource classes and emits one `Endpoint`-shaped
  # `Route` per HTTP-method-annotated method. Recognises:
  #
  #   * Class-level `@ServerEndpoint("/x")` — surfaced as `GET`
  #     with `protocol = "ws"`.
  #   * Application-level `@ApplicationPath("/api")` for analyzer
  #     adapters that need to prefix resource routes.
  #   * Class-level `@Path("/x")` — joined onto each method's path
  #     (or `@Path("/sub")` if the method has one).
  #   * Verb annotations: `@GET`, `@POST`, `@PUT`, `@DELETE`,
  #     `@PATCH`, `@HEAD`, `@OPTIONS`.
  #   * `@Consumes(MediaType.APPLICATION_*)` at class or method level
  #     to set the body parameter format. Method-level wins.
  #   * Parameter annotations: `@PathParam` (skipped — URL carries
  #     it), `@QueryParam`, `@HeaderParam`, `@CookieParam`,
  #     `@FormParam`, plus `@DefaultValue("x")` modifier.
  #   * `@BeanParam` — expands the bean class's
  #     JAX-RS-annotated fields as parameters with the right
  #     param_type, looked up via `Noir::TreeSitterJavaDtoIndex`-style
  #     cross-file resolution.
  #   * Un-annotated, non-primitive parameters — treated as the
  #     request body and expanded against a caller-supplied DTO
  #     index (same pipeline as Spring's `@RequestBody`).
  #
  # Out of scope for this first cut: meta-annotations,
  # `@MatrixParam`.
  module TreeSitterJaxRsExtractor
    extend self

    # JAX-RS HTTP-method annotations. Simple names are matched; the
    # walker normalises any package-qualified prefix to the trailing
    # segment.
    HTTP_VERB_ANNOTATIONS = {
      "GET"     => "GET",
      "POST"    => "POST",
      "PUT"     => "PUT",
      "DELETE"  => "DELETE",
      "PATCH"   => "PATCH",
      "HEAD"    => "HEAD",
      "OPTIONS" => "OPTIONS",
    }

    # Both standard JAX-RS names and Quarkus's `@Rest*` aliases map
    # to the same param formats. Listing both here keeps the
    # Quarkus analyzer a thin detector layer on top of this extractor.
    PARAM_ANNOTATION_FORMAT = {
      "QueryParam"  => "query",
      "HeaderParam" => "header",
      "CookieParam" => "cookie",
      "FormParam"   => "form",
      "RestQuery"   => "query",
      "RestHeader"  => "header",
      "RestCookie"  => "cookie",
      "RestForm"    => "form",
    }

    # `@PathParam` skip-list — Quarkus's `@RestPath` is a drop-in
    # alias for the same role. Both are URL-carried and never emitted
    # as request parameters.
    PATH_PARAM_ANNOTATIONS = Set{"PathParam", "RestPath"}

    # Java primitive type names (lowercased). Anything else with no
    # parameter annotation gets treated as a request-body DTO.
    PRIMITIVE_TYPES = Set{
      "boolean", "byte", "char", "short", "int", "long",
      "float", "double", "void", "string", "object",
      "integer", "character",
    }

    # Framework-provided method parameters that can be injected by
    # type in RESTEasy Reactive / Quarkus or are commonly carried by
    # JAX-RS/Servlet `@Context` / `@Suspended`. These are never
    # request bodies.
    INJECTED_PARAM_TYPES = Set{
      "routingcontext", "httpserverrequest", "httpserverresponse",
      "containerrequestcontext", "containerresponsecontext",
      "securitycontext", "uriinfo", "httpheaders", "resourcecontext",
      "providers", "sse", "sseeventsink", "asyncresponse",
      "httpservletrequest", "httpservletresponse",
      "servletrequest", "servletresponse",
      "securityidentity", "jsonwebtoken",
    }

    MULTIPART_FORM_PARAM_TYPES = Set{
      "multipartformdatainput", "multipartinput", "formdatamultipart",
    }

    alias SourceEntry = Tuple(String, String) # file_path, source

    struct Route
      getter verb : String
      getter path : String
      getter class_name : String
      getter method_name : String
      getter line : Int32
      getter parameter_format : String?
      getter params : Array(Param)
      getter callees : Array(Tuple(String, Int32))
      getter file_path : String?
      getter protocol : String

      def initialize(@verb, @path, @class_name, @method_name, @line,
                     @parameter_format, @params, @callees, @file_path = nil, @protocol = "http")
      end
    end

    # Public entry point — walks `source` and returns one `Route`
    # per JAX-RS endpoint defined in `path`'s file. `dto_index` maps
    # `class_name → fields` for cross-file body / `@BeanParam`
    # expansion (typically built via `TreeSitterJavaDtoIndex`).
    def extract_routes(source : String,
                       dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)) = {} of String => Array(TreeSitterJavaParameterExtractor::FieldInfo),
                       bean_index : Hash(String, Array(Param)) = {} of String => Array(Param),
                       subresource_sources : Hash(String, SourceEntry) = {} of String => SourceEntry,
                       *,
                       include_callees : Bool = false) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_java(source) do |root|
        routes.concat(extract_routes_from(root, source, dto_index, bean_index, subresource_sources, include_callees: include_callees))
      end
      routes
    end

    # Same as `extract_routes`, but reuses a Java tree-sitter root the
    # caller already parsed. Analyzer adapters use this when they also
    # need to attach method-body callees without reparsing the file.
    def extract_routes_from(root : LibTreeSitter::TSNode,
                            source : String,
                            dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)) = {} of String => Array(TreeSitterJavaParameterExtractor::FieldInfo),
                            bean_index : Hash(String, Array(Param)) = {} of String => Array(Param),
                            subresource_sources : Hash(String, SourceEntry) = {} of String => SourceEntry,
                            *,
                            include_callees : Bool = false) : Array(Route)
      routes = [] of Route
      classes = collect_classes(root, source)
      constants = TreeSitterJavaRouteExtractor.extract_string_constants_from(root, source)
      classes.each_value do |decl|
        next unless Noir::TreeSitter.node_type(decl) == "class_declaration"
        class_name = type_identifier_text(decl, source)
        collect_server_endpoint_route(decl, source, routes, constants, class_name)
        next unless annotation_string_value(decl, "Path", source, constants, class_name)
        collect_class_routes(decl, source, dto_index, bean_index, routes, include_callees,
          class_index: classes, constants: constants, subresource_sources: subresource_sources)
      end
      routes
    end

    private def collect_server_endpoint_route(decl : LibTreeSitter::TSNode,
                                              source : String,
                                              routes : Array(Route),
                                              constants : Hash(String, String),
                                              class_name : String)
      endpoint_path = annotation_string_value(decl, "ServerEndpoint", source, constants, class_name)
      return unless endpoint_path

      line = annotation_line(decl, "ServerEndpoint", source) || Noir::TreeSitter.node_start_row(decl)
      routes << Route.new("GET", endpoint_path, class_name, "", line, nil,
        [] of Param, [] of Tuple(String, Int32), nil, "ws")
    end

    def extract_class_names(source : String) : Array(String)
      Noir::TreeSitter.parse_java(source) do |root|
        return extract_class_names_from(root, source)
      end
      [] of String
    end

    def extract_class_names_from(root : LibTreeSitter::TSNode, source : String) : Array(String)
      collect_classes(root, source).keys
    end

    def extract_application_path(source : String) : String?
      result : String? = nil
      Noir::TreeSitter.parse_java(source) do |root|
        result = extract_application_path_from(root, source)
      end
      result
    end

    def extract_application_path_from(root : LibTreeSitter::TSNode, source : String) : String?
      constants = TreeSitterJavaRouteExtractor.extract_string_constants_from(root, source)
      collect_classes(root, source).each_value do |decl|
        class_name = type_identifier_text(decl, source)
        if path = annotation_string_value(decl, "ApplicationPath", source, constants, class_name)
          return path
        end
      end
      nil
    end

    # Read JAX-RS-annotated fields (`@QueryParam`, `@HeaderParam`,
    # ...) from every class in the file as `{class_name => Params}`.
    # Used to power `@BeanParam` expansion across files.
    def extract_bean_fields(source : String) : Hash(String, Array(Param))
      Noir::TreeSitter.parse_java(source) do |root|
        return extract_bean_fields_from(root, source)
      end
      Hash(String, Array(Param)).new
    end

    def extract_bean_fields_from(root : LibTreeSitter::TSNode, source : String) : Hash(String, Array(Param))
      results = Hash(String, Array(Param)).new
      constants = TreeSitterJavaRouteExtractor.extract_string_constants_from(root, source)
      walk_classes(root) do |decl|
        name = type_identifier_text(decl, source)
        next if name.empty?
        params = collect_bean_params(decl, source, constants, name)
        results[name] = params unless params.empty?
      end
      results
    end

    # ---- private ------------------------------------------------------

    private def collect_classes(root : LibTreeSitter::TSNode, source : String) : Hash(String, LibTreeSitter::TSNode)
      classes = Hash(String, LibTreeSitter::TSNode).new
      walk_classes(root) do |decl|
        name = type_identifier_text(decl, source)
        classes[name] ||= decl unless name.empty?
      end
      classes
    end

    private def walk_classes(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      ty = Noir::TreeSitter.node_type(node)
      block.call(node) if ty == "class_declaration" || ty == "interface_declaration"
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_classes(child, &block)
      end
    end

    private def type_identifier_text(decl : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.each_named_child(decl) do |child|
        if Noir::TreeSitter.node_type(child) == "identifier"
          return Noir::TreeSitter.node_text(child, source)
        end
      end
      ""
    end

    private def collect_class_routes(decl : LibTreeSitter::TSNode,
                                     source : String,
                                     dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)),
                                     bean_index : Hash(String, Array(Param)),
                                     routes : Array(Route),
                                     include_callees : Bool = false,
                                     base_path : String? = nil,
                                     inherited_consumes : String? = nil,
                                     class_index : Hash(String, LibTreeSitter::TSNode)? = nil,
                                     constants : Hash(String, String)? = nil,
                                     subresource_sources : Hash(String, SourceEntry) = {} of String => SourceEntry,
                                     current_file : String? = nil,
                                     visited : Set(String)? = nil,
                                     method_excludes : Set(String) = Set(String).new)
      class_name = type_identifier_text(decl, source)
      local_constants = constants || TreeSitterJavaRouteExtractor.extract_string_constants(source)
      own_class_path = annotation_string_value(decl, "Path", source, local_constants, class_name) || ""
      class_path = base_path || own_class_path
      class_consumes = consumes_format(decl, source) || inherited_consumes
      local_class_index = class_index || collect_classes(decl, source)
      local_visited = visited || Set(String).new
      visit_key = "#{class_name}@#{class_path}"
      return if local_visited.includes?(visit_key)
      local_visited.add(visit_key)

      body = class_body_node(decl)
      return unless body

      Noir::TreeSitter.each_named_child(body) do |member|
        ty = Noir::TreeSitter.node_type(member)
        next unless ty == "method_declaration"

        verb_node = nil
        verb : String? = nil
        each_annotation(member, source) do |ann_name, _, ann|
          if mapped = HTTP_VERB_ANNOTATIONS[ann_name]?
            verb = mapped
            verb_node = ann
            break
          end
        end

        method_name = method_name_of(member, source) || ""
        method_path = annotation_string_value(member, "Path", source, local_constants, class_name) || ""

        full_path = join_paths(class_path, method_path)
        method_consumes = consumes_format(member, source) || class_consumes

        unless verb && verb_node
          next if method_excludes.includes?(method_name)
          next if method_path.empty?
          return_type = method_return_type(member, source)
          next if return_type.empty?
          if subresource = local_class_index[return_type]?
            collect_class_routes(subresource, source, dto_index, bean_index, routes, include_callees,
              base_path: full_path, inherited_consumes: method_consumes, class_index: local_class_index,
              constants: local_constants, subresource_sources: subresource_sources, current_file: current_file,
              visited: local_visited)
          elsif source_entry = subresource_sources[return_type]?
            subresource_path, subresource_source = source_entry
            collect_cross_file_subresource(return_type, subresource_path, subresource_source,
              full_path, method_consumes, dto_index, bean_index, routes, include_callees,
              subresource_sources, local_visited)
          end
          next
        end

        next if method_excludes.includes?(method_name)
        params = collect_method_params(member, source, verb, method_consumes,
          dto_index, bean_index, local_constants, class_name)

        line = Noir::TreeSitter.node_start_row(verb_node)
        callees = include_callees ? collect_method_callees(member, source) : [] of Tuple(String, Int32)
        routes << Route.new(verb, full_path, class_name, method_name, line,
          method_consumes, params, callees, current_file)
      end

      collect_implemented_interface_routes(decl, source, class_path, class_consumes,
        dto_index, bean_index, routes, include_callees, local_class_index,
        local_constants, subresource_sources, current_file, local_visited)
    end

    private def collect_implemented_interface_routes(decl : LibTreeSitter::TSNode,
                                                     source : String,
                                                     class_path : String,
                                                     class_consumes : String?,
                                                     dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)),
                                                     bean_index : Hash(String, Array(Param)),
                                                     routes : Array(Route),
                                                     include_callees : Bool,
                                                     class_index : Hash(String, LibTreeSitter::TSNode),
                                                     constants : Hash(String, String),
                                                     subresource_sources : Hash(String, SourceEntry),
                                                     current_file : String?,
                                                     visited : Set(String))
      return unless Noir::TreeSitter.node_type(decl) == "class_declaration"

      implemented_names = implemented_interface_names(decl, source)
      return if implemented_names.empty?

      method_excludes = jaxrs_annotated_method_names(decl, source)
      implemented_names.each do |interface_name|
        if interface_decl = class_index[interface_name]?
          interface_path = annotation_string_value(interface_decl, "Path", source, constants, interface_name) || ""
          collect_class_routes(interface_decl, source, dto_index, bean_index, routes, include_callees,
            base_path: join_paths(class_path, interface_path), inherited_consumes: class_consumes,
            class_index: class_index, constants: constants, subresource_sources: subresource_sources,
            current_file: current_file, visited: visited, method_excludes: method_excludes)
        elsif source_entry = subresource_sources[interface_name]?
          interface_source_path, interface_source = source_entry
          collect_cross_file_interface(interface_name, interface_source_path, interface_source,
            class_path, class_consumes, dto_index, bean_index, routes, include_callees,
            subresource_sources, visited, method_excludes)
        end
      end
    end

    private def collect_cross_file_interface(interface_name : String,
                                             interface_path : String,
                                             interface_source : String,
                                             class_path : String,
                                             class_consumes : String?,
                                             dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)),
                                             bean_index : Hash(String, Array(Param)),
                                             routes : Array(Route),
                                             include_callees : Bool,
                                             subresource_sources : Hash(String, SourceEntry),
                                             visited : Set(String),
                                             method_excludes : Set(String))
      Noir::TreeSitter.parse_java(interface_source) do |root|
        classes = collect_classes(root, interface_source)
        interface_decl = classes[interface_name]?
        next unless interface_decl
        constants = TreeSitterJavaRouteExtractor.extract_string_constants_from(root, interface_source)
        own_path = annotation_string_value(interface_decl, "Path", interface_source, constants, interface_name) || ""
        collect_class_routes(interface_decl, interface_source, dto_index, bean_index, routes, include_callees,
          base_path: join_paths(class_path, own_path), inherited_consumes: class_consumes,
          class_index: classes, constants: constants, subresource_sources: subresource_sources,
          current_file: interface_path, visited: visited, method_excludes: method_excludes)
      end
    end

    private def collect_cross_file_subresource(return_type : String,
                                               subresource_path : String,
                                               subresource_source : String,
                                               base_path : String,
                                               inherited_consumes : String?,
                                               dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)),
                                               bean_index : Hash(String, Array(Param)),
                                               routes : Array(Route),
                                               include_callees : Bool,
                                               subresource_sources : Hash(String, SourceEntry),
                                               visited : Set(String))
      Noir::TreeSitter.parse_java(subresource_source) do |root|
        classes = collect_classes(root, subresource_source)
        subresource = classes[return_type]?
        next unless subresource
        constants = TreeSitterJavaRouteExtractor.extract_string_constants_from(root, subresource_source)
        collect_class_routes(subresource, subresource_source, dto_index, bean_index, routes, include_callees,
          base_path: base_path, inherited_consumes: inherited_consumes, class_index: classes,
          constants: constants, subresource_sources: subresource_sources, current_file: subresource_path,
          visited: visited)
      end
    end

    private def method_return_type(method : LibTreeSitter::TSNode, source : String) : String
      if type_node = Noir::TreeSitter.field(method, "type")
        return class_return_type(type_node, source)
      end

      Noir::TreeSitter.each_named_child(method) do |child|
        case Noir::TreeSitter.node_type(child)
        when "type_identifier", "generic_type", "scoped_type_identifier"
          return class_return_type(child, source)
        end
      end
      ""
    end

    private def class_return_type(type_node : LibTreeSitter::TSNode, source : String) : String
      text = Noir::TreeSitter.node_text(type_node, source)
      if match = text.match(/\bClass\s*<\s*([A-Za-z_][A-Za-z0-9_]*)\s*>/)
        return match[1]
      end

      leaf_type_name(type_node, source)
    end

    private def collect_method_callees(method : LibTreeSitter::TSNode,
                                       source : String) : Array(Tuple(String, Int32))
      body = Noir::TreeSitter.field(method, "body")
      return [] of Tuple(String, Int32) unless body

      Noir::JavaCalleeExtractor.callees_in_body(body, source, "").map do |name, _path, line|
        {name, line}
      end
    end

    private def class_body_node(decl : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(decl) do |child|
        return child if Noir::TreeSitter.node_type(child) == "class_body" ||
                        Noir::TreeSitter.node_type(child) == "interface_body"
      end
      nil
    end

    private def method_name_of(method : LibTreeSitter::TSNode, source : String) : String?
      Noir::TreeSitter.each_named_child(method) do |child|
        return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "identifier"
      end
      nil
    end

    private def jaxrs_annotated_method_names(decl : LibTreeSitter::TSNode, source : String) : Set(String)
      names = Set(String).new
      body = class_body_node(decl)
      return names unless body

      Noir::TreeSitter.each_named_child(body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "method_declaration"
        next unless method_has_jaxrs_binding?(member, source)
        name = method_name_of(member, source)
        names << name if name
      end
      names
    end

    private def method_has_jaxrs_binding?(method : LibTreeSitter::TSNode, source : String) : Bool
      each_annotation(method, source) do |name, _, _|
        return true if name == "Path" || name == "Consumes" || HTTP_VERB_ANNOTATIONS.has_key?(name)
      end
      false
    end

    private def implemented_interface_names(class_decl : LibTreeSitter::TSNode, source : String) : Array(String)
      header = Noir::TreeSitter.node_text(class_decl, source)
      if body_start = header.index('{')
        header = header[...body_start]
      end

      match = header.match(/\bimplements\s+(.+)\z/m)
      return [] of String unless match

      names = split_top_level_commas(match[1]).compact_map do |raw|
        type_name = strip_generic_arguments(raw.strip)
        next if type_name.empty?
        type_name = type_name.split(/\s+/).first? || type_name
        if idx = type_name.rindex('.')
          type_name[(idx + 1)..]
        else
          type_name
        end
      end
      names.uniq!
      names
    end

    private def split_top_level_commas(text : String) : Array(String)
      parts = [] of String
      start = 0
      depth = 0
      text.each_char_with_index do |char, index|
        case char
        when '<'
          depth += 1
        when '>'
          depth -= 1 if depth > 0
        when ','
          if depth == 0
            parts << text[start...index]
            start = index + 1
          end
        end
      end
      parts << text[start..]
      parts
    end

    private def strip_generic_arguments(text : String) : String
      String.build do |io|
        depth = 0
        text.each_char do |char|
          case char
          when '<'
            depth += 1
          when '>'
            depth -= 1 if depth > 0
          else
            io << char if depth == 0
          end
        end
      end.strip
    end

    # ---- annotation helpers ------------------------------------------

    private def each_annotation(decl : LibTreeSitter::TSNode, source : String, &)
      Noir::TreeSitter.each_named_child(decl) do |child|
        case Noir::TreeSitter.node_type(child)
        when "modifiers"
          Noir::TreeSitter.each_named_child(child) do |ann|
            ty = Noir::TreeSitter.node_type(ann)
            next unless ty == "annotation" || ty == "marker_annotation"
            name = annotation_simple_name(ann, source)
            args = annotation_args_node(ann)
            yield name, args, ann
          end
        end
      end
    end

    private def annotation_simple_name(ann : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.each_named_child(ann) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier", "scoped_identifier"
          full = Noir::TreeSitter.node_text(child, source)
          return last_segment(full)
        end
      end
      ""
    end

    private def last_segment(text : String) : String
      if idx = text.rindex('.')
        text[(idx + 1)..]
      else
        text
      end
    end

    private def annotation_args_node(ann : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(ann) do |child|
        return child if Noir::TreeSitter.node_type(child) == "annotation_argument_list"
      end
      nil
    end

    private def annotation_line(decl : LibTreeSitter::TSNode, ann_name : String, source : String) : Int32?
      result : Int32? = nil
      each_annotation(decl, source) do |name, _, ann|
        next unless name == ann_name
        result = Noir::TreeSitter.node_start_row(ann)
      end
      result
    end

    # `@Path("/x")` / `@Path(value = "/x")` / `@Path(Constants.X)` —
    # return the resolved string. Skip if the annotation isn't found
    # or value isn't statically resolvable.
    private def annotation_string_value(decl : LibTreeSitter::TSNode,
                                        ann_name : String,
                                        source : String,
                                        constants : Hash(String, String) = Hash(String, String).new,
                                        current_class : String = "") : String?
      result : String? = nil
      each_annotation(decl, source) do |name, args, _|
        next unless name == ann_name
        next unless args
        Noir::TreeSitter.each_named_child(args) do |child|
          case Noir::TreeSitter.node_type(child)
          when "string_literal", "identifier", "field_access", "scoped_identifier", "binary_expression", "parenthesized_expression"
            result = resolve_path_value(child, source, constants, current_class)
          when "element_value_pair"
            key = Noir::TreeSitter.field(child, "key")
            value = Noir::TreeSitter.field(child, "value")
            if key && value && Noir::TreeSitter.node_text(key, source) == "value"
              result = resolve_path_value(value, source, constants, current_class)
            end
          end
        end
      end
      result
    end

    private def resolve_path_value(node : LibTreeSitter::TSNode,
                                   source : String,
                                   constants : Hash(String, String),
                                   current_class : String = "",
                                   depth = 0) : String?
      return if depth > 16

      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        decode_string_literal(node, source)
      when "identifier"
        text = Noir::TreeSitter.node_text(node, source)
        constants["#{current_class}.#{text}"]? || constants[text]?
      when "field_access", "scoped_identifier"
        constants[Noir::TreeSitter.node_text(node, source)]?
      when "binary_expression"
        return unless Noir::TreeSitter.node_text(node, source).includes?("+")
        left = Noir::TreeSitter.field(node, "left")
        right = Noir::TreeSitter.field(node, "right")
        return unless left && right
        left_value = resolve_path_value(left, source, constants, current_class, depth + 1)
        right_value = resolve_path_value(right, source, constants, current_class, depth + 1)
        return unless left_value && right_value
        "#{left_value}#{right_value}"
      when "parenthesized_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          if value = resolve_path_value(child, source, constants, current_class, depth + 1)
            return value
          end
        end
      end
    end

    # `@Consumes(MediaType.APPLICATION_FORM_URLENCODED)` →
    # "form" / "json" / nil. Same shape as Spring's helper.
    private def consumes_format(decl : LibTreeSitter::TSNode, source : String) : String?
      result : String? = nil
      each_annotation(decl, source) do |name, args, _|
        next unless name == "Consumes"
        next unless args
        text = Noir::TreeSitter.node_text(args, source)
        if text.includes?("APPLICATION_FORM_URLENCODED") || text.includes?("application/x-www-form-urlencoded")
          result = "form"
        elsif text.includes?("APPLICATION_JSON") || text.includes?("application/json")
          result = "json"
        elsif text.includes?("MULTIPART_FORM_DATA") || text.includes?("multipart/form-data")
          result = "form"
        end
      end
      result
    end

    private def decode_string_literal(node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "string_fragment"
            io << Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      return buf unless buf.empty?
      raw = Noir::TreeSitter.node_text(node, source)
      raw.size >= 2 && raw.starts_with?('"') && raw.ends_with?('"') ? raw[1..-2] : raw
    end

    # JAX-RS path composition: trailing-slash on the class path is
    # cosmetic — Jakarta REST normalises it. We emit `/users` rather
    # than `/users/` for the index handler, matching how callers
    # actually request the route.
    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end

    # ---- formal-parameter walk --------------------------------------

    private def collect_method_params(method : LibTreeSitter::TSNode,
                                      source : String,
                                      verb : String,
                                      method_format : String?,
                                      dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)),
                                      bean_index : Hash(String, Array(Param)),
                                      constants : Hash(String, String),
                                      current_class : String) : Array(Param)
      params = [] of Param
      formal = formal_parameters_node(method)
      return params unless formal

      multipart_fields = multipart_form_fields(method, source)
      Noir::TreeSitter.each_named_child(formal) do |param|
        next unless Noir::TreeSitter.node_type(param) == "formal_parameter"
        emit_param_for(param, source, verb, method_format, dto_index, bean_index, constants, current_class, params, multipart_fields)
      end
      params
    end

    private def formal_parameters_node(method : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(method) do |child|
        return child if Noir::TreeSitter.node_type(child) == "formal_parameters"
      end
      nil
    end

    private def emit_param_for(param : LibTreeSitter::TSNode,
                               source : String,
                               verb : String,
                               method_format : String?,
                               dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)),
                               bean_index : Hash(String, Array(Param)),
                               constants : Hash(String, String),
                               current_class : String,
                               sink : Array(Param),
                               multipart_fields = Hash(String, Array(String)).new)
      param_name, type_name = parameter_name_and_type(param, source)
      return if param_name.empty?

      ann_kind : Symbol? = nil
      ann_arg : String? = nil
      ann_format : String? = nil
      default_value : String? = nil

      each_annotation(param, source) do |name, args, _|
        if PATH_PARAM_ANNOTATIONS.includes?(name)
          ann_kind = :path
          ann_arg = first_string_arg(args, source, constants, current_class)
        elsif name == "BeanParam"
          ann_kind = :bean
        elsif name == "Context" || name == "Suspended"
          ann_kind = :context
        elsif name == "DefaultValue"
          default_value = first_string_arg(args, source, constants, current_class)
        elsif fmt = PARAM_ANNOTATION_FORMAT[name]?
          ann_kind = :param
          ann_format = fmt
          ann_arg = first_string_arg(args, source, constants, current_class)
          ann_arg ||= ""
        end
      end

      case ann_kind
      when :path, :context
        # @PathParam carries it in the URL; @Context/@Suspended are
        # framework injection. Skip in both cases.
        return
      when :bean
        if fields = bean_index[type_name]?
          fields.each do |field|
            sink << Param.new(field.name, field.value, field.param_type)
          end
        end
        return
      when :param
        # Emit here (not inside the loop) so @DefaultValue is captured
        # regardless of annotation order on the parameter.
        sink << Param.new((ann_arg || "").presence || param_name, default_value || "", ann_format || "query")
        return
      end

      # Un-annotated parameter — request body. Expand DTO fields when
      # we know them, otherwise emit a single `body` param so the
      # caller still sees something.
      return if PRIMITIVE_TYPES.includes?(type_name.downcase)
      return if INJECTED_PARAM_TYPES.includes?(type_name.downcase)
      format = method_format || "json"
      if MULTIPART_FORM_PARAM_TYPES.includes?(type_name.downcase)
        fields = multipart_fields[param_name]? || [] of String
        if fields.empty?
          sink << Param.new(param_name, "", "form")
        else
          fields.each { |field| sink << Param.new(field, "", "form") }
        end
        return
      end
      if fields = dto_index[type_name]?
        fields.each do |field|
          next unless field.access_modifier == "public" || field.has_setter?
          sink << Param.new(field.name, field.init_value, format)
        end
      else
        sink << Param.new(param_name, type_name, format)
      end
    end

    private def parameter_name_and_type(param : LibTreeSitter::TSNode, source : String) : Tuple(String, String)
      name = ""
      type_name = ""
      Noir::TreeSitter.each_named_child(param) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier"
          name = Noir::TreeSitter.node_text(child, source) if name.empty?
        when "type_identifier", "integral_type", "floating_point_type", "boolean_type", "void_type"
          type_name = Noir::TreeSitter.node_text(child, source) if type_name.empty?
        when "generic_type", "scoped_type_identifier", "array_type"
          type_name = leaf_type_name(child, source) if type_name.empty?
        end
      end
      {name, type_name}
    end

    private def multipart_form_fields(method : LibTreeSitter::TSNode, source : String) : Hash(String, Array(String))
      fields = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }
      body = Noir::TreeSitter.field(method, "body")
      return fields unless body

      collect_multipart_form_fields(body, source, fields, 0)
      fields
    end

    private def collect_multipart_form_fields(node : LibTreeSitter::TSNode,
                                              source : String,
                                              fields : Hash(String, Array(String)),
                                              depth : Int32)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "method_invocation"
        collect_multipart_form_field_from_call(node, source, fields)
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        collect_multipart_form_fields(child, source, fields, depth + 1)
      end
    end

    private def collect_multipart_form_field_from_call(call : LibTreeSitter::TSNode,
                                                       source : String,
                                                       fields : Hash(String, Array(String)))
      name = method_invocation_name(call, source)
      carrier = ""
      field_name : String? = nil

      if name == "get"
        object = Noir::TreeSitter.field(call, "object")
        if object && Noir::TreeSitter.node_type(object) == "method_invocation" &&
           method_invocation_name(object, source) == "getFormDataMap"
          carrier = method_invocation_receiver(object, source)
          field_name = first_string_arg(method_invocation_args(call), source)
        end
      elsif name == "getFormDataPart"
        carrier = method_invocation_receiver(call, source)
        field_name = first_string_arg(method_invocation_args(call), source)
      end

      return if carrier.empty?
      field = field_name
      return unless field
      return if field.empty?

      fields[carrier] << field unless fields[carrier].includes?(field)
    end

    private def method_invocation_name(call : LibTreeSitter::TSNode, source : String) : String
      if name_node = Noir::TreeSitter.field(call, "name")
        return Noir::TreeSitter.node_text(name_node, source)
      end

      ""
    end

    private def method_invocation_receiver(call : LibTreeSitter::TSNode, source : String) : String
      object = Noir::TreeSitter.field(call, "object")
      return "" unless object

      case Noir::TreeSitter.node_type(object)
      when "identifier"
        Noir::TreeSitter.node_text(object, source)
      when "field_access", "scoped_identifier"
        last_segment(Noir::TreeSitter.node_text(object, source))
      else
        ""
      end
    end

    private def method_invocation_args(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(call) do |child|
        return child if Noir::TreeSitter.node_type(child) == "argument_list"
      end
      nil
    end

    private def leaf_type_name(node : LibTreeSitter::TSNode, source : String) : String
      ty = Noir::TreeSitter.node_type(node)
      return Noir::TreeSitter.node_text(node, source) if ty == "type_identifier"
      Noir::TreeSitter.each_named_child(node) do |child|
        leaf = leaf_type_name(child, source)
        return leaf unless leaf.empty?
      end
      ""
    end

    private def first_string_arg(args : LibTreeSitter::TSNode?,
                                 source : String,
                                 constants : Hash(String, String) = Hash(String, String).new,
                                 current_class : String = "") : String?
      return unless args
      Noir::TreeSitter.each_named_child(args) do |child|
        case Noir::TreeSitter.node_type(child)
        when "string_literal"
          return decode_string_literal(child, source)
        when "identifier", "field_access", "scoped_identifier", "binary_expression", "parenthesized_expression"
          if value = resolve_path_value(child, source, constants, current_class)
            return value
          end
        when "element_value_pair"
          key = Noir::TreeSitter.field(child, "key")
          val = Noir::TreeSitter.field(child, "value")
          next unless key && val
          next unless Noir::TreeSitter.node_text(key, source) == "value"
          if value = resolve_path_value(val, source, constants, current_class)
            return value
          end
        end
      end
      nil
    end

    # ---- @BeanParam field collection --------------------------------

    private def collect_bean_params(decl : LibTreeSitter::TSNode,
                                    source : String,
                                    constants : Hash(String, String),
                                    current_class : String) : Array(Param)
      params = [] of Param
      body = class_body_node(decl)
      return params unless body

      Noir::TreeSitter.each_named_child(body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "field_declaration"

        field_name = ""
        Noir::TreeSitter.each_named_child(member) do |child|
          if Noir::TreeSitter.node_type(child) == "variable_declarator"
            Noir::TreeSitter.each_named_child(child) do |sub|
              if Noir::TreeSitter.node_type(sub) == "identifier"
                field_name = Noir::TreeSitter.node_text(sub, source)
                break
              end
            end
          end
        end
        next if field_name.empty?

        default_value = annotation_value(member, "DefaultValue", source, constants, current_class) || ""
        each_annotation(member, source) do |name, args, _|
          if format = PARAM_ANNOTATION_FORMAT[name]?
            arg = first_string_arg(args, source, constants, current_class) || field_name
            params << Param.new(arg, default_value, format)
          end
        end
      end

      Noir::TreeSitter.each_named_child(body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "method_declaration"

        method_name = method_name_of(member, source) || ""
        default_value = annotation_value(member, "DefaultValue", source, constants, current_class) || ""
        each_annotation(member, source) do |name, args, _|
          if format = PARAM_ANNOTATION_FORMAT[name]?
            fallback = setter_property_name(method_name)
            next if fallback.empty?
            arg = first_string_arg(args, source, constants, current_class) || fallback
            params << Param.new(arg, default_value, format)
          end
        end
      end
      params
    end

    private def annotation_value(decl : LibTreeSitter::TSNode,
                                 ann_name : String,
                                 source : String,
                                 constants : Hash(String, String),
                                 current_class : String) : String?
      result : String? = nil
      each_annotation(decl, source) do |name, args, _|
        next unless name == ann_name
        result = first_string_arg(args, source, constants, current_class)
      end
      result
    end

    private def setter_property_name(method_name : String) : String
      return "" unless method_name.starts_with?("set") && method_name.size > 3

      raw = method_name[3..]
      raw[0].downcase + raw[1..]
    end
  end
end
