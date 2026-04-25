require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "./java_parameter_extractor_ts"
require "./import_graph"

module Noir
  # Tree-sitter-backed JAX-RS / Jakarta REST extractor.
  #
  # Walks `@Path` resource classes and emits one `Endpoint`-shaped
  # `Route` per HTTP-method-annotated method. Recognises:
  #
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
  # Out of scope for this first cut: meta-annotations, sub-resource
  # locators (`@Path` returning a sub-resource), `@MatrixParam`,
  # `@Context` (always skipped — framework injection, not user input).
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

    struct Route
      getter verb : String
      getter path : String
      getter class_name : String
      getter method_name : String
      getter line : Int32
      getter parameter_format : String?
      getter params : Array(Param)

      def initialize(@verb, @path, @class_name, @method_name, @line,
                     @parameter_format, @params)
      end
    end

    # Public entry point — walks `source` and returns one `Route`
    # per JAX-RS endpoint defined in `path`'s file. `dto_index` maps
    # `class_name → fields` for cross-file body / `@BeanParam`
    # expansion (typically built via `TreeSitterJavaDtoIndex`).
    def extract_routes(source : String,
                       dto_index : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)) = {} of String => Array(TreeSitterJavaParameterExtractor::FieldInfo),
                       bean_index : Hash(String, Array(Param)) = {} of String => Array(Param)) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_java(source) do |root|
        walk_classes(root) do |decl|
          collect_class_routes(decl, source, dto_index, bean_index, routes)
        end
      end
      routes
    end

    # Read JAX-RS-annotated fields (`@QueryParam`, `@HeaderParam`,
    # ...) from every class in the file as `{class_name => Params}`.
    # Used to power `@BeanParam` expansion across files.
    def extract_bean_fields(source : String) : Hash(String, Array(Param))
      results = Hash(String, Array(Param)).new
      Noir::TreeSitter.parse_java(source) do |root|
        walk_classes(root) do |decl|
          name = type_identifier_text(decl, source)
          next if name.empty?
          params = collect_bean_params(decl, source)
          results[name] = params unless params.empty?
        end
      end
      results
    end

    # ---- private ------------------------------------------------------

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
                                     routes : Array(Route))
      class_name = type_identifier_text(decl, source)
      class_path = annotation_string_value(decl, "Path", source) || ""
      class_consumes = consumes_format(decl, source)

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
        next unless verb && verb_node

        method_name = method_name_of(member, source) || ""
        method_path = annotation_string_value(member, "Path", source) || ""

        full_path = join_paths(class_path, method_path)
        method_consumes = consumes_format(member, source) || class_consumes

        params = collect_method_params(member, source, verb, method_consumes,
          dto_index, bean_index)

        line = Noir::TreeSitter.node_start_row(verb_node)
        routes << Route.new(verb, full_path, class_name, method_name, line,
          method_consumes, params)
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

    # `@Path("/x")` / `@Path(value = "/x")` — return the string. Skip
    # if the annotation isn't found or value isn't a string literal.
    private def annotation_string_value(decl : LibTreeSitter::TSNode,
                                        ann_name : String,
                                        source : String) : String?
      result : String? = nil
      each_annotation(decl, source) do |name, args, _|
        next unless name == ann_name
        next unless args
        Noir::TreeSitter.each_named_child(args) do |child|
          case Noir::TreeSitter.node_type(child)
          when "string_literal"
            result = decode_string_literal(child, source)
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
            if key == "value" && value && Noir::TreeSitter.node_type(value) == "string_literal"
              result = decode_string_literal(value, source)
            end
          end
        end
      end
      result
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
                                      bean_index : Hash(String, Array(Param))) : Array(Param)
      params = [] of Param
      formal = formal_parameters_node(method)
      return params unless formal

      Noir::TreeSitter.each_named_child(formal) do |param|
        next unless Noir::TreeSitter.node_type(param) == "formal_parameter"
        emit_param_for(param, source, verb, method_format, dto_index, bean_index, params)
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
                               sink : Array(Param))
      param_name, type_name = parameter_name_and_type(param, source)
      return if param_name.empty?

      ann_kind : Symbol? = nil
      ann_arg : String? = nil
      default_value : String? = nil

      each_annotation(param, source) do |name, args, _|
        if PATH_PARAM_ANNOTATIONS.includes?(name)
          ann_kind = :path
          ann_arg = first_string_arg(args, source)
        elsif name == "BeanParam"
          ann_kind = :bean
        elsif name == "Context"
          ann_kind = :context
        elsif name == "DefaultValue"
          default_value = first_string_arg(args, source)
        elsif format = PARAM_ANNOTATION_FORMAT[name]?
          ann_kind = :param
          ann_arg = first_string_arg(args, source)
          ann_arg ||= ""
          sink << Param.new(ann_arg.presence || param_name, default_value || "", format)
        end
      end

      case ann_kind
      when :path, :context
        # @PathParam → URL carries it; @Context → framework
        # injection. Skip in both cases.
        return
      when :bean
        if fields = bean_index[type_name]?
          fields.each do |field|
            sink << Param.new(field.name, field.value, field.param_type)
          end
        end
        return
      when :param
        # already emitted above
        return
      end

      # Un-annotated parameter — request body. Expand DTO fields when
      # we know them, otherwise emit a single `body` param so the
      # caller still sees something.
      return if PRIMITIVE_TYPES.includes?(type_name.downcase)
      format = method_format || "json"
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

    # ---- @BeanParam field collection --------------------------------

    private def collect_bean_params(decl : LibTreeSitter::TSNode, source : String) : Array(Param)
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

        each_annotation(member, source) do |name, args, _|
          if format = PARAM_ANNOTATION_FORMAT[name]?
            arg = first_string_arg(args, source) || field_name
            params << Param.new(arg, "", format)
          end
        end
      end
      params
    end
  end
end
