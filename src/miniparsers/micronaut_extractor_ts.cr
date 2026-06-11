require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "./java_callee_extractor"
require "./java_parameter_extractor_ts"
require "./java_route_extractor_ts"

module Noir
  # Tree-sitter-backed Micronaut route + parameter extractor.
  #
  # Walks `@Controller`-annotated classes and emits one route per
  # method-level verb annotation. Recognises:
  #
  #   * Class-level `@Controller("/x")` — joined onto each method's
  #     path with a single `/` separator.
  #   * Class-level `@ServerWebSocket("/x")` — surfaced as `GET`
  #     with `protocol = "ws"`.
  #   * Verb annotations: `@Get`, `@Post`, `@Put`, `@Delete`,
  #     `@Patch`, `@Head`, `@Options` from
  #     `io.micronaut.http.annotation`.
  #   * Path supplied positionally (`@Get("/x")`) or via the
  #     `value` / `uri` / `uris` keyword. Array forms (`uris =
  #     {"/a", "/b"}`) fan out into one route per path.
  #   * `@Consumes(MediaType.APPLICATION_*)` at class or method
  #     level — method-level wins. Same form/json detection shape
  #     as the Spring + JAX-RS extractors.
  #   * Parameter annotations:
  #     - `@PathVariable` (skipped — URL carries it)
  #     - `@QueryValue("name")` — query
  #     - `@Header("X-Foo")` — header
  #     - `@CookieValue("name")` — cookie
  #     - `@Part("name")` — multipart form
  #     - `@RequestBean` — query bean fields
  #     - `@Body` — explicit request body
  #   * Un-annotated, non-primitive parameters — treated as the
  #     request body (Micronaut's implicit convention) and expanded
  #     against the caller-supplied DTO index.
  #
  # Out of scope for this first cut: meta-annotations, `@Filter`,
  # `@Produces` (response type, not input), `@RequestAttribute`.
  module TreeSitterMicronautExtractor
    extend self

    HTTP_VERB_ANNOTATIONS = {
      "Get"     => "GET",
      "Post"    => "POST",
      "Put"     => "PUT",
      "Delete"  => "DELETE",
      "Patch"   => "PATCH",
      "Head"    => "HEAD",
      "Options" => "OPTIONS",
    }

    PARAM_ANNOTATION_FORMAT = {
      "QueryValue"  => "query",
      "Header"      => "header",
      "CookieValue" => "cookie",
      "Part"        => "form",
    }

    PRIMITIVE_TYPES = Set{
      "boolean", "byte", "char", "short", "int", "long",
      "float", "double", "void", "string", "object",
      "integer", "character",
    }

    INJECTED_PARAM_TYPES = Set{
      "authentication", "httprequest", "httpheaders", "pageable",
      "principal", "x509authentication",
    }

    FORM_FILE_PARAM_TYPES = Set{
      "completedfileupload", "streamingfileupload", "completedpart",
      "partdata",
    }

    struct Route
      getter verb : String
      getter path : String
      getter class_name : String
      getter method_name : String
      getter line : Int32
      getter params : Array(Param)
      getter callees : Array(Tuple(String, Int32))
      getter protocol : String

      def initialize(@verb, @path, @class_name, @method_name, @line, @params, @callees, @protocol = "http")
      end
    end

    struct ControllerInterfaceImplementation
      getter class_name : String
      getter interface_names : Array(String)
      getter paths : Array(String)
      getter line : Int32

      def initialize(@class_name, @interface_names, @paths, @line)
      end
    end

    def extract_routes(source : String,
                       dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)) = {} of String => Array(TreeSitterJavaParameterExtractor::FieldInfo),
                       *,
                       include_callees : Bool = false) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_java(source) do |root|
        constants = TreeSitterJavaRouteExtractor.extract_string_constants_from(root, source)
        walk_classes(root) do |decl|
          collect_class_routes(decl, source, dto_index, routes, include_callees, constants)
        end
      end
      routes
    end

    def extract_interface_routes(source : String,
                                 dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)) = {} of String => Array(TreeSitterJavaParameterExtractor::FieldInfo),
                                 *,
                                 include_callees : Bool = false) : Hash(String, Array(Route))
      routes = Hash(String, Array(Route)).new { |hash, key| hash[key] = [] of Route }
      Noir::TreeSitter.parse_java(source) do |root|
        routes = extract_interface_routes_from(root, source, dto_index, include_callees: include_callees)
      end
      routes
    end

    def extract_interface_routes_from(root : LibTreeSitter::TSNode,
                                      source : String,
                                      dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)) = {} of String => Array(TreeSitterJavaParameterExtractor::FieldInfo),
                                      *,
                                      include_callees : Bool = false) : Hash(String, Array(Route))
      constants = TreeSitterJavaRouteExtractor.extract_string_constants_from(root, source)
      routes = Hash(String, Array(Route)).new { |hash, key| hash[key] = [] of Route }
      walk_interfaces(root) do |decl|
        collect_interface_routes(decl, source, dto_index, routes, include_callees, constants)
      end
      routes.reject { |_name, interface_routes| interface_routes.empty? }
    end

    def extract_controller_interface_implementations(source : String) : Array(ControllerInterfaceImplementation)
      implementations = [] of ControllerInterfaceImplementation
      Noir::TreeSitter.parse_java(source) do |root|
        implementations = extract_controller_interface_implementations_from(root, source)
      end
      implementations
    end

    def extract_controller_interface_implementations_from(root : LibTreeSitter::TSNode,
                                                          source : String) : Array(ControllerInterfaceImplementation)
      constants = TreeSitterJavaRouteExtractor.extract_string_constants_from(root, source)
      implementations = [] of ControllerInterfaceImplementation
      walk_controller_interface_implementations(root, source, implementations, constants)
      implementations
    end

    # ---- traversal ---------------------------------------------------

    private def walk_classes(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      ty = Noir::TreeSitter.node_type(node)
      block.call(node) if ty == "class_declaration" || ty == "interface_declaration"
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_classes(child, &block)
      end
    end

    private def walk_interfaces(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node) if Noir::TreeSitter.node_type(node) == "interface_declaration"
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_interfaces(child, &block)
      end
    end

    private def walk_controller_interface_implementations(node : LibTreeSitter::TSNode,
                                                          source : String,
                                                          implementations : Array(ControllerInterfaceImplementation),
                                                          constants : Hash(String, String),
                                                          depth : Int32 = 0)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "class_declaration"
        interface_names = implemented_interface_names(node, source)
        if !interface_names.empty?
          class_name = type_identifier_text(node, source)
          paths = annotation_paths_named(node, "Controller", source, constants, class_name)
          unless paths.empty?
            implementations << ControllerInterfaceImplementation.new(
              class_name, interface_names, paths, Noir::TreeSitter.node_start_row(node)
            )
          end
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_controller_interface_implementations(child, source, implementations, constants, depth + 1)
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

    private def class_body_node(decl : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(decl) do |child|
        ty = Noir::TreeSitter.node_type(child)
        return child if ty == "class_body" || ty == "interface_body"
      end
      nil
    end

    private def method_name_of(method : LibTreeSitter::TSNode, source : String) : String?
      Noir::TreeSitter.each_named_child(method) do |child|
        return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "identifier"
      end
      nil
    end

    private def collect_class_routes(decl : LibTreeSitter::TSNode,
                                     source : String,
                                     dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)),
                                     routes : Array(Route),
                                     include_callees : Bool = false,
                                     constants : Hash(String, String) = Hash(String, String).new)
      class_name = type_identifier_text(decl, source)

      each_annotation(decl, source) do |ann_name, args, ann|
        next unless ann_name == "ServerWebSocket"

        websocket_paths = annotation_paths(args, source, constants, class_name)
        websocket_paths = ["/ws"] if websocket_paths.empty?
        line = Noir::TreeSitter.node_start_row(ann)
        websocket_paths.each do |websocket_path|
          routes << Route.new("GET", websocket_path, class_name, "", line,
            [] of Param, [] of Tuple(String, Int32), "ws")
        end
      end

      # Need a class-level `@Controller` annotation to consider this
      # class a Micronaut endpoint host. Falling back to "any class
      # with verb-annotated methods" would surface helper utilities.
      controller_paths = annotation_paths_named(decl, "Controller", source, constants, class_name)
      return if controller_paths.empty?
      class_consumes = consumes_format(decl, source)

      body = class_body_node(decl)
      return unless body

      Noir::TreeSitter.each_named_child(body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "method_declaration"

        verb_node : LibTreeSitter::TSNode? = nil
        verb : String? = nil
        method_args : LibTreeSitter::TSNode? = nil
        each_annotation(member, source) do |ann_name, args, ann|
          if mapped = HTTP_VERB_ANNOTATIONS[ann_name]?
            verb = mapped
            verb_node = ann
            method_args = args
            break
          end
        end
        next unless verb && verb_node

        method_name = method_name_of(member, source) || ""
        method_paths = annotation_paths(method_args, source, constants, class_name)
        method_paths = [""] if method_paths.empty?
        method_consumes = consumes_format(member, source) ||
                          consumes_format_args(method_args, source, Set{"consumes", "processes"}) ||
                          class_consumes

        callees = include_callees ? collect_method_callees(member, source) : [] of Tuple(String, Int32)
        line = Noir::TreeSitter.node_start_row(verb_node)

        controller_paths.each do |class_path|
          method_paths.each do |method_path|
            full_path = join_paths(class_path, method_path)
            normalized_path = strip_uri_template_query(full_path)
            query_vars = uri_template_query_vars(full_path)
            path_vars = uri_template_path_vars(normalized_path)
            params = collect_method_params(member, source, method_consumes, dto_index, constants, class_name, query_vars.to_set, path_vars.to_set)
            merge_query_template_params(params, unbound_query_template_vars(member, source, query_vars))
            routes << Route.new(verb, normalized_path, class_name, method_name, line, params, callees)
          end
        end
      end
    end

    private def collect_interface_routes(decl : LibTreeSitter::TSNode,
                                         source : String,
                                         dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)),
                                         routes : Hash(String, Array(Route)),
                                         include_callees : Bool,
                                         constants : Hash(String, String))
      interface_name = type_identifier_text(decl, source)
      return if interface_name.empty?

      interface_paths = annotation_paths_named(decl, "Controller", source, constants, interface_name)
      interface_paths = [""] if interface_paths.empty?
      interface_consumes = consumes_format(decl, source)

      body = class_body_node(decl)
      return unless body

      Noir::TreeSitter.each_named_child(body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "method_declaration"

        verb_node : LibTreeSitter::TSNode? = nil
        verb : String? = nil
        method_args : LibTreeSitter::TSNode? = nil
        each_annotation(member, source) do |ann_name, args, ann|
          if mapped = HTTP_VERB_ANNOTATIONS[ann_name]?
            verb = mapped
            verb_node = ann
            method_args = args
            break
          end
        end
        next unless verb && verb_node

        method_name = method_name_of(member, source) || ""
        method_paths = annotation_paths(method_args, source, constants, interface_name)
        method_paths = [""] if method_paths.empty?
        method_consumes = consumes_format(member, source) ||
                          consumes_format_args(method_args, source, Set{"consumes", "processes"}) ||
                          interface_consumes

        callees = include_callees ? collect_method_callees(member, source) : [] of Tuple(String, Int32)
        line = Noir::TreeSitter.node_start_row(verb_node)

        interface_paths.each do |interface_path|
          method_paths.each do |method_path|
            full_path = join_paths(interface_path, method_path)
            normalized_path = strip_uri_template_query(full_path)
            query_vars = uri_template_query_vars(full_path)
            path_vars = uri_template_path_vars(normalized_path)
            params = collect_method_params(member, source, method_consumes, dto_index, constants, interface_name, query_vars.to_set, path_vars.to_set)
            merge_query_template_params(params, unbound_query_template_vars(member, source, query_vars))
            routes[interface_name] << Route.new(verb, normalized_path, interface_name, method_name, line, params, callees)
          end
        end
      end
    end

    private def collect_method_callees(method : LibTreeSitter::TSNode,
                                       source : String) : Array(Tuple(String, Int32))
      body = Noir::TreeSitter.field(method, "body")
      return [] of Tuple(String, Int32) unless body

      Noir::JavaCalleeExtractor.callees_in_body(body, source, "").map do |(name, _path, line)|
        {name, line}
      end
    end

    # ---- annotation helpers -----------------------------------------

    private def each_annotation(decl : LibTreeSitter::TSNode, source : String, &)
      Noir::TreeSitter.each_named_child(decl) do |child|
        next unless Noir::TreeSitter.node_type(child) == "modifiers"
        Noir::TreeSitter.each_named_child(child) do |ann|
          ty = Noir::TreeSitter.node_type(ann)
          next unless ty == "annotation" || ty == "marker_annotation"
          name = annotation_simple_name(ann, source)
          args = annotation_args_node(ann)
          yield name, args, ann
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

    # `@Foo("a")`, `@Foo(value="a")`, `@Foo(uri="a")`,
    # `@Foo(uris={"a","b"})` — return every string path encountered.
    private def annotation_paths(args : LibTreeSitter::TSNode?,
                                 source : String,
                                 constants : Hash(String, String) = Hash(String, String).new,
                                 current_class : String = "") : Array(String)
      paths = [] of String
      return paths unless args

      Noir::TreeSitter.each_named_child(args) do |child|
        case Noir::TreeSitter.node_type(child)
        when "string_literal", "identifier", "field_access", "scoped_identifier", "binary_expression", "parenthesized_expression"
          collect_string_values(child, source, constants, paths, current_class)
        when "array_initializer", "element_value_array_initializer"
          collect_string_values(child, source, constants, paths, current_class)
        when "element_value_pair"
          key = ""
          value : LibTreeSitter::TSNode? = nil
          Noir::TreeSitter.each_named_child(child) do |sub|
            case Noir::TreeSitter.node_type(sub)
            when "identifier"
              key = Noir::TreeSitter.node_text(sub, source) if key.empty?
            else
              value = sub if value.nil?
            end
          end
          next unless value
          next unless key == "value" || key == "uri" || key == "uris"
          case Noir::TreeSitter.node_type(value)
          when "string_literal", "identifier", "field_access", "scoped_identifier", "binary_expression", "parenthesized_expression",
               "array_initializer", "element_value_array_initializer"
            collect_string_values(value, source, constants, paths, current_class)
          end
        end
      end
      paths
    end

    # `@Controller("/x")` lookup that returns either a single path,
    # an array fan-out, or `[""]` when the annotation is bare.
    private def annotation_paths_named(decl : LibTreeSitter::TSNode,
                                       ann_name : String,
                                       source : String,
                                       constants : Hash(String, String) = Hash(String, String).new,
                                       current_class : String = "") : Array(String)
      paths = [] of String
      found = false
      each_annotation(decl, source) do |name, args, _|
        next unless name == ann_name
        found = true
        paths.concat(annotation_paths(args, source, constants, current_class))
      end
      return paths unless paths.empty?
      found ? [""] : paths
    end

    private def implemented_interface_names(class_decl : LibTreeSitter::TSNode, source : String) : Array(String)
      header = Noir::TreeSitter.node_text(class_decl, source)
      if body_start = header.index('{')
        header = header[...body_start]
      end

      match = header.match(/\bimplements\s+(.+)\z/m)
      return [] of String unless match

      names = split_top_level_commas(match[1]).compact_map do |raw|
        type_name = raw.strip
        next if type_name.empty?
        type_name = strip_generic_arguments(type_name)
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

    private def collect_string_values(node : LibTreeSitter::TSNode,
                                      source : String,
                                      constants : Hash(String, String),
                                      sink : Array(String),
                                      current_class : String = "")
      case Noir::TreeSitter.node_type(node)
      when "array_initializer", "element_value_array_initializer"
        Noir::TreeSitter.each_named_child(node) do |child|
          collect_string_values(child, source, constants, sink, current_class)
        end
      else
        if resolved = resolve_string_value(node, source, constants, current_class)
          sink << resolved
        end
      end
    end

    private def resolve_string_value(node : LibTreeSitter::TSNode,
                                     source : String,
                                     constants : Hash(String, String),
                                     current_class : String = "",
                                     depth = 0) : String?
      return if depth > 16

      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        decode_string_literal(node, source)
      when "identifier", "field_access", "scoped_identifier"
        resolve_constant_reference(Noir::TreeSitter.node_text(node, source), constants, current_class)
      when "binary_expression"
        return unless Noir::TreeSitter.node_text(node, source).includes?("+")
        left = Noir::TreeSitter.field(node, "left")
        right = Noir::TreeSitter.field(node, "right")
        return unless left && right
        left_value = resolve_string_value(left, source, constants, current_class, depth + 1)
        right_value = resolve_string_value(right, source, constants, current_class, depth + 1)
        return unless left_value && right_value
        "#{left_value}#{right_value}"
      when "parenthesized_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          if value = resolve_string_value(child, source, constants, current_class, depth + 1)
            return value
          end
        end
      end
    end

    private def resolve_constant_reference(name : String,
                                           constants : Hash(String, String),
                                           current_class : String = "") : String?
      unless current_class.empty?
        if resolved = constants["#{current_class}.#{name}"]?
          return resolved
        end
      end

      constants[name]?
    end

    private def consumes_format(decl : LibTreeSitter::TSNode, source : String) : String?
      result : String? = nil
      each_annotation(decl, source) do |name, args, _|
        next unless name == "Consumes"
        result = consumes_format_args(args, source)
      end
      result
    end

    private def consumes_format_args(args : LibTreeSitter::TSNode?,
                                     source : String,
                                     keys : Set(String)? = nil) : String?
      return unless args

      if keys
        Noir::TreeSitter.each_named_child(args) do |child|
          next unless Noir::TreeSitter.node_type(child) == "element_value_pair"
          key = ""
          value : LibTreeSitter::TSNode? = nil
          Noir::TreeSitter.each_named_child(child) do |sub|
            case Noir::TreeSitter.node_type(sub)
            when "identifier"
              key = Noir::TreeSitter.node_text(sub, source) if key.empty?
            else
              value = sub if value.nil?
            end
          end
          next unless keys.includes?(key) && value
          if format = consumes_format_from_text(Noir::TreeSitter.node_text(value, source))
            return format
          end
        end
        return
      end

      consumes_format_from_text(Noir::TreeSitter.node_text(args, source))
    end

    private def consumes_format_from_text(text : String) : String?
      if text.includes?("APPLICATION_FORM_URLENCODED") || text.includes?("application/x-www-form-urlencoded")
        "form"
      elsif text.includes?("APPLICATION_JSON") || text.includes?("application/json")
        "json"
      elsif text.includes?("MULTIPART_FORM_DATA") || text.includes?("multipart/form-data")
        "form"
      end
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

    # Micronaut joins class + method paths with a single `/`. Empty
    # method path → just the class prefix (no trailing slash).
    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end

    private def strip_uri_template_query(path : String) : String
      normalized = path.gsub(/\{\?[^}]*\}/, "")
      normalized.empty? ? "/" : normalized
    end

    private def uri_template_query_vars(path : String) : Array(String)
      vars = [] of String
      path.scan(/\{\?([^}]*)\}/) do |match|
        match[1].split(',').each do |raw|
          name = normalize_uri_template_var(raw)
          vars << name unless name.empty?
        end
      end
      vars.uniq
    end

    private def uri_template_path_vars(path : String) : Array(String)
      vars = [] of String
      path.scan(/\{([^}?][^}]*)\}/) do |match|
        name = normalize_uri_template_var(match[1])
        vars << name unless name.empty?
      end
      vars.uniq
    end

    private def normalize_uri_template_var(raw : String) : String
      name = raw.strip
      name = name.rstrip('*')
      if colon = name.index(':')
        name = name[...colon]
      end
      name.strip
    end

    private def merge_query_template_params(params : Array(Param), query_vars : Array(String))
      query_vars.each do |name|
        next if params.any? { |param| param.name == name && param.param_type == "query" }
        params << Param.new(name, "", "query")
      end
    end

    private def unbound_query_template_vars(method : LibTreeSitter::TSNode,
                                            source : String,
                                            query_vars : Array(String)) : Array(String)
      return query_vars if query_vars.empty?

      names = formal_parameter_names(method, source)
      query_vars.reject { |name| names.includes?(name) }
    end

    # ---- formal parameter walk --------------------------------------

    private def collect_method_params(method : LibTreeSitter::TSNode,
                                      source : String,
                                      method_format : String?,
                                      dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)),
                                      constants : Hash(String, String),
                                      current_class : String,
                                      query_template_vars = Set(String).new,
                                      path_template_vars = Set(String).new) : Array(Param)
      params = [] of Param
      formal = formal_parameters_node(method)
      return params unless formal

      Noir::TreeSitter.each_named_child(formal) do |param|
        next unless Noir::TreeSitter.node_type(param) == "formal_parameter"
        emit_param_for(param, source, method_format, dto_index, constants, current_class, params, query_template_vars, path_template_vars)
      end
      params
    end

    private def formal_parameters_node(method : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(method) do |child|
        return child if Noir::TreeSitter.node_type(child) == "formal_parameters"
      end
      nil
    end

    private def formal_parameter_names(method : LibTreeSitter::TSNode, source : String) : Set(String)
      names = Set(String).new
      formal = formal_parameters_node(method)
      return names unless formal

      Noir::TreeSitter.each_named_child(formal) do |param|
        next unless Noir::TreeSitter.node_type(param) == "formal_parameter"
        name, _type_name = parameter_name_and_type(param, source)
        names << name unless name.empty?
      end
      names
    end

    private def emit_param_for(param : LibTreeSitter::TSNode,
                               source : String,
                               method_format : String?,
                               dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)),
                               constants : Hash(String, String),
                               current_class : String,
                               sink : Array(Param),
                               query_template_vars = Set(String).new,
                               path_template_vars = Set(String).new)
      param_name, type_name = parameter_name_and_type(param, source)
      return if param_name.empty?

      ann_kind : Symbol? = nil
      ann_arg : String? = nil
      default_value : String? = nil

      each_annotation(param, source) do |name, args, _|
        if name == "PathVariable"
          ann_kind = :path
          ann_arg = annotation_string_arg(args, source, constants: constants, current_class: current_class)
        elsif name == "Body"
          ann_kind = :body
          ann_arg = annotation_string_arg(args, source, constants: constants, current_class: current_class)
        elsif name == "RequestBean"
          ann_kind = :param
          emit_dto_fields(type_name, dto_index, "query", default_value, sink) do
            sink << Param.new(param_name, type_name, "query")
          end
        elsif format = PARAM_ANNOTATION_FORMAT[name]?
          ann_kind = :param
          ann_arg = annotation_string_arg(args, source, constants: constants, current_class: current_class)
          ann_arg ||= ""
          default_value = annotation_string_arg(args, source, Set{"defaultValue"}, constants, current_class)
          sink << Param.new(ann_arg.presence || param_name, param_value(default_value, ""), format)
        end
      end

      case ann_kind
      when :path
        # URL placeholder — the optimizer expands `{id}` separately.
        return
      when :param
        # already emitted above
        return
      end
      return if path_template_vars.includes?(param_name)

      if query_template_vars.includes?(param_name)
        emit_dto_fields(type_name, dto_index, "query", default_value, sink) do
          sink << Param.new(param_name, param_value(default_value, ""), "query")
        end
        return
      end

      # `@Body` and un-annotated complex parameters share the same
      # body-expansion path. Skip primitives (the `model: Model`
      # equivalent in Spring) so framework-injected helpers don't
      # leak into the param list.
      format = method_format || "json"
      if ann_kind == :body && PRIMITIVE_TYPES.includes?(type_name.downcase)
        sink << Param.new(ann_arg.presence || param_name, param_value(default_value, ""), format)
        return
      end

      return if PRIMITIVE_TYPES.includes?(type_name.downcase)
      return if INJECTED_PARAM_TYPES.includes?(type_name.downcase)
      if format == "form" && FORM_FILE_PARAM_TYPES.includes?(type_name.downcase)
        sink << Param.new(ann_arg.presence || param_name, param_value(default_value, ""), "form")
        return
      end
      emit_dto_fields(type_name, dto_index, format, default_value, sink) do
        sink << Param.new(ann_arg.presence || param_name, param_value(default_value, type_name), format)
      end
    end

    private def emit_dto_fields(type_name : String,
                                dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)),
                                format : String,
                                default_value : String?,
                                sink : Array(Param),
                                &fallback : ->)
      if fields = dto_index[type_name]?
        fields.each do |field|
          next unless field.access_modifier == "public" || field.has_setter?
          sink << Param.new(field.name, param_value(default_value, field.init_value), format)
        end
      else
        fallback.call
      end
    end

    private def param_value(value : String?, fallback : String) : String
      if value
        value
      else
        fallback
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

    private def leaf_type_name(node : LibTreeSitter::TSNode, source : String) : String
      ty = Noir::TreeSitter.node_type(node)
      return Noir::TreeSitter.node_text(node, source) if ty == "type_identifier"
      Noir::TreeSitter.each_named_child(node) do |child|
        leaf = leaf_type_name(child, source)
        return leaf unless leaf.empty?
      end
      ""
    end

    private def annotation_string_arg(args : LibTreeSitter::TSNode?,
                                      source : String,
                                      keys : Set(String) = Set{"value", "name"},
                                      constants : Hash(String, String) = Hash(String, String).new,
                                      current_class : String = "") : String?
      return unless args
      Noir::TreeSitter.each_named_child(args) do |child|
        child_type = Noir::TreeSitter.node_type(child)
        if annotation_string_value_node?(child_type)
          next unless keys.includes?("value") || keys.includes?("name")
          return resolve_string_value(child, source, constants, current_class)
        elsif child_type == "element_value_pair"
          key = ""
          value : LibTreeSitter::TSNode? = nil
          Noir::TreeSitter.each_named_child(child) do |sub|
            case Noir::TreeSitter.node_type(sub)
            when "identifier"
              key = Noir::TreeSitter.node_text(sub, source) if key.empty?
            else
              value = sub if value.nil?
            end
          end
          next unless keys.includes?(key) && value
          value_type = Noir::TreeSitter.node_type(value)
          return resolve_string_value(value, source, constants, current_class) if annotation_string_value_node?(value_type)
        end
      end
      nil
    end

    private def annotation_string_value_node?(node_type : String) : Bool
      node_type == "string_literal" ||
        node_type == "identifier" ||
        node_type == "field_access" ||
        node_type == "scoped_identifier" ||
        node_type == "binary_expression" ||
        node_type == "parenthesized_expression"
    end
  end
end
