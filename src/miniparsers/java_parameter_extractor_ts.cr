require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "../models/code_locator"
require "./import_graph"
require "./java_route_extractor_ts"

module Noir
  # Tree-sitter-backed parameter extractor for Java/Spring.
  #
  # Pairs with `TreeSitterJavaRouteExtractor`: after the route
  # discovery pass tells us which methods are routes, this module
  # walks the matching `method_declaration` to extract request
  # parameters from `@RequestParam` / `@RequestBody` / `@RequestHeader`
  # / `@CookieValue` / `@PathVariable` annotations, primitive typed args,
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

    # Lombok class-level annotations that synthesise setters (or an
    # all-args constructor) for every instance field at compile time.
    # The generated members never appear in source, so a DTO annotated
    # with one of these binds its fields from a request body even though
    # no explicit `setX(...)` method is visible. Treat every non-static
    # field on such a class as settable — otherwise the extremely common
    # `@Data`-annotated Spring DTO yields zero body parameters.
    LOMBOK_FIELD_BINDING_ANNOTATIONS = Set{"Data", "Setter", "Value"}

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
        results = extract_class_fields_from(root, source)
      end
      results
    end

    # `_from(root, source)` variants accept a pre-parsed root node so
    # callers (typically the Spring analyzer) can amortise the
    # tree-sitter parse across multiple extractions on the same file
    # — `extract_routes_from`, `extract_consumes_from`,
    # `extract_method_parameters_from`, and the rest can all share a
    # single `Noir::TreeSitter.parse_java` block. Tree lifetime is
    # the caller's responsibility (it must keep `root` valid by
    # staying inside the `parse_java` block while these are invoked).
    def extract_class_fields_from(root : LibTreeSitter::TSNode, source : String) : Hash(String, Array(FieldInfo))
      results = Hash(String, Array(FieldInfo)).new
      walk_class_containers(root) do |decl|
        name_node = Noir::TreeSitter.field(decl, "name")
        next unless name_node
        class_name = Noir::TreeSitter.node_text(name_node, source)
        body = Noir::TreeSitter.field(decl, "body")
        next unless body
        lombok_setters = lombok_field_binding?(decl, source)
        fields = collect_class_fields(body, source, lombok_setters)
        results[class_name] = fields unless fields.empty?
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
        params = extract_method_parameters_from(root, source, class_name, method_name, verb, parameter_format, class_fields)
      end
      params
    end

    def extract_method_parameters_from(root : LibTreeSitter::TSNode,
                                       source : String,
                                       class_name : String,
                                       method_name : String,
                                       verb : String,
                                       parameter_format : String?,
                                       class_fields : Hash(String, Array(FieldInfo))) : Array(Param)
      method = find_method(root, source, class_name, method_name)
      return [] of Param unless method
      constants = TreeSitterJavaRouteExtractor.extract_string_constants_from(root, source)
      collect_method_params(method, source, verb, parameter_format, class_fields, constants, class_name)
    end

    # Find `@*Mapping` annotation on (class_name, method_name) and
    # read its `consumes = ...` attribute. Returns "form" / "json" /
    # nil — matches `spring.cr`'s legacy helper semantics so the
    # analyzer can swap this in without behaviour drift.
    def extract_consumes(source : String, class_name : String, method_name : String) : String?
      result : String? = nil
      Noir::TreeSitter.parse_java(source) do |root|
        result = extract_consumes_from(root, source, class_name, method_name)
      end
      result
    end

    def extract_consumes_from(root : LibTreeSitter::TSNode, source : String, class_name : String, method_name : String) : String?
      method = find_method(root, source, class_name, method_name)
      return unless method
      ann = mapping_annotation_on(method, source)
      return unless ann
      args = Noir::TreeSitter.field(ann, "arguments")
      return unless args
      result : String? = nil
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
      result
    end

    # Return the file's `package com.foo.bar;` declaration as a
    # dotted name, or `""` when no package declaration is present.
    def extract_package_name(source : String) : String
      result = ""
      Noir::TreeSitter.parse_java(source) do |root|
        result = extract_package_name_from(root, source)
      end
      result
    end

    def extract_package_name_from(root : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.each_named_child(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "package_declaration"
        Noir::TreeSitter.each_named_child(node) do |child|
          ty = Noir::TreeSitter.node_type(child)
          if ty == "scoped_identifier" || ty == "identifier"
            return Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      ""
    end

    # Return every `import` in the source as `ImportDecl`. Static imports
    # (`import static ...`) are skipped since they don't contribute DTO
    # classes.
    def extract_imports(source : String) : Array(ImportDecl)
      results = [] of ImportDecl
      Noir::TreeSitter.parse_java(source) do |root|
        results = extract_imports_from(root, source)
      end
      results
    end

    def extract_imports_from(root : LibTreeSitter::TSNode, source : String) : Array(ImportDecl)
      results = [] of ImportDecl
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
      results
    end

    # Return the set of class/interface simple names annotated with
    # `@FeignClient` in `source`. Spring Cloud Feign interfaces are
    # treated as remote clients in the analyzer's output.
    def extract_feign_client_classes(source : String) : Set(String)
      result = Set(String).new
      Noir::TreeSitter.parse_java(source) do |root|
        result = extract_feign_client_classes_from(root, source)
      end
      result
    end

    def extract_feign_client_classes_from(root : LibTreeSitter::TSNode, source : String) : Set(String)
      result = Set(String).new
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
      result
    end

    # Return the set of class/interface simple names that declare a
    # Spring HTTP Interface. These are remote client contracts when used
    # with HttpServiceProxyFactory, so Spring analyzer output marks them
    # internal like Feign clients.
    def extract_http_exchange_client_classes_from(root : LibTreeSitter::TSNode, source : String) : Set(String)
      result = Set(String).new
      walk_class_containers(root) do |decl|
        next unless Noir::TreeSitter.node_type(decl) == "interface_declaration"
        name_node = Noir::TreeSitter.field(decl, "name")
        next unless name_node

        if http_exchange_interface?(decl, source)
          result << Noir::TreeSitter.node_text(name_node, source)
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

    private def http_exchange_interface?(decl : LibTreeSitter::TSNode, source : String) : Bool
      each_annotation_on(decl, source) do |ann_name|
        return true if ann_name == "HttpExchange"
      end

      return false unless body = Noir::TreeSitter.field(decl, "body")
      Noir::TreeSitter.each_named_child(body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "method_declaration"
        each_annotation_on(member, source) do |ann_name|
          return true if ann_name == "HttpExchange" || ann_name.ends_with?("Exchange")
        end
      end

      false
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

    private def collect_class_fields(body : LibTreeSitter::TSNode,
                                     source : String,
                                     lombok_setters : Bool = false) : Array(FieldInfo)
      # First pass: collect field declarations.
      declared = [] of Tuple(String, String, String) # name, access, init_value
      setter_targets = Set(String).new

      Noir::TreeSitter.each_named_child(body) do |member|
        case Noir::TreeSitter.node_type(member)
        when "field_declaration"
          # Static fields are class constants (`serialVersionUID`,
          # `public static final` config keys), never instance state a
          # request body populates — skip them. This also keeps Lombok
          # `@Data` from promoting constants to params, since Lombok
          # never synthesises accessors for static fields.
          next if field_static?(member, source)
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
        has_setter = lombok_setters || setter_targets.includes?(name)
        FieldInfo.new(name, access, has_setter, init)
      end
    end

    # True when `decl` carries a Lombok class annotation that synthesises
    # field accessors (`@Data` / `@Setter` / `@Value`). Such a class
    # exposes every instance field to request-body binding even though no
    # `setX(...)` method is written out in source.
    private def lombok_field_binding?(decl : LibTreeSitter::TSNode, source : String) : Bool
      each_annotation_on(decl, source) do |name|
        return true if LOMBOK_FIELD_BINDING_ANNOTATIONS.includes?(name)
      end
      false
    end

    # True when a `field_declaration`'s modifier list includes `static`.
    private def field_static?(decl : LibTreeSitter::TSNode, source : String) : Bool
      mods = find_modifiers(decl)
      return false unless mods
      count = LibTreeSitter.ts_node_child_count(mods)
      count.times do |i|
        child = LibTreeSitter.ts_node_child(mods, i.to_u32)
        return true if Noir::TreeSitter.node_text(child, source) == "static"
      end
      false
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
                                      class_fields : Hash(String, Array(FieldInfo)),
                                      constants : Hash(String, String),
                                      current_class : String) : Array(Param)
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
        current_format = emit_param_for(fp, method, source, verb, current_format, class_fields, constants, current_class, params)
      end
      params
    end

    private def emit_param_for(fp : LibTreeSitter::TSNode,
                               method : LibTreeSitter::TSNode,
                               source : String,
                               verb : String,
                               parameter_format : String?,
                               class_fields : Hash(String, Array(FieldInfo)),
                               constants : Hash(String, String),
                               current_class : String,
                               sink : Array(Param)) : String?
      type_node = Noir::TreeSitter.field(fp, "type")
      name_node = Noir::TreeSitter.field(fp, "name")
      return parameter_format unless type_node && name_node

      type_name = Noir::TreeSitter.node_text(type_node, source)
      arg_name = Noir::TreeSitter.node_text(name_node, source)

      # Annotation dispatch. A parameter may carry at most one of
      # `@PathVariable` / `@RequestBody` / `@RequestParam` /
      # `@RequestHeader` / `@CookieValue`; the first we see wins.
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
          when "CookieValue"
            ann_kind = :cookie
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
      when :cookie
        effective_format = "cookie"
      end
      return effective_format if effective_format.nil?

      default_value : String? = nil
      parameter_name = arg_name

      # Walk `@RequestParam(value = "x", defaultValue = "y")` / single-arg shorthand.
      if ann_node
        if args = Noir::TreeSitter.field(ann_node, "arguments")
          Noir::TreeSitter.each_named_child(args) do |arg|
            arg_type = Noir::TreeSitter.node_type(arg)
            if annotation_string_value_node?(arg_type)
              parameter_name = resolve_annotation_string_or_const(arg, source, constants, current_class)
              next
            end

            case arg_type
            when "element_value_pair"
              key = Noir::TreeSitter.field(arg, "key")
              val = Noir::TreeSitter.field(arg, "value")
              next unless key && val
              k = Noir::TreeSitter.node_text(key, source)
              case k
              when "value", "name"
                parameter_name = resolve_annotation_string_or_const(val, source, constants, current_class)
              when "defaultValue"
                default_value = resolve_annotation_string_value(val, source, constants, current_class)
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

    # Resolve either a string literal, a local Java constant, or a
    # qualified-identifier constant (`HttpHeaders.AUTHORIZATION`) to
    # the final header/param name. Matches the legacy normalisation.
    private def resolve_annotation_string_or_const(node : LibTreeSitter::TSNode,
                                                   source : String,
                                                   constants : Hash(String, String),
                                                   current_class : String) : String
      resolve_annotation_string_value(node, source, constants, current_class) || Noir::TreeSitter.node_text(node, source)
    end

    private def resolve_annotation_string_value(node : LibTreeSitter::TSNode,
                                                source : String,
                                                constants : Hash(String, String),
                                                current_class : String,
                                                depth = 0) : String?
      return if depth > 16

      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        decode_string_literal(node, source)
      when "identifier", "field_access", "scoped_identifier"
        text = Noir::TreeSitter.node_text(node, source)
        return normalise_http_header_constant(text) if text.starts_with?("HttpHeaders.")

        resolve_constant_reference(text, constants, current_class)
      when "binary_expression"
        return unless Noir::TreeSitter.node_text(node, source).includes?("+")
        left = Noir::TreeSitter.field(node, "left")
        right = Noir::TreeSitter.field(node, "right")
        return unless left && right

        left_value = resolve_annotation_string_value(left, source, constants, current_class, depth + 1)
        right_value = resolve_annotation_string_value(right, source, constants, current_class, depth + 1)
        return unless left_value && right_value

        "#{left_value}#{right_value}"
      when "parenthesized_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          if value = resolve_annotation_string_value(child, source, constants, current_class, depth + 1)
            return value
          end
        end
      end
    end

    private def resolve_constant_reference(name : String,
                                           constants : Hash(String, String),
                                           current_class : String) : String?
      unless current_class.empty?
        if resolved = constants["#{current_class}.#{name}"]?
          return resolved
        end
      end

      constants[name]?
    end

    private def annotation_string_value_node?(node_type : String) : Bool
      node_type == "string_literal" ||
        node_type == "identifier" ||
        node_type == "field_access" ||
        node_type == "scoped_identifier" ||
        node_type == "binary_expression" ||
        node_type == "parenthesized_expression"
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

    # Process-wide shared cache of DTO field extractions, keyed by
    # absolute file path. Multiple Java analyzers (Spring, JAX-RS,
    # Quarkus, Dropwizard, Micronaut) typically scan the same
    # codebase concurrently — without sharing, each builds its own
    # `DtoIndex` and re-parses every DTO file independently.
    # Promoting the cache to class scope means the Nth analyzer
    # picks up the previously-extracted fields for free.
    #
    # File contents don't change during a noir run, so this is
    # safe in production. Tests inside the same Crystal process
    # use unique fixture paths per scenario, so cross-test
    # contamination doesn't occur in practice; `clear_cache!` is
    # exposed anyway for any test setup that wants explicit
    # determinism.
    @@shared_cache = Hash(String, Index).new
    @@shared_cache_mutex = Mutex.new

    def self.clear_cache!
      @@shared_cache_mutex.synchronize { @@shared_cache.clear }
    end

    def initialize
    end

    # Build the DTO index visible to the Spring controller at `path`.
    # Callers pass `content` (already read once) to avoid a redundant
    # disk read for the current file. Cross-file traversal is
    # delegated to `Noir::ImportGraph` so this stays a thin
    # language-specific cache.
    def build_for(path : String, content : String) : Index
      Noir::TreeSitter.parse_java(content) do |root|
        return build_for_with_root(path, content, root)
      end
      Index.new
    end

    # `build_for_with_root(path, content, root)` — same as
    # `build_for` but uses a pre-parsed root for the current file's
    # extractions (`extract_package_name`, `extract_imports`, the
    # current file's `extract_class_fields`). Sibling files still
    # parse independently — but sibling parses go through the
    # process-wide cache so concurrent analyzers don't double-up.
    def build_for_with_root(path : String, content : String, root : LibTreeSitter::TSNode) : Index
      result = Index.new
      package_name = TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
      imports = TreeSitterJavaParameterExtractor.extract_imports_from(root, content)

      # Seed the shared cache for the current file from the
      # already-parsed root so this and any concurrent analyzer's
      # `related_files` loop reuses it.
      current_fields = TreeSitterJavaParameterExtractor.extract_class_fields_from(root, content)
      @@shared_cache_mutex.synchronize do
        @@shared_cache[path] ||= current_fields
      end

      Noir::ImportGraph.related_files(path, package_name, imports, "java") do |file|
        merge!(result, classes_in(file, path, content))
      end

      result
    end

    private def classes_in(file : String, current_path : String, current_content : String) : Index
      cached = @@shared_cache_mutex.synchronize { @@shared_cache[file]? }
      return cached if cached

      fields = parse_classes_for(file, current_path, current_content)

      # Multiple analyzers may race here on a cache miss — the
      # `||=` keeps whichever wrote first; the loser silently
      # discards its parse. Acceptable cost vs the per-file lock
      # complexity that strict single-parse would require.
      @@shared_cache_mutex.synchronize do
        @@shared_cache[file] ||= fields
        @@shared_cache[file]
      end
    end

    private def parse_classes_for(file : String, current_path : String, current_content : String) : Index
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

    private def merge!(into : Index, src : Index)
      src.each do |name, fields|
        into[name] ||= fields
      end
    end
  end
end
