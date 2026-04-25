require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "./java_parameter_extractor_ts"

module Noir
  # Tree-sitter-backed Micronaut route + parameter extractor.
  #
  # Walks `@Controller`-annotated classes and emits one route per
  # method-level verb annotation. Recognises:
  #
  #   * Class-level `@Controller("/x")` — joined onto each method's
  #     path with a single `/` separator.
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

    struct Route
      getter verb : String
      getter path : String
      getter class_name : String
      getter method_name : String
      getter line : Int32
      getter params : Array(Param)

      def initialize(@verb, @path, @class_name, @method_name, @line, @params)
      end
    end

    def extract_routes(source : String,
                       dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)) = {} of String => Array(TreeSitterJavaParameterExtractor::FieldInfo)) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_java(source) do |root|
        walk_classes(root) do |decl|
          collect_class_routes(decl, source, dto_index, routes)
        end
      end
      routes
    end

    # ---- traversal ---------------------------------------------------

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
                                     routes : Array(Route))
      class_name = type_identifier_text(decl, source)

      # Need a class-level `@Controller` annotation to consider this
      # class a Micronaut endpoint host. Falling back to "any class
      # with verb-annotated methods" would surface helper utilities.
      controller_paths = annotation_paths_named(decl, "Controller", source)
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
        method_paths = annotation_paths(method_args, source)
        method_paths = [""] if method_paths.empty?
        method_consumes = consumes_format(member, source) || class_consumes

        params = collect_method_params(member, source, method_consumes, dto_index)
        line = Noir::TreeSitter.node_start_row(verb_node)

        controller_paths.each do |class_path|
          method_paths.each do |method_path|
            full_path = join_paths(class_path, method_path)
            routes << Route.new(verb, full_path, class_name, method_name, line, params.dup)
          end
        end
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
    private def annotation_paths(args : LibTreeSitter::TSNode?, source : String) : Array(String)
      paths = [] of String
      return paths unless args

      Noir::TreeSitter.each_named_child(args) do |child|
        case Noir::TreeSitter.node_type(child)
        when "string_literal"
          paths << decode_string_literal(child, source)
        when "array_initializer"
          collect_array_strings(child, source, paths)
        when "element_value_array_initializer"
          collect_array_strings(child, source, paths)
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
          when "string_literal"
            paths << decode_string_literal(value, source)
          when "array_initializer", "element_value_array_initializer"
            collect_array_strings(value, source, paths)
          end
        end
      end
      paths
    end

    # `@Controller("/x")` lookup that returns either a single path,
    # an array fan-out, or `[""]` when the annotation is bare.
    private def annotation_paths_named(decl : LibTreeSitter::TSNode,
                                       ann_name : String,
                                       source : String) : Array(String)
      paths = [] of String
      found = false
      each_annotation(decl, source) do |name, args, _|
        next unless name == ann_name
        found = true
        paths.concat(annotation_paths(args, source))
      end
      return paths unless paths.empty?
      found ? [""] : paths
    end

    private def collect_array_strings(node : LibTreeSitter::TSNode, source : String, sink : Array(String))
      Noir::TreeSitter.each_named_child(node) do |child|
        if Noir::TreeSitter.node_type(child) == "string_literal"
          sink << decode_string_literal(child, source)
        end
      end
    end

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

    # Micronaut joins class + method paths with a single `/`. Empty
    # method path → just the class prefix (no trailing slash).
    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end

    # ---- formal parameter walk --------------------------------------

    private def collect_method_params(method : LibTreeSitter::TSNode,
                                      source : String,
                                      method_format : String?,
                                      dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo))) : Array(Param)
      params = [] of Param
      formal = formal_parameters_node(method)
      return params unless formal

      Noir::TreeSitter.each_named_child(formal) do |param|
        next unless Noir::TreeSitter.node_type(param) == "formal_parameter"
        emit_param_for(param, source, method_format, dto_index, params)
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
                               method_format : String?,
                               dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)),
                               sink : Array(Param))
      param_name, type_name = parameter_name_and_type(param, source)
      return if param_name.empty?

      ann_kind : Symbol? = nil
      ann_arg : String? = nil

      each_annotation(param, source) do |name, args, _|
        if name == "PathVariable"
          ann_kind = :path
          ann_arg = first_string_arg(args, source)
        elsif name == "Body"
          ann_kind = :body
          ann_arg = first_string_arg(args, source)
        elsif format = PARAM_ANNOTATION_FORMAT[name]?
          ann_kind = :param
          ann_arg = first_string_arg(args, source)
          ann_arg ||= ""
          sink << Param.new(ann_arg.presence || param_name, "", format)
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

      # `@Body` and un-annotated complex parameters share the same
      # body-expansion path. Skip primitives (the `model: Model`
      # equivalent in Spring) so framework-injected helpers don't
      # leak into the param list.
      return if PRIMITIVE_TYPES.includes?(type_name.downcase)
      format = method_format || "json"
      if fields = dto_index[type_name]?
        fields.each do |field|
          next unless field.access_modifier == "public" || field.has_setter?
          sink << Param.new(field.name, field.init_value, format)
        end
      else
        sink << Param.new(ann_arg.presence || param_name, type_name, format)
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

    private def first_string_arg(args : LibTreeSitter::TSNode?, source : String) : String?
      return unless args
      Noir::TreeSitter.each_named_child(args) do |child|
        if Noir::TreeSitter.node_type(child) == "string_literal"
          return decode_string_literal(child, source)
        end
      end
      nil
    end
  end
end
