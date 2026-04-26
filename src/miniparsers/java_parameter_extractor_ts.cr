require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "../models/code_locator"
require "./import_graph"

module Noir
  # Tree-sitter-backed parameter extractor for Java/Spring.
  #
  # Pairs with `TreeSitterJavaRouteExtractor`: after the route
  # discovery pass tells us which methods are routes, this module
  # walks the matching `method_declaration` to extract request
  # parameters from `@RequestParam` / `@RequestBody` / `@RequestHeader`
  # / `@PathVariable` annotations, primitive typed args,
  # `HttpServletRequest` body scans, and user-defined DTO fields.
  #
  # DTO resolution is caller-provided (`class_fields` map) so the same
  # extractor works whether fields come from a same-file scan, a same-
  # package Dir.glob, or a cross-file import resolver. Keeping that
  # concern out of here keeps the extractor source-scoped and testable.
  module TreeSitterJavaParameterExtractor
    extend self

    # Primitive / stdlib types whose name we emit directly as a
    # parameter. Everything else is looked up in `class_fields` for
    # DTO expansion.
    PRIMITIVE_TYPES = Set{"long", "int", "integer", "char", "boolean", "string", "multipartfile"}

    # Subset of servlet types whose method body is scanned for
    # `request.getParameter("x")` / `request.getHeader("x")` calls.
    SERVLET_REQUEST_TYPES = Set{"HttpServletRequest"}

    # Spring `HttpHeaders` constant → canonical header name. Matches
    # the table the legacy analyzer maintained; necessary because
    # tree-sitter reports the constant as a `field_access` node
    # (e.g. `HttpHeaders.AUTHORIZATION`), not the string value.
    HTTP_HEADER_SPECIAL_CASES = {
      "Etag"             => "ETag",
      "Te"               => "TE",
      "Www-Authenticate" => "WWW-Authenticate",
      "X-Frame-Options"  => "X-Frame-Options",
    }

    # A Java `import` declaration. `wildcard` is true for star imports
    # (`import com.foo.*;`) which fan out to every `.java` in the
    # resolved directory.
    # Alias the shared import-graph type so existing call sites stay
    # ergonomic while the cross-file traversal logic lives in
    # `Noir::ImportGraph` (#1107).
    alias ImportDecl = Noir::ImportGraph::ImportRef

    struct FieldInfo
      getter name : String
      getter access_modifier : String # "public", "private", "protected", ""
      getter? has_setter : Bool
      getter init_value : String # "" when no initializer

      def initialize(@name, @access_modifier, @has_setter, @init_value)
      end
    end

    # Scan every `class_declaration` / `interface_declaration` in
    # `source` and return `{class_name => [FieldInfo]}`. Only classes
    # with at least one field appear; setter detection walks sibling
    # `method_declaration`s looking for `setFoo(...)`.
    def extract_class_fields(source : String) : Hash(String, Array(FieldInfo))
      results = Hash(String, Array(FieldInfo)).new
      Noir::TreeSitter.parse_java(source) do |root|
        walk_class_containers(root) do |decl|
          name_node = Noir::TreeSitter.field(decl, "name")
          next unless name_node
          class_name = Noir::TreeSitter.node_text(name_node, source)
          body = Noir::TreeSitter.field(decl, "body")
          next unless body
          fields = collect_class_fields(body, source)
          results[class_name] = fields unless fields.empty?
        end
      end
      results
    end

    # Extract parameters for `method_name` on `class_name`. Returns
    # `[]` when the method isn't found. `parameter_format` is the
    # method's default-shape hint (e.g. "form" when `@PostMapping` +
    # no explicit `consumes`); individual parameter annotations
    # override it.
    #
    # `class_fields` is the pre-built DTO index — a parameter whose
    # type matches a key is expanded into one `Param` per public /
    # setter-backed field on that class.
    def extract_method_parameters(source : String,
                                  class_name : String,
                                  method_name : String,
                                  verb : String,
                                  parameter_format : String?,
                                  class_fields : Hash(String, Array(FieldInfo))) : Array(Param)
      params = [] of Param
      Noir::TreeSitter.parse_java(source) do |root|
        method = find_method(root, source, class_name, method_name)
        next unless method
        params = collect_method_params(method, source, verb, parameter_format, class_fields)
      end
      params
    end

    # Find `@*Mapping` annotation on (class_name, method_name) and
    # read its `consumes = ...` attribute. Returns "form" / "json" /
    # nil — matches `spring.cr`'s legacy helper semantics so the
    # analyzer can swap this in without behaviour drift.
    def extract_consumes(source : String, class_name : String, method_name : String) : String?
      result : String? = nil
      Noir::TreeSitter.parse_java(source) do |root|
        method = find_method(root, source, class_name, method_name)
        next unless method
        ann = mapping_annotation_on(method, source)
        next unless ann
        args = Noir::TreeSitter.field(ann, "arguments")
        next unless args
        Noir::TreeSitter.each_named_child(args) do |arg|
          next unless Noir::TreeSitter.node_type(arg) == "element_value_pair"
          key = Noir::TreeSitter.field(arg, "key")
          val = Noir::TreeSitter.field(arg, "value")
          next unless key && val
          next unless Noir::TreeSitter.node_text(key, source) == "consumes"
          text = Noir::TreeSitter.node_text(val, source)
          if text.ends_with?("APPLICATION_FORM_URLENCODED_VALUE")
            result = "form"
          elsif text.ends_with?("APPLICATION_JSON_VALUE")
            result = "json"
          end
        end
      end
      result
    end

    # Return the file's `package com.foo.bar;` declaration as a
    # dotted name, or `""` when no package declaration is present.
    def extract_package_name(source : String) : String
      result = ""
      Noir::TreeSitter.parse_java(source) do |root|
        Noir::TreeSitter.each_named_child(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "package_declaration"
          Noir::TreeSitter.each_named_child(node) do |child|
            ty = Noir::TreeSitter.node_type(child)
            if ty == "scoped_identifier" || ty == "identifier"
              result = Noir::TreeSitter.node_text(child, source)
              break
            end
          end
          break
        end
      end
      result
    end

    # Return every `import` in the source as `ImportDecl`. Static imports
    # (`import static ...`) are skipped since they don't contribute DTO
    # classes.
    def extract_imports(source : String) : Array(ImportDecl)
      results = [] of ImportDecl
      Noir::TreeSitter.parse_java(source) do |root|
        Noir::TreeSitter.each_named_child(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "import_declaration"
          # Static imports emit `(static)` as a child; skip them.
          text = Noir::TreeSitter.node_text(node, source)
          next if text.starts_with?("import static")

          path = ""
          wildcard = false
          Noir::TreeSitter.each_named_child(node) do |child|
            case Noir::TreeSitter.node_type(child)
            when "scoped_identifier", "identifier"
              path = Noir::TreeSitter.node_text(child, source) if path.empty?
            when "asterisk"
              wildcard = true
            end
          end
          results << ImportDecl.new(path, wildcard) unless path.empty?
        end
      end
      results
    end

    # Return the set of class/interface simple names annotated with
    # `@FeignClient` in `source`. Spring Cloud Feign interfaces are
    # treated as remote clients in the analyzer's output.
    def extract_feign_client_classes(source : String) : Set(String)
      result = Set(String).new
      Noir::TreeSitter.parse_java(source) do |root|
        walk_class_containers(root) do |decl|
          name_node = Noir::TreeSitter.field(decl, "name")
          next unless name_node
          each_annotation_on(decl, source) do |ann_name|
            if ann_name == "FeignClient"
              result << Noir::TreeSitter.node_text(name_node, source)
              break
            end
          end
        end
      end
      result
    end

    # ---- private helpers ----------------------------------------------

    # Walk every class/interface declaration in the tree.
    private def walk_class_containers(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      ty = Noir::TreeSitter.node_type(node)
      if ty == "class_declaration" || ty == "interface_declaration"
        block.call(node)
      end
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_class_containers(child, &block)
      end
    end

    # Find the (class_name, method_name) method_declaration in the
    # tree. Returns nil when absent.
    private def find_method(root : LibTreeSitter::TSNode,
                            source : String,
                            class_name : String,
                            method_name : String) : LibTreeSitter::TSNode?
      result : LibTreeSitter::TSNode? = nil
      walk_class_containers(root) do |decl|
        next if result
        name_node = Noir::TreeSitter.field(decl, "name")
        next unless name_node
        next unless Noir::TreeSitter.node_text(name_node, source) == class_name
        body = Noir::TreeSitter.field(decl, "body")
        next unless body
        Noir::TreeSitter.each_named_child(body) do |member|
          next if result
          next unless Noir::TreeSitter.node_type(member) == "method_declaration"
          mn = Noir::TreeSitter.field(member, "name")
          next unless mn
          if Noir::TreeSitter.node_text(mn, source) == method_name
            result = member
          end
        end
      end
      result
    end

    # Iterate annotation names (marker or full) attached to a
    # declaration's `modifiers` child. Yields just the simple name
    # (e.g. `"RequestParam"` even for `@org.springframework.web.bind.
    # annotation.RequestParam`).
    private def each_annotation_on(decl : LibTreeSitter::TSNode, source : String, &)
      mods = find_modifiers(decl)
      return unless mods
      Noir::TreeSitter.each_named_child(mods) do |ann|
        ty = Noir::TreeSitter.node_type(ann)
        next unless ty == "annotation" || ty == "marker_annotation"
        n = Noir::TreeSitter.field(ann, "name")
        next unless n
        yield simple_name(Noir::TreeSitter.node_text(n, source))
      end
    end

    private def find_modifiers(decl : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        return child if Noir::TreeSitter.node_type(child) == "modifiers"
      end
      nil
    end

    private def simple_name(full : String) : String
      if idx = full.rindex('.')
        full[(idx + 1)..]
      else
        full
      end
    end

    # Find the first annotation whose simple name ends with "Mapping".
    private def mapping_annotation_on(decl : LibTreeSitter::TSNode, source : String) : LibTreeSitter::TSNode?
      mods = find_modifiers(decl)
      return unless mods
      Noir::TreeSitter.each_named_child(mods) do |ann|
        ty = Noir::TreeSitter.node_type(ann)
        next unless ty == "annotation" || ty == "marker_annotation"
        n = Noir::TreeSitter.field(ann, "name")
        next unless n
        return ann if simple_name(Noir::TreeSitter.node_text(n, source)).ends_with?("Mapping")
      end
      nil
    end

    # ---- class field introspection ------------------------------------

    private def collect_class_fields(body : LibTreeSitter::TSNode, source : String) : Array(FieldInfo)
      # First pass: collect field declarations.
      declared = [] of Tuple(String, String, String) # name, access, init_value
      setter_targets = Set(String).new

      Noir::TreeSitter.each_named_child(body) do |member|
        case Noir::TreeSitter.node_type(member)
        when "field_declaration"
          access = modifier_access(member, source)
          type_node = Noir::TreeSitter.field(member, "type")
          _ = type_node
          dec = Noir::TreeSitter.field(member, "declarator")
          next unless dec
          name_node = Noir::TreeSitter.field(dec, "name")
          next unless name_node
          name = Noir::TreeSitter.node_text(name_node, source)
          init = ""
          if value_node = Noir::TreeSitter.field(dec, "value")
            init = Noir::TreeSitter.node_text(value_node, source)
          end
          declared << {name, access, init}
        when "method_declaration"
          mn = Noir::TreeSitter.field(member, "name")
          next unless mn
          name = Noir::TreeSitter.node_text(mn, source)
          next unless name.starts_with?("set") && name.size > 3
          # Convert `setFoo` → `foo` for field-name matching.
          base = name[3].downcase.to_s + name[4..]
          setter_targets << base
        end
      end

      declared.map do |name, access, init|
        FieldInfo.new(name, access, setter_targets.includes?(name), init)
      end
    end

    # Return the first access modifier keyword in `decl`'s modifiers,
    # or "" when none. Spring's legacy analyzer compared this to
    # "public" to decide whether a field is externally settable.
    private def modifier_access(decl : LibTreeSitter::TSNode, source : String) : String
      mods = find_modifiers(decl)
      return "" unless mods
      count = LibTreeSitter.ts_node_child_count(mods)
      count.times do |i|
        child = LibTreeSitter.ts_node_child(mods, i.to_u32)
        text = Noir::TreeSitter.node_text(child, source)
        case text
        when "public", "private", "protected"
          return text
        end
      end
      ""
    end

    # ---- method parameter walk ----------------------------------------

    private def collect_method_params(method : LibTreeSitter::TSNode,
                                      source : String,
                                      verb : String,
                                      parameter_format : String?,
                                      class_fields : Hash(String, Array(FieldInfo))) : Array(Param)
      params = [] of Param
      fparams = Noir::TreeSitter.field(method, "parameters")
      return params unless fparams

      # `current_format` carries over between parameters, matching the
      # legacy analyzer's sticky state: once a `@RequestParam` promotes
      # the format to "query", a subsequent un-annotated `String name`
      # argument is still emitted as a query parameter.
      current_format = parameter_format

      Noir::TreeSitter.each_named_child(fparams) do |fp|
        next unless Noir::TreeSitter.node_type(fp) == "formal_parameter"
        current_format = emit_param_for(fp, method, source, verb, current_format, class_fields, params)
      end
      params
    end

    private def emit_param_for(fp : LibTreeSitter::TSNode,
                               method : LibTreeSitter::TSNode,
                               source : String,
                               verb : String,
                               parameter_format : String?,
                               class_fields : Hash(String, Array(FieldInfo)),
                               sink : Array(Param)) : String?
      type_node = Noir::TreeSitter.field(fp, "type")
      name_node = Noir::TreeSitter.field(fp, "name")
      return parameter_format unless type_node && name_node

      type_name = Noir::TreeSitter.node_text(type_node, source)
      arg_name = Noir::TreeSitter.node_text(name_node, source)

      # Annotation dispatch. A parameter may carry at most one of
      # `@PathVariable` / `@RequestBody` / `@RequestParam` /
      # `@RequestHeader`; the first we see wins.
      ann_kind = nil
      ann_node : LibTreeSitter::TSNode? = nil
      if mods = find_modifiers(fp)
        Noir::TreeSitter.each_named_child(mods) do |ann|
          ty = Noir::TreeSitter.node_type(ann)
          next unless ty == "annotation" || ty == "marker_annotation"
          n = Noir::TreeSitter.field(ann, "name")
          next unless n
          sn = simple_name(Noir::TreeSitter.node_text(n, source))
          case sn
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
          end
        end
      end

      return parameter_format if ann_kind == :path # legacy: @PathVariable is not emitted

      effective_format = parameter_format
      case ann_kind
      when :body
        effective_format = effective_format.nil? ? "json" : effective_format
      when :query
        effective_format = "query"
      when :header
        effective_format = "header"
      end
      return effective_format if effective_format.nil?

      default_value : String? = nil
      parameter_name = arg_name

      # Walk `@RequestParam(value = "x", defaultValue = "y")` / single-arg shorthand.
      if ann_node
        if args = Noir::TreeSitter.field(ann_node, "arguments")
          Noir::TreeSitter.each_named_child(args) do |arg|
            case Noir::TreeSitter.node_type(arg)
            when "string_literal"
              parameter_name = decode_string_literal(arg, source)
            when "field_access"
              parameter_name = normalise_http_header_constant(Noir::TreeSitter.node_text(arg, source))
            when "element_value_pair"
              key = Noir::TreeSitter.field(arg, "key")
              val = Noir::TreeSitter.field(arg, "value")
              next unless key && val
              k = Noir::TreeSitter.node_text(key, source)
              case k
              when "value", "name"
                parameter_name = resolve_annotation_string_or_const(val, source)
              when "defaultValue"
                default_value = decode_string_literal(val, source) if Noir::TreeSitter.node_type(val) == "string_literal"
              end
            end
          end
        end
      end

      type_key = type_name.downcase
      if PRIMITIVE_TYPES.includes?(type_key)
        sink << Param.new(parameter_name, default_value || "", effective_format)
      elsif SERVLET_REQUEST_TYPES.includes?(type_name)
        scan_servlet_body(method, source, arg_name, effective_format, sink)
      elsif fields = class_fields[type_name]?
        fields.each do |field|
          next unless field.access_modifier == "public" || field.has_setter?
          expanded_default = default_value || field.init_value
          sink << Param.new(field.name, expanded_default, effective_format)
        end
      end

      effective_format
    end

    # Resolve either a string literal or a qualified-identifier
    # constant (`HttpHeaders.AUTHORIZATION`) to the final header/param
    # name. Matches the legacy normalisation.
    private def resolve_annotation_string_or_const(node : LibTreeSitter::TSNode, source : String) : String
      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        decode_string_literal(node, source)
      when "field_access"
        normalise_http_header_constant(Noir::TreeSitter.node_text(node, source))
      else
        Noir::TreeSitter.node_text(node, source)
      end
    end

    # `HttpHeaders.X_FRAME_OPTIONS` → `X-Frame-Options`.
    private def normalise_http_header_constant(raw : String) : String
      return raw unless raw.starts_with?("HttpHeaders.")
      header_key = raw["HttpHeaders.".size..]
      normalised = header_key.split('_').map(&.capitalize).join('-')
      HTTP_HEADER_SPECIAL_CASES[normalised]? || normalised
    end

    # Walk a method body for `<arg>.getParameter("x")` /
    # `<arg>.getHeader("x")` calls, turning each into a Param on the
    # endpoint. `arg_name` is the declared `HttpServletRequest`
    # parameter name.
    private def scan_servlet_body(method : LibTreeSitter::TSNode,
                                  source : String,
                                  arg_name : String,
                                  parameter_format : String,
                                  sink : Array(Param))
      body = Noir::TreeSitter.field(method, "body")
      return unless body
      walk_node(body) do |node|
        next unless Noir::TreeSitter.node_type(node) == "method_invocation"
        obj = Noir::TreeSitter.field(node, "object")
        name = Noir::TreeSitter.field(node, "name")
        next unless obj && name
        next unless Noir::TreeSitter.node_type(obj) == "identifier"
        next unless Noir::TreeSitter.node_text(obj, source) == arg_name
        method_name = Noir::TreeSitter.node_text(name, source)
        next unless method_name == "getParameter" || method_name == "getHeader"

        args = Noir::TreeSitter.field(node, "arguments")
        next unless args
        Noir::TreeSitter.each_named_child(args) do |arg|
          next unless Noir::TreeSitter.node_type(arg) == "string_literal"
          param_name = decode_string_literal(arg, source)
          next if param_name.empty?
          format = method_name == "getHeader" ? "header" : parameter_format
          # Match legacy dedupe: same-name params collapse.
          next if sink.any? { |p| p.name == param_name && p.param_type == format }
          sink << Param.new(param_name, "", format)
        end
      end
    end

    private def walk_node(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_node(child, &block)
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
      buf
    end
  end

  # Builds the DTO field index for a given source file by combining:
  #
  #   1. in-file class/interface declarations,
  #   2. every `.java` in the same directory (same Java package), and
  #   3. files reachable through the `import` statements, resolved
  #      against a source root inferred from the current file's
  #      `package ...;` declaration.
  #
  # Each file's extraction is memoised so the per-file loop in
  # `spring.cr` doesn't re-read and re-parse DTOs over and over when
  # many controllers share the same package.
  class TreeSitterJavaDtoIndex
    alias Index = Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo))

    def initialize
      @file_cache = Hash(String, Index).new
    end

    # Build the DTO index visible to the Spring controller at `path`.
    # Callers pass `content` (already read once) to avoid a redundant
    # disk read for the current file. Cross-file traversal is
    # delegated to `Noir::ImportGraph` so this stays a thin
    # language-specific cache.
    def build_for(path : String, content : String) : Index
      result = Index.new
      package_name = TreeSitterJavaParameterExtractor.extract_package_name(content)
      imports = TreeSitterJavaParameterExtractor.extract_imports(content)

      Noir::ImportGraph.related_files(path, package_name, imports, "java") do |file|
        merge!(result, classes_in(file, path, content))
      end

      result
    end

    private def classes_in(file : String, current_path : String, current_content : String) : Index
      @file_cache[file] ||= begin
        body =
          if file == current_path
            current_content
          else
            # Detector pre-warms a content cache for every scanned
            # file (size-bounded). Sibling DTO files often live in
            # that cache already — `nil` falls back to a fresh
            # `File.read` for files outside the budget.
            CodeLocator.instance.content_for(file) ||
            File.read(file, encoding: "utf-8", invalid: :skip)
          end
        TreeSitterJavaParameterExtractor.extract_class_fields(body)
      rescue File::NotFoundError
        Index.new
      end
    end

    private def merge!(into : Index, src : Index)
      src.each do |name, fields|
        into[name] ||= fields
      end
    end
  end
end
