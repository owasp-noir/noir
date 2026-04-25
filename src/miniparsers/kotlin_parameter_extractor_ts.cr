require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"

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
  #   * `@RequestBody` — defaults to "json" (or "form" via consumes=)
  #   * `@RequestParam(value/name = "x", defaultValue = "y")` — query
  #   * `@RequestHeader(value/name = "x")` — header, including
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

    PRIMITIVE_TYPES = Set{
      "long", "int", "integer", "short", "byte",
      "char", "boolean", "string",
      "float", "double", "number",
      "multipartfile",
    }

    HTTP_HEADER_SPECIAL_CASES = {
      "Etag"             => "ETag",
      "Te"               => "TE",
      "Www-Authenticate" => "WWW-Authenticate",
      "X-Frame-Options"  => "X-Frame-Options",
    }

    # Verbs whose `params = [...]` constraint should be exposed as
    # query parameters. Anything else routes to "form".
    QUERY_VERB_PARAMS = Set{"GET", "HEAD", "OPTIONS"}

    struct ImportDecl
      getter path : String
      getter? wildcard : Bool

      def initialize(@path, @wildcard)
      end
    end

    struct FieldInfo
      getter name : String
      getter access_modifier : String
      getter? has_setter : Bool
      getter init_value : String

      def initialize(@name, @access_modifier, @has_setter, @init_value)
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
        walk_class_containers(root) do |decl|
          name = type_identifier_text(decl, source)
          next if name.empty?
          fields = collect_class_fields(decl, source)
          results[name] = fields unless fields.empty?
        end
      end
      results
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
                                  class_fields : Hash(String, Array(FieldInfo))) : Array(Param)
      params = [] of Param
      Noir::TreeSitter.parse_kotlin(source) do |root|
        method = find_function(root, source, class_name, method_name)
        next unless method
        params = collect_method_params(method, source, verb, parameter_format, class_fields)
        append_constraint_params(method, source, verb, params)
      end
      params
    end

    # Read `consumes = ["..."]` / `consumes = arrayOf("...")` off the
    # method's mapping annotation. Returns "form" / "json" / nil.
    def extract_consumes(source : String, class_name : String, method_name : String) : String?
      result : String? = nil
      Noir::TreeSitter.parse_kotlin(source) do |root|
        method = find_function(root, source, class_name, method_name)
        next unless method
        ann = mapping_annotation_on(method, source)
        next unless ann
        args = annotation_args(ann)
        next unless args
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
      end
      result
    end

    def extract_package_name(source : String) : String
      result = ""
      Noir::TreeSitter.parse_kotlin(source) do |root|
        Noir::TreeSitter.each_named_child(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "package_header"
          Noir::TreeSitter.each_named_child(node) do |child|
            ty = Noir::TreeSitter.node_type(child)
            if ty == "identifier" || ty == "simple_identifier"
              result = Noir::TreeSitter.node_text(child, source)
              break
            end
          end
          break
        end
      end
      result
    end

    def extract_imports(source : String) : Array(ImportDecl)
      results = [] of ImportDecl
      Noir::TreeSitter.parse_kotlin(source) do |root|
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
      end
      results
    end

    # ---- private helpers ----------------------------------------------

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
      collect_string_values(node, source, sink)
      sink
    end

    private def collect_string_values(node : LibTreeSitter::TSNode, source : String, sink : Array(String))
      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        text = decode_string_literal(node, source)
        sink << text unless text.empty?
      when "collection_literal"
        Noir::TreeSitter.each_named_child(node) do |elem|
          collect_string_values(elem, source, sink)
        end
      when "call_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "call_suffix"
            Noir::TreeSitter.each_named_child(child) do |suf|
              next unless Noir::TreeSitter.node_type(suf) == "value_arguments"
              Noir::TreeSitter.each_named_child(suf) do |va|
                next unless Noir::TreeSitter.node_type(va) == "value_argument"
                Noir::TreeSitter.each_named_child(va) do |v|
                  collect_string_values(v, source, sink)
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
            when "user_type", "nullable_type", "binding_pattern_kind"
              # type / val|var marker — not needed here
            else
              # default-value expressions (numbers, identifiers, etc.)
              # — stringify so the legacy "init_value" semantic stays
              init = Noir::TreeSitter.node_text(child, source) if init.empty?
            end
          end
          next if name.empty?
          fields << FieldInfo.new(name, "public", true, init)
        end
      end

      # 2. Class-body `property_declaration`s.
      if body = class_body_of(decl)
        Noir::TreeSitter.each_named_child(body) do |member|
          next unless Noir::TreeSitter.node_type(member) == "property_declaration"
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
          fields << FieldInfo.new(name, "public", true, init)
        end
      end

      fields
    end

    # ---- formal parameter walk ---------------------------------------

    private def collect_method_params(method : LibTreeSitter::TSNode,
                                      source : String,
                                      verb : String,
                                      parameter_format : String?,
                                      class_fields : Hash(String, Array(FieldInfo))) : Array(Param)
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
          current_format = emit_param_for(child, pending_modifiers, source, current_format, class_fields, params)
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
                               parameter_format : String?,
                               class_fields : Hash(String, Array(FieldInfo)),
                               sink : Array(Param)) : String?
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
      if modifiers
        Noir::TreeSitter.each_named_child(modifiers) do |ann|
          next unless Noir::TreeSitter.node_type(ann) == "annotation"
          name = annotation_simple_name(ann, source)
          case name
          when "PathVariable"
            ann_kind = :path
            ann_node = ann
            break
          when "RequestBody"
            ann_kind = :body
            ann_node = ann
            break
          when "RequestParam"
            ann_kind = :query
            ann_node = ann
            break
          when "RequestHeader"
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

      return parameter_format if ann_kind == :path

      effective_format = parameter_format
      case ann_kind
      when :body
        effective_format = effective_format.nil? ? "json" : effective_format
      when :query
        effective_format = "query"
      when :header
        effective_format = "header"
      when :cookie
        effective_format = "cookie"
      end
      return effective_format if effective_format.nil?

      default_value : String? = nil
      parameter_name = arg_name

      if ann_node && (args = annotation_args(ann_node))
        Noir::TreeSitter.each_named_child(args) do |arg|
          next unless Noir::TreeSitter.node_type(arg) == "value_argument"
          kind, key, value = classify_value_argument(arg, source)
          next unless value
          if kind == :positional
            if Noir::TreeSitter.node_type(value) == "string_literal"
              parameter_name = decode_string_literal(value, source)
            end
          else
            case key
            when "value", "name"
              parameter_name = resolve_string_or_const(value, source)
            when "defaultValue"
              if Noir::TreeSitter.node_type(value) == "string_literal"
                default_value = decode_string_literal(value, source)
              end
            end
          end
        end
      end

      type_key = type_name.downcase
      if PRIMITIVE_TYPES.includes?(type_key)
        sink << Param.new(parameter_name, default_value || "", effective_format)
      elsif fields = class_fields[type_name]?
        fields.each do |field|
          next unless field.access_modifier == "public" || field.has_setter?
          expanded_default = default_value || field.init_value
          sink << Param.new(field.name, expanded_default, effective_format)
        end
      end

      effective_format
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

    # `value = "x"` literal or `value = HttpHeaders.X_FOO` constant.
    private def resolve_string_or_const(value : LibTreeSitter::TSNode, source : String) : String
      case Noir::TreeSitter.node_type(value)
      when "string_literal"
        decode_string_literal(value, source)
      when "navigation_expression"
        normalise_http_header_constant(Noir::TreeSitter.node_text(value, source))
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
                                         sink : Array(Param))
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
          string_values_in(value, source).each do |raw|
            name, default = split_constraint(raw)
            next if name.empty?
            format = QUERY_VERB_PARAMS.includes?(verb.upcase) ? "query" : "form"
            sink << Param.new(name, default, format)
          end
        when "headers"
          string_values_in(value, source).each do |raw|
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

    def initialize
      @file_cache = Hash(String, Index).new
    end

    def build_for(path : String, content : String) : Index
      result = Index.new
      merge!(result, classes_in_current(path, content))

      package_dir = File.dirname(path)
      safe_glob("#{package_dir}/*.kt") do |sibling|
        next if sibling == path
        merge!(result, classes_in(sibling))
      end

      package_name = TreeSitterKotlinParameterExtractor.extract_package_name(content)
      source_root = source_root_for(path, package_name) unless package_name.empty?
      return result unless source_root

      TreeSitterKotlinParameterExtractor.extract_imports(content).each do |imp|
        relative = imp.path.gsub(".", "/")
        if imp.wildcard?
          dir = File.join(source_root, relative)
          next unless Dir.exists?(dir)
          safe_glob("#{dir}/*.kt") do |match|
            merge!(result, classes_in(match))
          end
        else
          file = File.join(source_root, "#{relative}.kt")
          next unless File.exists?(file)
          merge!(result, classes_in(file))
        end
      end

      result
    end

    private def classes_in_current(path : String, content : String) : Index
      @file_cache[path] ||= TreeSitterKotlinParameterExtractor.extract_class_fields(content)
    end

    private def classes_in(path : String) : Index
      @file_cache[path] ||= begin
        TreeSitterKotlinParameterExtractor.extract_class_fields(File.read(path, encoding: "utf-8", invalid: :skip))
      rescue File::NotFoundError
        Index.new
      end
    end

    private def source_root_for(file_path : String, package_name : String) : String?
      package_segments = package_name.split('.')
      dir = File.dirname(file_path)
      dir_segments = dir.split('/')
      return if dir_segments.size < package_segments.size
      tail = dir_segments[(dir_segments.size - package_segments.size)..]
      return unless tail == package_segments
      root = dir_segments[0, dir_segments.size - package_segments.size].join('/')
      root.empty? ? "." : root
    end

    private def safe_glob(pattern : String, &)
      Dir.glob(pattern) { |p| yield p }
    rescue
    end

    private def merge!(into : Index, src : Index)
      src.each do |name, fields|
        into[name] ||= fields
      end
    end
  end
end
