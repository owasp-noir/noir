require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "../models/code_locator"
require "./import_graph"

module Noir
  # Tree-sitter-backed parameter extractor for Kotlin Spring.
  #
  # Mirrors `TreeSitterJavaParameterExtractor` for the Kotlin AST
  # (parameter modifiers come before the parameter, primary
  # constructor properties carry DTO fields, annotation arguments
  # use `value_arguments` instead of `annotation_argument_list`).
  #
  # Covered:
  #
  #   * `@PathVariable` (skipped — URL carries it)
  #   * `@RequestBody` / messaging `@Payload` — defaults to "json" (or "form" via consumes=)
  #   * `@RequestParam(value/name = "x", defaultValue = "y")` — query
  #   * `@RequestHeader(value/name = "x")` / messaging `@Header` — header, including
  #     `HttpHeaders.X_FOO` constant normalisation
  #   * `@CookieValue(name = "lorem", defaultValue = "ipsum")` — cookie
  #   * Primitive types (Long/Int/String/Boolean/MultipartFile) emit
  #     directly with the declared parameter name
  #   * User-defined classes — DTO field expansion via the
  #     caller-supplied `class_fields` index. Kotlin DTOs are usually
  #     `data class Foo(val a, var b)` — properties live on the
  #     primary constructor and are all exposed as if they were
  #     `public` fields with synthesised setters.
  #   * `params = ["x=v"]` and `headers = ["X-H=v"]` on the method's
  #     mapping annotation synthesise extra `Param`s. `params=` for
  #     GET/HEAD/OPTIONS is "query"; otherwise "form" (matches Spring's
  #     dispatch convention).
  #
  # Not covered yet (see #1298):
  #   * HttpServletRequest body scan — Kotlin idiom rarely uses it.
  #   * Meta-annotations (custom annotations composing `@RequestMapping`).
  module TreeSitterKotlinParameterExtractor
    extend self

    # Scalar types Spring binds from a single request value. Type names
    # are first resolved to their leaf identifier by `leaf_type_name`
    # (so `List<Long>` reduces to `List`); annotated request params emit
    # by name regardless of type. Mirrors the Java extractor's
    # `SIMPLE_PARAM_TYPES` so `@RequestParam ids: List<Long>` surfaces
    # instead of being silently dropped.
    PRIMITIVE_TYPES = Set{
      "long", "int", "integer", "short", "byte",
      "char", "character", "boolean", "string",
      "float", "double", "number",
      "bigdecimal", "biginteger", "uuid",
      "date", "localdate", "localdatetime", "localtime", "instant",
      "multipartfile",
    }

    # Parameter annotations whose value is supplied by a Spring argument
    # resolver, not bound from the HTTP request the client controls. A
    # parameter carrying one of these is NOT an attack-surface input
    # even when its type is a bindable DTO (the classic
    # `@AuthenticationPrincipal user: User`, or a custom meta-annotation
    # like `@CurrentUser`), so it must be excluded from the un-annotated
    # implicit-binding path that would otherwise expand its DTO fields
    # into phantom params. Validation annotations (`@Valid`, …) are
    # intentionally absent — they leave binding semantics untouched.
    INJECTED_PARAM_ANNOTATIONS = Set{
      "AuthenticationPrincipal", "CurrentUser", "CurrentSecurityContext",
      "SessionAttribute", "RequestAttribute",
    }

    # Verbs whose `params = [...]` constraint emits as query
    # parameters. Anything else uses form data.
    QUERY_VERB_PARAMS = Set{"GET", "HEAD", "OPTIONS"}

    HTTP_HEADER_SPECIAL_CASES = {
      "Etag"             => "ETag",
      "Te"               => "TE",
      "Www-Authenticate" => "WWW-Authenticate",
      "X-Frame-Options"  => "X-Frame-Options",
    }

    # Alias the shared import-graph type so existing call sites stay
    # ergonomic while the cross-file traversal logic lives in
    # `Noir::ImportGraph` (#1107).
    alias ImportDecl = Noir::ImportGraph::ImportRef

    struct FieldInfo
      getter name : String
      getter access_modifier : String
      getter? has_setter : Bool
      getter init_value : String
      getter null_validation_groups : Array(String)
      getter? server_managed : Bool
      getter validation_annotations : Array(String)

      def initialize(@name, @access_modifier, @has_setter, @init_value,
                     @null_validation_groups = [] of String, @server_managed = false,
                     @validation_annotations = [] of String)
      end

      def null_for_any_group?(groups : Array(String)) : Bool
        return false if groups.empty? || @null_validation_groups.empty?
        groups.any? { |group| @null_validation_groups.includes?(group) }
      end
    end

    # Extract `{class_name => [FieldInfo]}` from `source`. Kotlin DTO
    # fields can come from:
    #
    #   1. Primary constructor parameters declared with `val` / `var`
    #      (the common `data class Foo(val a: Int, var b: String)`
    #      idiom).
    #   2. `property_declaration` nodes inside the class body (`var`/
    #      `val` properties on regular classes).
    #
    # Properties are treated as setter-accessible by default — Kotlin
    # synthesises setters for `var`, and `val` properties usually
    # serialise just fine for our endpoint-fan-out purposes.
    def extract_class_fields(source : String) : Hash(String, Array(FieldInfo))
      results = Hash(String, Array(FieldInfo)).new
      Noir::TreeSitter.parse_kotlin(source) do |root|
        results = extract_class_fields_from(root, source)
      end
      results
    end

    # `_from(root, source, ...)` variants accept a pre-parsed root
    # so the Kotlin Spring analyzer can amortise the tree-sitter
    # parse across multiple extractions on the same file. Tree
    # lifetime is the caller's responsibility.
    def extract_class_fields_from(root : LibTreeSitter::TSNode, source : String) : Hash(String, Array(FieldInfo))
      results = Hash(String, Array(FieldInfo)).new
      walk_class_containers(root) do |decl|
        name = type_identifier_text(decl, source)
        next if name.empty?
        fields = collect_class_fields(decl, source)
        results[name] = fields unless fields.empty?
      end
      results
    end

    # Map each class to the simple name of its superCLASS (the supertype
    # invoked with `()`, e.g. `class Owner : Person()` → `{"Owner" =>
    # "Person"}`). Interface supertypes (`: Foo` without parens) carry no
    # bindable fields and are skipped. Drives the DTO index's cross-file
    # inheritance merge so a command object that extends a base class
    # inherits its bindable fields.
    def extract_class_supertypes(source : String) : Hash(String, String)
      results = Hash(String, String).new
      Noir::TreeSitter.parse_kotlin(source) do |root|
        results = extract_class_supertypes_from(root, source)
      end
      results
    end

    def extract_class_supertypes_from(root : LibTreeSitter::TSNode, source : String) : Hash(String, String)
      results = Hash(String, String).new
      walk_class_containers(root) do |decl|
        next unless Noir::TreeSitter.node_type(decl) == "class_declaration"
        name = type_identifier_text(decl, source)
        next if name.empty?
        sup = superclass_name(decl, source)
        results[name] = sup unless sup.empty?
      end
      results
    end

    # The superclass simple name from a class declaration's supertype
    # list. Kotlin spells a base CLASS as a `constructor_invocation`
    # (`Person()`); interfaces are bare `user_type`s and are ignored.
    private def superclass_name(decl : LibTreeSitter::TSNode, source : String) : String
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        ty = Noir::TreeSitter.node_type(child)
        next unless ty.includes?("delegation")
        name = constructor_super_in(child, source, 0)
        return name unless name.empty?
      end
      ""
    end

    private def constructor_super_in(node : LibTreeSitter::TSNode, source : String, depth : Int32) : String
      return "" if depth > 4
      if Noir::TreeSitter.node_type(node) == "constructor_invocation"
        Noir::TreeSitter.each_named_child(node) do |c|
          return leaf_type_name(c, source) if Noir::TreeSitter.node_type(c) == "user_type"
        end
        return ""
      end
      Noir::TreeSitter.each_named_child(node) do |c|
        name = constructor_super_in(c, source, depth + 1)
        return name unless name.empty?
      end
      ""
    end

    # Walk method formal parameters + synthesised `params=`/`headers=`
    # constraints on the method's mapping annotation. Returns the
    # combined parameter list in the order the legacy analyzer
    # emitted them: formal-parameter sweep first, constraint sweep
    # appended.
    def extract_method_parameters(source : String,
                                  class_name : String,
                                  method_name : String,
                                  verb : String,
                                  parameter_format : String?,
                                  class_fields : Hash(String, Array(FieldInfo)),
                                  string_constants = Hash(String, String).new,
                                  local_string_constants = Hash(String, String).new) : Array(Param)
      params = [] of Param
      Noir::TreeSitter.parse_kotlin(source) do |root|
        params = extract_method_parameters_from(
          root, source, class_name, method_name, verb, parameter_format, class_fields,
          string_constants, local_string_constants
        )
      end
      params
    end

    def extract_method_parameters_from(root : LibTreeSitter::TSNode,
                                       source : String,
                                       class_name : String,
                                       method_name : String,
                                       verb : String,
                                       parameter_format : String?,
                                       class_fields : Hash(String, Array(FieldInfo)),
                                       string_constants = Hash(String, String).new,
                                       local_string_constants = Hash(String, String).new) : Array(Param)
      method = find_function(root, source, class_name, method_name)
      return [] of Param unless method
      extract_method_parameters_from_method(
        method, source, verb, parameter_format, class_fields, string_constants, local_string_constants
      )
    end

    def extract_method_parameters_from_method(method : LibTreeSitter::TSNode,
                                              source : String,
                                              verb : String,
                                              parameter_format : String?,
                                              class_fields : Hash(String, Array(FieldInfo)),
                                              string_constants = Hash(String, String).new,
                                              local_string_constants = Hash(String, String).new) : Array(Param)
      params = collect_method_params(
        method, source, verb, parameter_format, class_fields, string_constants, local_string_constants
      )
      append_constraint_params(method, source, verb, params, string_constants, local_string_constants)
      params
    end

    def extract_server_request_parameters_from_method(method : LibTreeSitter::TSNode,
                                                      source : String,
                                                      verb : String,
                                                      parameter_format : String?,
                                                      class_fields : Hash(String, Array(FieldInfo))) : Array(Param)
      params = [] of Param
      body = Noir::TreeSitter.node_text(method, source)
      request_names = server_request_parameter_names(body)
      return params if request_names.empty?

      request_names.each do |request_name|
        query_re, first_header_re, header_re = server_request_param_regexes(request_name)

        body.scan(query_re) do |match|
          push_unique_param(params, Param.new(match[1], "", "query"))
        end

        body.scan(first_header_re) do |match|
          push_unique_param(params, Param.new(match[1], "", "header"))
        end

        body.scan(header_re) do |match|
          push_unique_param(params, Param.new(match[1], "", "header"))
        end
      end

      body_type_names(body, request_names).each do |type_name|
        append_body_type_params(params, type_name, verb, parameter_format, class_fields)
      end

      params
    end

    # Read `consumes = ["..."]` / `consumes = arrayOf("...")` off the
    # method's mapping annotation. Returns "form" / "json" / nil.
    def extract_consumes(source : String, class_name : String, method_name : String) : String?
      result : String? = nil
      Noir::TreeSitter.parse_kotlin(source) do |root|
        result = extract_consumes_from(root, source, class_name, method_name)
      end
      result
    end

    def extract_consumes_from(root : LibTreeSitter::TSNode, source : String, class_name : String, method_name : String) : String?
      method = find_function(root, source, class_name, method_name)
      return unless method
      extract_consumes_from_method(method, source)
    end

    def extract_consumes_from_method(method : LibTreeSitter::TSNode, source : String) : String?
      ann = mapping_annotation_on(method, source)
      return unless ann
      args = annotation_args(ann)
      return unless args
      result : String? = nil
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        kind, key, value = classify_value_argument(arg, source)
        next unless kind == :keyword && key == "consumes"
        next unless value
        # Use the raw text so we catch both string literals
        # ("application/json") and constant references
        # (MediaType.APPLICATION_JSON_VALUE) in one pass — same
        # approach as the Java extractor.
        text = Noir::TreeSitter.node_text(value, source)
        if text.includes?("application/x-www-form-urlencoded") || text.includes?("APPLICATION_FORM_URLENCODED_VALUE")
          result = "form"
        elsif text.includes?("application/json") || text.includes?("APPLICATION_JSON_VALUE")
          result = "json"
        end
      end
      result
    end

    def extract_package_name(source : String) : String
      result = ""
      Noir::TreeSitter.parse_kotlin(source) do |root|
        result = extract_package_name_from(root, source)
      end
      result
    end

    def extract_package_name_from(root : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.each_named_child(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "package_header"
        Noir::TreeSitter.each_named_child(node) do |child|
          ty = Noir::TreeSitter.node_type(child)
          if ty == "identifier" || ty == "simple_identifier"
            return Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      ""
    end

    def extract_imports(source : String) : Array(ImportDecl)
      results = [] of ImportDecl
      Noir::TreeSitter.parse_kotlin(source) do |root|
        results = extract_imports_from(root, source)
      end
      results
    end

    def extract_imports_from(root : LibTreeSitter::TSNode, source : String) : Array(ImportDecl)
      results = [] of ImportDecl
      Noir::TreeSitter.each_named_child(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "import_list"
        Noir::TreeSitter.each_named_child(node) do |header|
          next unless Noir::TreeSitter.node_type(header) == "import_header"
          path = ""
          wildcard = false
          Noir::TreeSitter.each_named_child(header) do |child|
            case Noir::TreeSitter.node_type(child)
            when "identifier", "simple_identifier"
              path = Noir::TreeSitter.node_text(child, source) if path.empty?
            when "wildcard_import"
              wildcard = true
            end
          end
          results << ImportDecl.new(path, wildcard) unless path.empty?
        end
      end
      results
    end

    def index_functions_from(root : LibTreeSitter::TSNode, source : String) : Hash(String, LibTreeSitter::TSNode)
      result = Hash(String, LibTreeSitter::TSNode).new
      walk_class_containers(root) do |decl|
        class_name = type_identifier_text(decl, source)
        next if class_name.empty?
        body = class_body_of(decl)
        next unless body
        Noir::TreeSitter.each_named_child(body) do |member|
          next unless Noir::TreeSitter.node_type(member) == "function_declaration"
          method_name = function_name(member, source)
          next if method_name.empty?
          result["#{class_name}##{method_name}"] ||= member
        end
      end
      index_orphan_functions_from(root, source, result)
      result
    end

    # ---- private helpers ----------------------------------------------

    private def index_orphan_functions_from(root : LibTreeSitter::TSNode,
                                            source : String,
                                            result : Hash(String, LibTreeSitter::TSNode))
      orphan_class : String? = nil
      Noir::TreeSitter.each_named_child(root) do |child|
        case Noir::TreeSitter.node_type(child)
        when "class_declaration", "object_declaration", "interface_declaration"
          if class_body_of(child).nil? && !abstract_type?(child, source)
            class_name = type_identifier_text(child, source)
            orphan_class = class_name.empty? ? nil : class_name
          else
            orphan_class = nil
          end
        when "ERROR"
          if class_name = orphan_class
            collect_orphan_function_nodes(child, source, class_name, result)
          end
          orphan_class = nil
        when "prefix_expression"
          if class_name = split_constructor_class_name(child, source)
            collect_orphan_function_nodes(child, source, class_name, result)
          end
          orphan_class = nil
        when "annotation"
          # Constructor annotations may be parsed as a sibling between
          # the no-body class_declaration and the call_expression that
          # carries the class body. Keep the orphan class context alive.
        when "call_expression"
          if class_name = orphan_class
            collect_orphan_function_nodes(child, source, class_name, result)
          end
          orphan_class = nil
        else
          orphan_class = nil
        end
      end
    end

    private def split_constructor_class_name(node : LibTreeSitter::TSNode, source : String) : String?
      text = Noir::TreeSitter.node_text(node, source)
      return unless text.includes?(" constructor")
      return unless text.includes?(" fun ")
      return if text.match(/\babstract\s+class\b/)
      match = text.match(/\bclass\s+([A-Za-z_][A-Za-z0-9_]*)\b/)
      match.try &.[1]
    end

    private def collect_orphan_function_nodes(node : LibTreeSitter::TSNode,
                                              source : String,
                                              class_name : String,
                                              result : Hash(String, LibTreeSitter::TSNode))
      if Noir::TreeSitter.node_type(node) == "function_declaration"
        method_name = function_name(node, source)
        result["#{class_name}##{method_name}"] ||= node unless method_name.empty?
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        collect_orphan_function_nodes(child, source, class_name, result)
      end
    end

    private def abstract_type?(decl : LibTreeSitter::TSNode, source : String) : Bool
      if mods = find_modifiers(decl)
        Noir::TreeSitter.each_named_child(mods) do |child|
          return true if Noir::TreeSitter.node_text(child, source) == "abstract"
        end
      end
      false
    end

    private def walk_class_containers(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      ty = Noir::TreeSitter.node_type(node)
      if ty == "class_declaration" || ty == "object_declaration" || ty == "interface_declaration"
        block.call(node)
      end
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_class_containers(child, &block)
      end
    end

    private def type_identifier_text(decl : LibTreeSitter::TSNode, source : String) : String
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        if Noir::TreeSitter.node_type(child) == "type_identifier"
          return Noir::TreeSitter.node_text(child, source)
        end
      end
      ""
    end

    private def class_body_of(decl : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        return child if Noir::TreeSitter.node_type(child) == "class_body"
      end
      nil
    end

    private def primary_constructor_of(decl : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        return child if Noir::TreeSitter.node_type(child) == "primary_constructor"
      end
      nil
    end

    # Find the (class_name, method_name) `function_declaration` node.
    private def find_function(root : LibTreeSitter::TSNode,
                              source : String,
                              class_name : String,
                              method_name : String) : LibTreeSitter::TSNode?
      result : LibTreeSitter::TSNode? = nil
      walk_class_containers(root) do |decl|
        next if result
        next unless type_identifier_text(decl, source) == class_name
        body = class_body_of(decl)
        next unless body
        Noir::TreeSitter.each_named_child(body) do |member|
          next if result
          next unless Noir::TreeSitter.node_type(member) == "function_declaration"
          fname = function_name(member, source)
          if fname == method_name
            result = member
          end
        end
      end
      result
    end

    private def function_name(func : LibTreeSitter::TSNode, source : String) : String
      count = LibTreeSitter.ts_node_named_child_count(func)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(func, i.to_u32)
        if Noir::TreeSitter.node_type(child) == "simple_identifier"
          return Noir::TreeSitter.node_text(child, source)
        end
      end
      ""
    end

    # Find the first method-level `@*Mapping` annotation. Used for
    # both `consumes=` and `params=`/`headers=` lookups.
    private def mapping_annotation_on(decl : LibTreeSitter::TSNode, source : String) : LibTreeSitter::TSNode?
      mods = find_modifiers(decl)
      return unless mods
      Noir::TreeSitter.each_named_child(mods) do |ann|
        next unless Noir::TreeSitter.node_type(ann) == "annotation"
        Noir::TreeSitter.each_named_child(ann) do |child|
          ty = Noir::TreeSitter.node_type(child)
          if ty == "user_type" || ty == "constructor_invocation"
            user_type_node = ty == "user_type" ? child : nil
            if ty == "constructor_invocation"
              Noir::TreeSitter.each_named_child(child) do |sub|
                user_type_node = sub if Noir::TreeSitter.node_type(sub) == "user_type"
              end
            end
            next unless user_type_node
            name = simple_annotation_name(Noir::TreeSitter.node_text(user_type_node, source))
            return ann if name.ends_with?("Mapping")
          end
        end
      end
      nil
    end

    private def find_modifiers(decl : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        return child if Noir::TreeSitter.node_type(child) == "modifiers"
      end
      nil
    end

    private def simple_annotation_name(full : String) : String
      if idx = full.rindex('.')
        full[(idx + 1)..]
      else
        full
      end
    end

    # An `annotation` node wraps either a `user_type` (no args) or a
    # `constructor_invocation` (with args). Return the `value_arguments`
    # node when present.
    private def annotation_args(ann : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(ann) do |child|
        next unless Noir::TreeSitter.node_type(child) == "constructor_invocation"
        Noir::TreeSitter.each_named_child(child) do |sub|
          return sub if Noir::TreeSitter.node_type(sub) == "value_arguments"
        end
      end
      nil
    end

    # Classify a `value_argument` node:
    #   * keyword:     `name = expr` — first identifier is the key,
    #                  remaining child is the value
    #   * positional:  bare expression — the only child is the value
    # Returns `{kind, key_or_empty, value_node_or_nil}`.
    private def classify_value_argument(arg : LibTreeSitter::TSNode, source : String) : Tuple(Symbol, String, LibTreeSitter::TSNode?)
      key = ""
      value : LibTreeSitter::TSNode? = nil
      named = false
      Noir::TreeSitter.each_named_child(arg) do |child|
        case Noir::TreeSitter.node_type(child)
        when "simple_identifier"
          if named
            value = child
          else
            key = Noir::TreeSitter.node_text(child, source)
            named = true
          end
        else
          value = child if value.nil?
        end
      end
      {named ? :keyword : :positional, key, value}
    end

    # Collect every literal string value reachable from `node`,
    # whether bare, in a `collection_literal` (`["a","b"]`), or wrapped
    # in `arrayOf("a","b")`.
    private def string_values_in(node : LibTreeSitter::TSNode, source : String) : Array(String)
      sink = [] of String
      collect_string_values(node, source, sink, Hash(String, String).new, Hash(String, String).new)
      sink
    end

    private def string_values_in(node : LibTreeSitter::TSNode,
                                 source : String,
                                 string_constants : Hash(String, String),
                                 local_string_constants : Hash(String, String)) : Array(String)
      sink = [] of String
      collect_string_values(node, source, sink, string_constants, local_string_constants)
      sink
    end

    private def collect_string_values(node : LibTreeSitter::TSNode,
                                      source : String,
                                      sink : Array(String),
                                      string_constants : Hash(String, String),
                                      local_string_constants : Hash(String, String))
      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        text = decode_string_literal(node, source)
        sink << text unless text.empty?
      when "simple_identifier", "navigation_expression"
        text = resolve_string_or_const(node, source, string_constants, local_string_constants)
        sink << text unless text.empty?
      when "collection_literal"
        Noir::TreeSitter.each_named_child(node) do |elem|
          collect_string_values(elem, source, sink, string_constants, local_string_constants)
        end
      when "call_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "call_suffix"
            Noir::TreeSitter.each_named_child(child) do |suf|
              next unless Noir::TreeSitter.node_type(suf) == "value_arguments"
              Noir::TreeSitter.each_named_child(suf) do |va|
                next unless Noir::TreeSitter.node_type(va) == "value_argument"
                Noir::TreeSitter.each_named_child(va) do |v|
                  collect_string_values(v, source, sink, string_constants, local_string_constants)
                end
              end
            end
          end
        end
      end
    end

    private def decode_string_literal(node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "string_content"
            io << Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      buf
    end

    # ---- DTO field collection ----------------------------------------

    private def collect_class_fields(decl : LibTreeSitter::TSNode, source : String) : Array(FieldInfo)
      fields = [] of FieldInfo
      class_name = type_identifier_text(decl, source)
      class_text = Noir::TreeSitter.node_text(decl, source)

      # 1. Primary constructor `class_parameter`s.
      if pc = primary_constructor_of(decl)
        Noir::TreeSitter.each_named_child(pc) do |param|
          next unless Noir::TreeSitter.node_type(param) == "class_parameter"
          name = ""
          init = ""
          Noir::TreeSitter.each_named_child(param) do |child|
            case Noir::TreeSitter.node_type(child)
            when "simple_identifier"
              name = Noir::TreeSitter.node_text(child, source) if name.empty?
            when "string_literal"
              init = decode_string_literal(child, source)
            when "user_type", "nullable_type", "binding_pattern_kind",
                 "modifiers", "parameter_modifiers", "annotation"
              # type / val|var marker / property annotations — not a
              # default value. `modifiers` carries `@field:Email`-style
              # annotations whose source text would otherwise leak into
              # `init_value` (and surface as a bogus param default).
            else
              # default-value expressions (numbers, identifiers, etc.)
              # — stringify so the legacy "init_value" semantic stays
              init = Noir::TreeSitter.node_text(child, source) if init.empty?
            end
          end
          next if name.empty?
          fields << FieldInfo.new(
            name, "public", true, init, null_validation_groups(param, source),
            server_managed_field?(param, source, name, init, class_name, class_text), validation_annotations(param, source)
          )
        end
      end

      # 2. Class-body `property_declaration`s.
      if body = class_body_of(decl)
        last_prop_name : String? = nil
        Noir::TreeSitter.each_named_child(body) do |member|
          case Noir::TreeSitter.node_type(member)
          when "getter", "setter", "property_accessor"
            # A standalone accessor parsed as a sibling belongs to the
            # property just before it (`val isNew: Boolean\n  get() =
            # ...`) — that property is computed, not a backing field, so
            # drop it. Common on JPA base entities; without this it would
            # surface as a phantom param through the inheritance merge.
            if (lf = fields.last?) && last_prop_name && lf.name == last_prop_name
              fields.pop
            end
            last_prop_name = nil
          when "property_declaration"
            last_prop_name = nil
            # Inline accessor form (`val x get() = ...` on one line) keeps
            # the getter as a child of the property_declaration.
            next if property_has_accessor?(member)
            name = ""
            init = ""
            Noir::TreeSitter.each_named_child(member) do |child|
              case Noir::TreeSitter.node_type(child)
              when "variable_declaration"
                Noir::TreeSitter.each_named_child(child) do |sub|
                  if Noir::TreeSitter.node_type(sub) == "simple_identifier"
                    name = Noir::TreeSitter.node_text(sub, source)
                    break
                  end
                end
              when "simple_identifier"
                name = Noir::TreeSitter.node_text(child, source) if name.empty?
              when "string_literal"
                init = decode_string_literal(child, source) if init.empty?
              end
            end
            next if name.empty?
            fields << FieldInfo.new(
              name, "public", true, init, null_validation_groups(member, source),
              server_managed_field?(member, source, name, init, class_name, class_text), validation_annotations(member, source)
            )
            last_prop_name = name
          else
            last_prop_name = nil
          end
        end
      end

      fields
    end

    # True when a `property_declaration` carries a custom getter/setter —
    # i.e. a computed property with no backing field, which must not be
    # treated as a bindable request field.
    private def property_has_accessor?(member : LibTreeSitter::TSNode) : Bool
      Noir::TreeSitter.each_named_child(member) do |child|
        ty = Noir::TreeSitter.node_type(child)
        return true if ty == "getter" || ty == "setter" || ty == "property_accessor"
      end
      false
    end

    private def null_validation_groups(node : LibTreeSitter::TSNode, source : String) : Array(String)
      text = Noir::TreeSitter.node_text(node, source)
      groups = [] of String

      text.scan(/@field:Null\s*\([^)]*groups\s*=\s*\[([^\]]+)\]/m) do |match|
        collect_validation_group_names(match[1], groups)
      end
      text.scan(/@field:Null\s*\([^)]*groups\s*=\s*([A-Za-z_][A-Za-z0-9_.]*)\s*::\s*class/m) do |match|
        add_validation_group_name(groups, match[1])
      end

      groups.uniq
    end

    private def validation_annotations(node : LibTreeSitter::TSNode, source : String) : Array(String)
      validation_annotations(Noir::TreeSitter.node_text(node, source))
    end

    private def validation_annotations(text : String) : Array(String)
      annotations = [] of String

      text.scan(/@(?:field:|get:|set:)?(?:[A-Za-z_][A-Za-z0-9_]*\.)*(NotBlank|NotEmpty|NotNull|Email|Size|Pattern|Min|Max|Positive|PositiveOrZero|Negative|NegativeOrZero|Past|PastOrPresent|Future|FutureOrPresent)\b/) do |match|
        annotations << "@#{match[1]}"
      end

      annotations.uniq
    end

    private def server_managed_field?(node : LibTreeSitter::TSNode,
                                      source : String,
                                      name : String,
                                      init : String,
                                      class_name : String,
                                      class_text : String) : Bool
      text = Noir::TreeSitter.node_text(node, source)
      return true if text.match(/@(?:field:|get:|set:)?(?:[A-Za-z_][A-Za-z0-9_]*\.)*(?:Id|GeneratedValue|CreatedDate|LastModifiedDate|ReadOnlyProperty|JsonIgnore)\b/)
      return true if nullable_default_id_field?(name, text, init)
      return true if nullable_validated_dto_id_field?(name, text, class_name, class_text)

      audit_field?(name) && (init == "null" || !!text.match(/=\s*null\b/))
    end

    private def nullable_default_id_field?(name : String, text : String, init : String) : Bool
      name == "id" && (init == "null" || !!text.match(/=\s*null\b/)) &&
        !!text.match(/\b(?:val|var)\s+id\s*:\s*[^=]+?\?\s*=\s*null\b/)
    end

    private def nullable_validated_dto_id_field?(name : String, text : String, class_name : String, class_text : String) : Bool
      return false unless name == "id"
      return false unless class_name.ends_with?("Dto") || class_name.ends_with?("DTO")
      return false unless text.match(/\b(?:val|var)\s+id\s*:\s*[^=]+?\?/)
      return false unless validation_annotations(text).empty?

      !validation_annotations(class_text).empty?
    end

    private def audit_field?(name : String) : Bool
      {"createdAt", "updatedAt", "deletedAt"}.includes?(name)
    end

    private def active_validation_groups(modifiers : LibTreeSitter::TSNode?, source : String) : Array(String)
      return [] of String unless modifiers

      groups = [] of String
      Noir::TreeSitter.node_text(modifiers, source).scan(/@(?:field:)?Validated\s*\(\s*([^)]+)\)/m) do |match|
        collect_validation_group_names(match[1], groups)
      end
      groups.uniq
    end

    private def collect_validation_group_names(text : String, groups : Array(String))
      text.scan(/([A-Za-z_][A-Za-z0-9_.]*)\s*::\s*class/) do |match|
        add_validation_group_name(groups, match[1])
      end
    end

    private def add_validation_group_name(groups : Array(String), raw_name : String)
      name = raw_name.split('.').last
      return if name.empty? || groups.includes?(name)
      groups << name
    end

    # ---- formal parameter walk ---------------------------------------

    private def collect_method_params(method : LibTreeSitter::TSNode,
                                      source : String,
                                      verb : String,
                                      parameter_format : String?,
                                      class_fields : Hash(String, Array(FieldInfo)),
                                      string_constants : Hash(String, String),
                                      local_string_constants : Hash(String, String)) : Array(Param)
      params = [] of Param
      fparams = function_value_parameters(method)
      return params unless fparams

      current_format = parameter_format
      pending_modifiers : LibTreeSitter::TSNode? = nil

      Noir::TreeSitter.each_named_child(fparams) do |child|
        case Noir::TreeSitter.node_type(child)
        when "parameter_modifiers"
          pending_modifiers = child
        when "parameter"
          current_format = emit_param_for(
            child, pending_modifiers, source, verb, current_format, class_fields, params,
            string_constants, local_string_constants
          )
          pending_modifiers = nil
        end
      end
      params
    end

    private def function_value_parameters(method : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(method)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(method, i.to_u32)
        return child if Noir::TreeSitter.node_type(child) == "function_value_parameters"
      end
      nil
    end

    private def emit_param_for(param : LibTreeSitter::TSNode,
                               modifiers : LibTreeSitter::TSNode?,
                               source : String,
                               verb : String,
                               parameter_format : String?,
                               class_fields : Hash(String, Array(FieldInfo)),
                               sink : Array(Param),
                               string_constants : Hash(String, String),
                               local_string_constants : Hash(String, String)) : String?
      arg_name = ""
      type_name = ""
      Noir::TreeSitter.each_named_child(param) do |child|
        case Noir::TreeSitter.node_type(child)
        when "simple_identifier"
          arg_name = Noir::TreeSitter.node_text(child, source) if arg_name.empty?
        when "user_type", "nullable_type", "type_identifier"
          # Get the leaf type_identifier name for primitive lookup /
          # DTO key. `nullable_type` wraps a `user_type`; `user_type`
          # wraps a `type_identifier`.
          type_name = leaf_type_name(child, source) if type_name.empty?
        end
      end
      return parameter_format if arg_name.empty?

      ann_kind = nil
      ann_node : LibTreeSitter::TSNode? = nil
      injected_param = false
      validation_groups = active_validation_groups(modifiers, source)
      if modifiers
        Noir::TreeSitter.each_named_child(modifiers) do |ann|
          next unless Noir::TreeSitter.node_type(ann) == "annotation"
          name = annotation_simple_name(ann, source)
          injected_param = true if INJECTED_PARAM_ANNOTATIONS.includes?(name)
          case name
          when "PathVariable", "DestinationVariable"
            ann_kind = :path
            ann_node = ann
            break
          when "RequestBody", "Payload"
            ann_kind = :body
            ann_node = ann
            break
          when "RequestParam"
            ann_kind = :query
            ann_node = ann
            break
          when "RequestHeader", "Header", "Headers"
            ann_kind = :header
            ann_node = ann
            break
          when "CookieValue"
            ann_kind = :cookie
            ann_node = ann
            break
          end
        end
      end

      # @PathVariable is carried by the URL, not emitted as a param.
      return parameter_format if ann_kind == :path

      # A Spring argument-resolver parameter (@AuthenticationPrincipal, a
      # custom @CurrentUser meta-annotation, …) with no request-binding
      # annotation is server-supplied, not client input — drop it before
      # the implicit-binding path can expand its (often DTO-typed) fields
      # into phantom params.
      return parameter_format if ann_kind.nil? && injected_param

      effective_format = parameter_format
      case ann_kind
      when :body
        # @RequestBody is JSON unless an explicit `consumes` already pinned
        # the format (e.g. form-urlencoded). The POST verb default is
        # applied per-parameter below, NOT pre-seeded into parameter_format,
        # so a @RequestBody on a POST still resolves to json rather than
        # being dragged along as form.
        effective_format = request_body_format(effective_format)
      when :query
        effective_format = "query"
      when :header
        effective_format = "header"
      when :cookie
        effective_format = "cookie"
      end

      if effective_format.nil?
        # No parameter annotation and no `consumes` hint. Spring still
        # binds a scalar (or a command object) from request values — query
        # string on GET/…, form body on POST. Framework resolver types
        # (Model, Pageable, BindingResult, …) aren't bindable and must not
        # surface. Applying the verb default here — rather than seeding the
        # whole method — lets an explicit @RequestBody on the same POST
        # resolve to json instead of being dragged to form.
        bindable = simple_bindable_param?(type_name) || class_fields.has_key?(type_name)
        return parameter_format unless bindable
        effective_format = verb == "POST" ? "form" : "query"
      end

      default_value : String? = nil
      parameter_name = arg_name

      if ann_node && (args = annotation_args(ann_node))
        Noir::TreeSitter.each_named_child(args) do |arg|
          next unless Noir::TreeSitter.node_type(arg) == "value_argument"
          kind, key, value = classify_value_argument(arg, source)
          next unless value
          if kind == :positional
            parameter_name = resolve_string_or_const(value, source, string_constants, local_string_constants)
          else
            case key
            when "value", "name"
              parameter_name = resolve_string_or_const(value, source, string_constants, local_string_constants)
            when "defaultValue"
              if Noir::TreeSitter.node_type(value) == "string_literal"
                default_value = decode_string_literal(value, source)
              end
            end
          end
        end
      end

      case ann_kind
      when :query, :header, :cookie
        # An explicit scalar request input (possibly a collection of
        # scalars like `@RequestParam ids: List<Long>`) — emit by its
        # declared name; never DTO-expand.
        sink << Param.new(parameter_name, default_value || "", effective_format)
      else
        # @RequestBody or an un-annotated command object: a scalar emits
        # by name, a known DTO fans out to its fields. Body JSON binds
        # every field (Jackson reflection); form/model binding keeps the
        # public-or-setter gate.
        if simple_bindable_param?(type_name)
          sink << Param.new(parameter_name, default_value || "", effective_format)
        elsif fields = class_fields[type_name]?
          json_body = effective_format == "json"
          fields.each do |field|
            next if field.server_managed?
            next if field.null_for_any_group?(validation_groups)
            next unless json_body || field.access_modifier == "public" || field.has_setter?
            expanded_default = default_value || field.init_value
            sink << param_from_field(field, expanded_default, effective_format)
          end
        end
      end

      # Carry the format to subsequent un-annotated params (Spring's
      # implicit binding makes a trailing `page: Int` share the prior
      # `@RequestParam`'s query format). A `@RequestBody`'s json is NOT a
      # method-wide default, though — propagating it would drag a sibling
      # command object into json, so a body param leaves the carry
      # untouched (returns the incoming consumes-derived format).
      ann_kind == :body ? parameter_format : effective_format
    end

    private def request_body_format(parameter_format : String?) : String
      return "json" if parameter_format.nil?
      return "json" if {"query", "header", "cookie"}.includes?(parameter_format)

      parameter_format
    end

    # True when `type_name` is a scalar Spring binds from a single
    # request value. `type_name` is the leaf type identifier resolved by
    # `leaf_type_name`, so a `List<Long>` parameter already reduces to
    # `List` here — collection element types are handled at the call
    # site (annotated request params emit by name regardless of type).
    private def simple_bindable_param?(type_name : String) : Bool
      PRIMITIVE_TYPES.includes?(type_name.downcase)
    end

    private def server_request_parameter_names(body : String) : Array(String)
      names = [] of String
      if match = body.match(/\bfun\s+[A-Za-z_][A-Za-z0-9_]*\s*\((.*?)\)/m)
        match[1].scan(/\b([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?:[A-Za-z_][A-Za-z0-9_.]*\.)?ServerRequest\b/) do |param_match|
          names << param_match[1]
        end
      end

      names.uniq
    end

    # The receiver names are discovered per handler but draw from a tiny
    # vocabulary (`request`, `req`, …), so the compiled patterns are
    # memoized per name/prefix — interpolated literals here would be
    # recompiled for every handler method.
    @@server_request_param_regexes = Hash(String, Tuple(Regex, Regex, Regex)).new
    @@body_type_regexes = Hash(String, Tuple(Regex, Regex, Regex)).new

    private def server_request_param_regexes(request_name : String) : Tuple(Regex, Regex, Regex)
      @@server_request_param_regexes[request_name] ||= begin
        receiver = Regex.escape(request_name)
        {
          /\b#{receiver}\s*\.\s*queryParam\s*\(\s*"([^"]+)"/,
          /\b#{receiver}\s*\.\s*headers\s*\(\s*\)\s*\.\s*firstHeader\s*\(\s*"([^"]+)"/,
          /\b#{receiver}\s*\.\s*header\s*\(\s*"([^"]+)"/,
        }
      end
    end

    private def body_type_regexes(prefix : String) : Tuple(Regex, Regex, Regex)
      @@body_type_regexes[prefix] ||= {
        /#{prefix}\.\s*(?:awaitBody|bodyToMono)\s*<\s*([A-Za-z_][A-Za-z0-9_.]*)\s*>/,
        /#{prefix}\.\s*awaitBodyOrNull\s*\(\s*([A-Za-z_][A-Za-z0-9_.]*)\s*::\s*class/,
        /#{prefix}\.\s*bodyToMono\s*\(\s*([A-Za-z_][A-Za-z0-9_.]*)\s*::\s*class(?:\.java)?/,
      }
    end

    private def body_type_names(body : String, request_names : Array(String)? = nil) : Array(String)
      names = [] of String
      receiver = request_names && !request_names.empty? ? "(?:#{request_names.map { |name| Regex.escape(name) }.join("|")})" : nil
      prefix = receiver ? "\\b#{receiver}\\s*" : ""
      await_body_re, await_body_or_null_re, body_to_mono_re = body_type_regexes(prefix)

      body.scan(await_body_re) do |match|
        add_type_name(names, match[1])
      end

      body.scan(await_body_or_null_re) do |match|
        add_type_name(names, match[1])
      end

      body.scan(body_to_mono_re) do |match|
        add_type_name(names, match[1])
      end

      names
    end

    private def add_type_name(names : Array(String), raw_name : String)
      name = raw_name.split('.').last
      return if name.empty? || names.includes?(name)
      names << name
    end

    private def append_body_type_params(params : Array(Param),
                                        type_name : String,
                                        verb : String,
                                        parameter_format : String?,
                                        class_fields : Hash(String, Array(FieldInfo)))
      return unless {"POST", "PUT", "PATCH"}.includes?(verb.upcase)

      format = parameter_format || "json"
      if fields = class_fields[type_name]?
        fields.each do |field|
          next if field.server_managed?
          push_unique_param(params, param_from_field(field, field.init_value, format))
        end
      elsif simple_bindable_param?(type_name)
        push_unique_param(params, Param.new("body", "", format))
      end
    end

    private def param_from_field(field : FieldInfo, value : String, param_type : String) : Param
      param = Param.new(field.name, value, param_type)
      unless field.validation_annotations.empty?
        param.add_tag(Tag.new(
          "input-validation",
          "Bean Validation constraints: #{field.validation_annotations.join(", ")}",
          "kotlin_spring_validation_analyzer"
        ))
      end
      param
    end

    private def push_unique_param(params : Array(Param), param : Param)
      return if params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
      params << param
    end

    private def leaf_type_name(node : LibTreeSitter::TSNode, source : String) : String
      case Noir::TreeSitter.node_type(node)
      when "type_identifier"
        Noir::TreeSitter.node_text(node, source)
      else
        result = ""
        Noir::TreeSitter.each_named_child(node) do |child|
          name = leaf_type_name(child, source)
          unless name.empty?
            result = name
            break
          end
        end
        result
      end
    end

    private def annotation_simple_name(ann : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.each_named_child(ann) do |child|
        case Noir::TreeSitter.node_type(child)
        when "user_type"
          return simple_annotation_name(Noir::TreeSitter.node_text(child, source))
        when "constructor_invocation"
          Noir::TreeSitter.each_named_child(child) do |sub|
            if Noir::TreeSitter.node_type(sub) == "user_type"
              return simple_annotation_name(Noir::TreeSitter.node_text(sub, source))
            end
          end
        end
      end
      ""
    end

    # `value = "x"` literal, local/shared Kotlin constants, or
    # `value = HttpHeaders.X_FOO` constants.
    private def resolve_string_or_const(value : LibTreeSitter::TSNode,
                                        source : String,
                                        string_constants : Hash(String, String),
                                        local_string_constants : Hash(String, String)) : String
      case Noir::TreeSitter.node_type(value)
      when "string_literal"
        decode_string_literal(value, source)
      when "simple_identifier"
        name = Noir::TreeSitter.node_text(value, source)
        local_string_constants[name]? || string_constants[name]? || name
      when "navigation_expression"
        text = Noir::TreeSitter.node_text(value, source)
        local_string_constants[text]? || string_constants[text]? || normalise_http_header_constant(text)
      else
        Noir::TreeSitter.node_text(value, source)
      end
    end

    private def normalise_http_header_constant(raw : String) : String
      return raw unless raw.starts_with?("HttpHeaders.")
      header_key = raw["HttpHeaders.".size..]
      normalised = header_key.split('_').map(&.capitalize).join('-')
      HTTP_HEADER_SPECIAL_CASES[normalised]? || normalised
    end

    # ---- params= / headers= constraint synthesis ---------------------

    # For each `"name=value"` entry in the method's mapping
    # `params = [...]` argument, append a `Param`. Same for
    # `headers = [...]`. Mirrors the legacy analyzer's behaviour;
    # synthesised params append after the formal-parameter sweep.
    private def append_constraint_params(method : LibTreeSitter::TSNode,
                                         source : String,
                                         verb : String,
                                         sink : Array(Param),
                                         string_constants : Hash(String, String),
                                         local_string_constants : Hash(String, String))
      ann = mapping_annotation_on(method, source)
      return unless ann
      args = annotation_args(ann)
      return unless args

      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        kind, key, value = classify_value_argument(arg, source)
        next unless kind == :keyword && value
        case key
        when "params"
          # Spring `params=` is a routing constraint. Use the verb's
          # natural format (GET/HEAD/OPTIONS → query, otherwise form)
          # — matches legacy single-verb behaviour. Multi-verb
          # `@RequestMapping(method = [GET, POST])` callers should
          # supply `verb` of the first method so all expansions share
          # one format (mirrors the legacy `||=` quirk).
          format = QUERY_VERB_PARAMS.includes?(verb.upcase) ? "query" : "form"
          string_values_in(value, source, string_constants, local_string_constants).each do |raw|
            name, default = split_constraint(raw)
            next if name.empty?
            sink << Param.new(name, default, format)
          end
        when "headers"
          string_values_in(value, source, string_constants, local_string_constants).each do |raw|
            name, default = split_constraint(raw)
            next if name.empty?
            sink << Param.new(name, default, "header")
          end
        end
      end
    end

    # `"name=value"` → `{"name", "value"}`. `"name"` (no `=`) →
    # `{"name", ""}`. Trims leading `!` (Spring negation marker).
    private def split_constraint(raw : String) : Tuple(String, String)
      str = raw.starts_with?("!") ? raw[1..] : raw
      idx = str.index('=')
      return {str, ""} if idx.nil?
      {str[0, idx], str[(idx + 1)..]}
    end
  end

  # Cross-file Kotlin DTO index. Mirrors `TreeSitterJavaDtoIndex`:
  # current file + same-directory siblings + imported files, all
  # parsed via tree-sitter, results memoised across the analyzer's
  # per-file loop.
  class TreeSitterKotlinDtoIndex
    alias Index = Hash(String, Array(TreeSitterKotlinParameterExtractor::FieldInfo))

    # Process-wide shared cache, mirroring `TreeSitterJavaDtoIndex`.
    # See that class for the rationale; the same applies for
    # Kotlin Spring + Ktor + http4k analyzers running concurrently
    # on the same codebase.
    @@shared_cache = Hash(String, Index).new
    # Per-file `class -> superclass simple name` map, cached alongside
    # the field index so a DTO file is parsed once for both. Drives the
    # cross-file inheritance merge below (mirrors TreeSitterJavaDtoIndex).
    @@shared_super_cache = Hash(String, Hash(String, String)).new
    @@shared_cache_mutex = Mutex.new

    # Backstop against pathological supertype graphs — far above any real
    # DTO hierarchy depth/fan-out.
    MAX_INHERITANCE_RESOLUTIONS = 512

    def self.clear_cache!
      @@shared_cache_mutex.synchronize do
        @@shared_cache.clear
        @@shared_super_cache.clear
      end
    end

    def initialize
    end

    def build_for(path : String, content : String) : Index
      Noir::TreeSitter.parse_kotlin(content) do |root|
        return build_for_with_root(path, content, root)
      end
      Index.new
    end

    # Variant taking a pre-parsed root so the Kotlin Spring analyzer can
    # share the parse across the route + parameter walks. Sibling files
    # still parse independently — but go through the process-wide cache
    # so concurrent analyzers don't double-up.
    def build_for_with_root(path : String, content : String, root : LibTreeSitter::TSNode) : Index
      result = Index.new
      # `supers[class] = superclass simple name`; `origin[class] = the
      # file that defined it` — the latter lets the inheritance pass
      # resolve a superclass through the SUBCLASS's imports (Owner imports
      # `model.Person` even though the controller that pulled Owner in
      # never mentions the `model` package).
      supers = Hash(String, String).new
      origin = Hash(String, String).new

      package_name = TreeSitterKotlinParameterExtractor.extract_package_name_from(root, content)
      imports = TreeSitterKotlinParameterExtractor.extract_imports_from(root, content)

      # Seed the shared caches for the current file from the already-parsed
      # root so this and any concurrent analyzer's loop reuses it.
      current_fields = TreeSitterKotlinParameterExtractor.extract_class_fields_from(root, content)
      current_supers = TreeSitterKotlinParameterExtractor.extract_class_supertypes_from(root, content)
      @@shared_cache_mutex.synchronize do
        @@shared_cache[path] ||= current_fields
        @@shared_super_cache[path] ||= current_supers
      end

      Noir::ImportGraph.related_files(path, package_name, imports, "kt") do |file|
        fields, file_supers = load_file(file)
        absorb!(result, supers, origin, fields, file_supers, file)
      end

      resolve_inheritance!(result, supers, origin)
      result
    end

    # Pull a file's `{fields, supertypes}` from the shared cache, parsing
    # it once on a miss. Both maps populate together so a DTO file is
    # never parsed twice.
    private def load_file(file : String) : {Index, Hash(String, String)}
      cached_fields, cached_supers = @@shared_cache_mutex.synchronize do
        {@@shared_cache[file]?, @@shared_super_cache[file]?}
      end
      return {cached_fields, cached_supers} if cached_fields && cached_supers

      fields = Index.new
      supertypes = Hash(String, String).new
      body = file_body(file)
      Noir::TreeSitter.parse_kotlin(body) do |root|
        fields = TreeSitterKotlinParameterExtractor.extract_class_fields_from(root, body)
        supertypes = TreeSitterKotlinParameterExtractor.extract_class_supertypes_from(root, body)
      end

      @@shared_cache_mutex.synchronize do
        @@shared_cache[file] ||= fields
        @@shared_super_cache[file] ||= supertypes
        {@@shared_cache[file], @@shared_super_cache[file]}
      end
    rescue File::NotFoundError
      {Index.new, Hash(String, String).new}
    end

    private def file_body(file : String) : String
      CodeLocator.instance.content_for(file) ||
        File.read(file, encoding: "utf-8", invalid: :skip)
    end

    private def absorb!(result : Index,
                        supers : Hash(String, String),
                        origin : Hash(String, String),
                        fields : Index,
                        file_supers : Hash(String, String),
                        file : String)
      fields.each do |name, fs|
        unless result.has_key?(name)
          result[name] = fs
          origin[name] ||= file
        end
      end
      file_supers.each do |name, sup|
        supers[name] ||= sup
        origin[name] ||= file
      end
    end

    # Merge inherited fields into each subclass: first pull in files that
    # define still-unresolved superclasses (following supertype edges the
    # controller never imported directly), then fold each chain into one
    # flattened field list.
    private def resolve_inheritance!(result : Index,
                                     supers : Hash(String, String),
                                     origin : Hash(String, String))
      return if supers.empty?

      pull_superclass_files!(result, supers, origin)

      memo = Hash(String, Array(TreeSitterKotlinParameterExtractor::FieldInfo)).new
      (result.keys.to_set | supers.keys.to_set).each do |cls|
        merged = effective_fields(cls, result, supers, memo, Set(String).new)
        result[cls] = merged unless merged.empty?
      end
    end

    private def pull_superclass_files!(result : Index,
                                       supers : Hash(String, String),
                                       origin : Hash(String, String))
      attempted = Set(String).new
      pending = supers.keys.to_a
      iterations = 0

      until pending.empty? || iterations > MAX_INHERITANCE_RESOLUTIONS
        iterations += 1
        cls = pending.shift
        sup = supers[cls]?
        next unless sup
        next if result.has_key?(sup) || supers.has_key?(sup)
        next unless attempted.add?(sup)
        file = origin[cls]?
        next unless file

        pending.concat(load_superclass_files(result, supers, origin, file))
      end
    end

    private def load_superclass_files(result : Index,
                                      supers : Hash(String, String),
                                      origin : Hash(String, String),
                                      subclass_file : String) : Array(String)
      added = [] of String
      package_name, imports = file_package_imports(subclass_file)

      Noir::ImportGraph.related_files(subclass_file, package_name, imports, "kt") do |file|
        fields, file_supers = load_file(file)
        fields.each do |name, fs|
          unless result.has_key?(name)
            result[name] = fs
            origin[name] ||= file
            added << name
          end
        end
        file_supers.each do |name, sup|
          unless supers.has_key?(name)
            supers[name] = sup
            origin[name] ||= file
            added << name
          end
        end
      end

      added
    end

    private def file_package_imports(file : String) : {String, Array(Noir::ImportGraph::ImportRef)}
      package_name = ""
      imports = [] of Noir::ImportGraph::ImportRef
      body = file_body(file)
      Noir::TreeSitter.parse_kotlin(body) do |root|
        package_name = TreeSitterKotlinParameterExtractor.extract_package_name_from(root, body)
        imports = TreeSitterKotlinParameterExtractor.extract_imports_from(root, body)
      end
      {package_name, imports}
    rescue File::NotFoundError
      {"", [] of Noir::ImportGraph::ImportRef}
    end

    # Own fields plus the (already-flattened) superclass fields, deduped
    # by name so an overriding field wins. `visiting` guards supertype
    # cycles; `memo` keeps the walk linear.
    private def effective_fields(cls : String,
                                 result : Index,
                                 supers : Hash(String, String),
                                 memo : Hash(String, Array(TreeSitterKotlinParameterExtractor::FieldInfo)),
                                 visiting : Set(String)) : Array(TreeSitterKotlinParameterExtractor::FieldInfo)
      if cached = memo[cls]?
        return cached
      end

      own = result[cls]? || [] of TreeSitterKotlinParameterExtractor::FieldInfo
      sup = supers[cls]?

      if sup.nil? || sup == cls || visiting.includes?(cls)
        memo[cls] = own
        return own
      end

      visiting << cls
      parent = effective_fields(sup, result, supers, memo, visiting)
      visiting.delete(cls)

      if parent.empty?
        memo[cls] = own
        return own
      end

      names = own.map(&.name).to_set
      combined = own.dup
      parent.each do |field|
        combined << field unless names.includes?(field.name)
      end
      memo[cls] = combined
      combined
    end
  end
end
