require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "../models/code_locator"
require "./extraction_result_cache"
require "./import_graph"
require "./java_route_extractor_ts"
require "../utils/text_file"
require "../utils/jvm_literal"
require "../utils/jackson_naming"

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

    # Scalar types Spring binds directly from a single request value
    # (query string, form field, or — when annotated — path segment).
    # Superset of `PRIMITIVE_TYPES`: covers the remaining numeric/date
    # wrappers and `MultipartFile` so an un-annotated `Integer[] ids` or
    # `BigDecimal amount` handler argument surfaces as a parameter
    # instead of being silently dropped. Array (`Integer[]`), varargs,
    # and single-type-argument collection forms (`List<Long>`,
    # `Optional<String>`) all reduce to their element type before lookup
    # via `simple_param_base`. Framework argument-resolver types (Model,
    # HttpServletRequest, Pageable, Authentication, Principal,
    # BindingResult, …) are deliberately absent — they are resolved by
    # Spring, not bound from one request value. (`HttpServletRequest` and
    # `Pageable` still surface what they read; see `emit_param_for`.)
    SIMPLE_PARAM_TYPES = Set{
      "long", "int", "integer", "short", "byte", "double", "float",
      "boolean", "char", "character", "string", "bigdecimal", "biginteger",
      "number", "uuid", "date", "localdate", "localdatetime", "localtime",
      "instant", "multipartfile",
    }

    # Parameter annotations whose value is supplied by a Spring argument
    # resolver, not bound from the HTTP request the client controls. A
    # parameter carrying one of these is NOT an attack-surface input even
    # when its type is a bindable DTO (the classic `@AuthenticationPrincipal
    # User user`), so it must be excluded from the un-annotated
    # implicit-binding path. Validation annotations (`@Valid`, `@Min`, …)
    # are intentionally absent — they leave binding semantics untouched.
    INJECTED_PARAM_ANNOTATIONS = Set{
      "AuthenticationPrincipal", "CurrentUser", "CurrentSecurityContext",
      "SessionAttribute", "RequestAttribute",
    }

    # Subset of servlet types whose method body is scanned for
    # `request.getParameter("x")` / `request.getHeader("x")` calls.
    SERVLET_REQUEST_TYPES = Set{"HttpServletRequest"}

    # `simple_param_base` of the types Spring fills from a multipart part:
    # always the request body, whatever the annotation or verb.
    MULTIPART_TYPES = Set{"multipartfile", "part"}

    # Types a `@RequestParam` / `@RequestHeader` fills with *every* request
    # value. They name no single input, so they emit nothing.
    MAP_LIKE_TYPES = Set{"Map", "HashMap", "LinkedHashMap", "MultiValueMap", "LinkedMultiValueMap", "HttpHeaders"}

    # Lookups by key on one of those maps (`params.get("key")`,
    # `headers.getFirst("X-Trace")`).
    MAP_ACCESSORS = {"get", "getFirst", "getOrDefault", "containsKey", "getValuesAsList"}

    # Request parameters `PageableHandlerMethodArgumentResolver` reads.
    PAGEABLE_PARAMS = {"page", "size", "sort"}

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
      "Content-Md5"      => "Content-MD5",
      "Dnt"              => "DNT",
      "Etag"             => "ETag",
      "Te"               => "TE",
      "Www-Authenticate" => "WWW-Authenticate",
      "X-Frame-Options"  => "X-Frame-Options",
      "X-Xss-Protection" => "X-XSS-Protection",
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
      # Wire name in a JSON body: `@JsonProperty("display_name")`, else
      # `name` (or its `@JsonNaming` translation).
      property json_name : String
      # The JSON key is settled by `@JsonProperty` or the class `@JsonNaming`;
      # the module-wide Jackson default leaves it alone.
      property? json_name_fixed : Bool = false
      # Declared Java type as written (`Pager`, `MultipartFile[]`), "" when unknown.
      getter type_name : String
      # Jackson `@JsonUnwrapped(prefix, suffix)`: the field has no key of its
      # own, its type's properties sit inline in the parent object.
      # `TreeSitterJavaDtoIndex` replaces such a field with those properties.
      # A nil affix was written as something other than a string literal.
      getter unwrap : {String?, String?}?
      # Jackson `@JsonIgnore` on the field or one of its accessors: a JSON
      # body never binds it. Form/query binding (`WebDataBinder`) ignores
      # Jackson annotations, so it still binds there.
      getter? json_ignored : Bool

      def initialize(@name, @access_modifier, @has_setter, @init_value, json_name : String? = nil, @type_name = "",
                     @unwrap = nil, @json_ignored = false)
        @json_name = json_name || @name
        @json_name_fixed = !json_name.nil?
      end

      # Jackson renames apply to JSON bodies only; form/query binding goes
      # through Spring's `WebDataBinder`, which uses the Java name.
      def name_for(format : String) : String
        format == "json" ? @json_name : @name
      end
    end

    private struct ModelAttributeSupplier
      getter name : String
      getter type_name : String

      def initialize(@name, @type_name)
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
        fields = apply_json_naming(collect_class_fields(body, source, lombok_setters), json_naming_of(decl, source))
        results[class_name] = fields unless fields.empty?
      end
      # Java records: the header components ARE the bindable fields (a
      # record can't declare extra instance state), bound through the
      # canonical constructor for both JSON and form requests. Records are
      # an increasingly common request-DTO shape, so index their
      # components too. Walked separately from `walk_class_containers` so
      # the shared class/interface walker's callers stay record-free.
      if source.includes?("record ")
        walk_record_declarations(root) do |decl|
          name_node = Noir::TreeSitter.field(decl, "name")
          next unless name_node
          class_name = Noir::TreeSitter.node_text(name_node, source)
          fields = apply_json_naming(collect_record_fields(decl, source), json_naming_of(decl, source))
          results[class_name] = fields unless fields.empty? || results.has_key?(class_name)
        end
      end
      results
    end

    # Apply a class-level Jackson naming strategy to the fields that have no
    # explicit `@JsonProperty`, and mark every field settled either way.
    def apply_json_naming(fields : Array(FieldInfo), strategy : String?) : Array(FieldInfo)
      return fields unless strategy
      fields.map do |field|
        field.json_name = Noir::JacksonNaming.translate(field.name, strategy) unless field.json_name_fixed?
        field.json_name_fixed = true
        field
      end
    end

    private def json_naming_of(decl : LibTreeSitter::TSNode, source : String) : String?
      return unless ann = annotation_node_on(decl, source, "JsonNaming")
      Noir::JacksonNaming.annotation_strategy(Noir::TreeSitter.node_text(ann, source))
    end

    private def walk_record_declarations(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node) if Noir::TreeSitter.node_type(node) == "record_declaration"
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_record_declarations(child, &block)
      end
    end

    # Collect a record's component list as bindable fields. Each component
    # is a `formal_parameter` (`record Foo(String a, int b)`); the
    # canonical constructor makes every one settable from a request, so
    # they bind regardless of HTTP method or content type.
    private def collect_record_fields(decl : LibTreeSitter::TSNode, source : String) : Array(FieldInfo)
      fields = [] of FieldInfo
      params = Noir::TreeSitter.field(decl, "parameters")
      return fields unless params
      Noir::TreeSitter.each_named_child(params) do |component|
        next unless Noir::TreeSitter.node_type(component) == "formal_parameter"
        name_node = Noir::TreeSitter.field(component, "name")
        next unless name_node
        name = Noir::TreeSitter.node_text(name_node, source)
        next if name.empty?
        type_name = Noir::TreeSitter.field(component, "type").try { |node| Noir::TreeSitter.node_text(node, source) } || ""
        fields << FieldInfo.new(name, "public", true, "", json_property_name(component, source), type_name,
          json_unwrap(component, source), json_ignore?(component, source))
      end
      fields
    end

    # `@JsonProperty("wire_name")` / `@JsonProperty(value = "wire_name")` on
    # a field or record component; nil when absent or nameless.
    private def json_property_name(decl : LibTreeSitter::TSNode, source : String) : String?
      return unless ann = annotation_node_on(decl, source, "JsonProperty")
      annotation_string_arg(ann, source).presence
    end

    # `@JsonIgnore` (not `@JsonIgnore(false)`) on a field or accessor.
    private def json_ignore?(decl : LibTreeSitter::TSNode, source : String) : Bool
      return false unless ann = annotation_node_on(decl, source, "JsonIgnore")
      !annotation_text(ann, source).matches?(/\(\s*(?:value\s*=\s*)?false\s*\)/)
    end

    # `{prefix, suffix}` of a `@JsonUnwrapped` field or record component
    # (both "" by default, nil when not a string literal); nil when absent
    # or `enabled = false`.
    private def json_unwrap(decl : LibTreeSitter::TSNode, source : String) : {String?, String?}?
      return unless ann = annotation_node_on(decl, source, "JsonUnwrapped")
      prefix : String? = ""
      suffix : String? = ""
      if args = Noir::TreeSitter.field(ann, "arguments")
        Noir::TreeSitter.each_named_child(args) do |arg|
          next unless Noir::TreeSitter.node_type(arg) == "element_value_pair"
          key = Noir::TreeSitter.field(arg, "key").try { |node| Noir::TreeSitter.node_text(node, source) }
          val = Noir::TreeSitter.field(arg, "value")
          next unless key && val
          return if key == "enabled" && Noir::TreeSitter.node_text(val, source) == "false"
          literal = decode_string_literal(val, source) if Noir::TreeSitter.node_type(val) == "string_literal"
          prefix = literal if key == "prefix"
          suffix = literal if key == "suffix"
        end
      end
      {prefix, suffix}
    end

    # Simple names of the `@interface` types declared in `source` that are
    # meta-annotated with an injected-argument annotation
    # (`@AuthenticationPrincipal public @interface CurrentMember {}`).
    # Spring resolves such a parameter annotation like the one it carries,
    # so callers pass these back as `injected_annotations`.
    def extract_injected_annotation_types_from(root : LibTreeSitter::TSNode, source : String) : Array(String)
      names = [] of String
      Noir::TreeSitter.walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "annotation_type_declaration"
        next unless name_node = Noir::TreeSitter.field(node, "name")
        each_annotation_on(node, source) do |ann|
          if INJECTED_PARAM_ANNOTATIONS.includes?(ann)
            names << Noir::TreeSitter.node_text(name_node, source)
            break
          end
        end
      end
      names
    end

    # Map each `class` to the simple name of its superclass
    # (`{"Owner" => "Person"}` for `class Owner extends Person`). Drives
    # cross-file DTO inheritance: a command object that extends a base
    # entity binds the parent's fields too, so the index merges them in
    # via `TreeSitterJavaDtoIndex`. Interfaces are skipped — only the
    # single `extends` superclass carries bindable fields.
    def extract_class_supertypes_from(root : LibTreeSitter::TSNode, source : String) : Hash(String, String)
      results = Hash(String, String).new
      walk_class_containers(root) do |decl|
        next unless Noir::TreeSitter.node_type(decl) == "class_declaration"
        name_node = Noir::TreeSitter.field(decl, "name")
        next unless name_node
        super_node = Noir::TreeSitter.field(decl, "superclass")
        next unless super_node
        super_name = simple_superclass_name(Noir::TreeSitter.node_text(super_node, source))
        next if super_name.empty?
        results[Noir::TreeSitter.node_text(name_node, source)] = super_name
      end
      results
    end

    # `extends com.example.Base<T>` -> `Base`. The tree-sitter
    # `superclass` node text carries the `extends` keyword, an optional
    # package qualifier, and optional generic arguments — strip all
    # three down to the simple type name the field index is keyed on.
    private def simple_superclass_name(text : String) : String
      name = text.strip
      name = name.lchop("extends").strip if name.starts_with?("extends")
      name = name.split('<', 2).first
      name = name.split('.').last
      name.strip
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
    def extract_method_parameters_from(root : LibTreeSitter::TSNode,
                                       source : String,
                                       class_name : String,
                                       method_name : String,
                                       verb : String,
                                       parameter_format : String?,
                                       class_fields : Hash(String, Array(FieldInfo)),
                                       target_line : Int32? = nil,
                                       constants : Hash(String, String)? = nil,
                                       index : FileIndex? = nil,
                                       injected_annotations : Set(String)? = nil,
                                       converted_types : Set(String)? = nil,
                                       disallowed_fields : Array(String)? = nil) : Array(Param)
      index ||= build_file_index(root, source)
      method = find_method(index, class_name, method_name, target_line)
      return [] of Param unless method
      # `constants` is file-scoped and identical for every route in a
      # file. Callers that emit many routes per file (spring.cr) build it
      # once and pass it in; the nil default keeps every other analyzer's
      # call site working by recomputing it here.
      resolved_constants = constants || TreeSitterJavaRouteExtractor.extract_string_constants_from(root, source)
      model_attributes = index.suppliers[class_name] ||= model_attribute_suppliers(root, source, class_name)
      collect_method_params(method, source, verb, parameter_format, class_fields, resolved_constants, class_name, model_attributes,
        injected_annotations || Set(String).new, converted_types || Set(String).new, disallowed_fields || [] of String)
    end

    # Per-file memo for callers that look up many routes in one parsed
    # file (spring.cr). Without it every route re-walked the whole tree
    # to find its method and re-scanned every method of its class for
    # `@ModelAttribute` suppliers: quadratic in a controller's size.
    class FileIndex
      # "Class#method" -> every same-named method, in tree order.
      getter methods = Hash(String, Array(LibTreeSitter::TSNode)).new { |hash, key| hash[key] = [] of LibTreeSitter::TSNode }
      getter suppliers = Hash(String, Array(ModelAttributeSupplier)).new
    end

    def build_file_index(root : LibTreeSitter::TSNode, source : String) : FileIndex
      index = FileIndex.new
      walk_class_containers(root) do |decl|
        name_node = Noir::TreeSitter.field(decl, "name")
        body = Noir::TreeSitter.field(decl, "body")
        next unless name_node && body
        class_name = Noir::TreeSitter.node_text(name_node, source)
        Noir::TreeSitter.each_named_child(body) do |member|
          next unless Noir::TreeSitter.node_type(member) == "method_declaration"
          next unless mn = Noir::TreeSitter.field(member, "name")
          index.methods["#{class_name}##{Noir::TreeSitter.node_text(mn, source)}"] << member
        end
      end
      index
    end

    # Find `@*Mapping` annotation on (class_name, method_name) and
    # read its `consumes = ...` attribute. Returns "form" / "json" /
    # nil — matches `spring.cr`'s legacy helper semantics so the
    # analyzer can swap this in without behaviour drift.
    def extract_consumes_from(root : LibTreeSitter::TSNode, source : String, class_name : String, method_name : String,
                              index : FileIndex? = nil) : String?
      method = find_method(index || build_file_index(root, source), class_name, method_name)
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
    # Locate the `method_declaration` named `method_name` inside class
    # `class_name`. When `target_line` is given (the route's mapping
    # annotation row, 0-based) it disambiguates overloaded handlers: the
    # annotation sits inside the *correct* overload's node span, so the
    # method whose `[start_row, end_row]` range contains `target_line`
    # wins. Without a line hint — or when no overload contains it — the
    # first same-named method is returned, preserving prior behaviour.
    private def find_method(index : FileIndex,
                            class_name : String,
                            method_name : String,
                            target_line : Int32? = nil) : LibTreeSitter::TSNode?
      candidates = index.methods["#{class_name}##{method_name}"]?
      return unless candidates
      if line = target_line
        candidates.each do |member|
          return member if line >= Noir::TreeSitter.node_start_row(member) && line <= Noir::TreeSitter.node_end_row(member)
        end
      end
      candidates.first
    end

    private def find_class(root : LibTreeSitter::TSNode,
                           source : String,
                           class_name : String) : LibTreeSitter::TSNode?
      result : LibTreeSitter::TSNode? = nil
      walk_class_containers(root) do |decl|
        next if result
        name_node = Noir::TreeSitter.field(decl, "name")
        next unless name_node
        result = decl if Noir::TreeSitter.node_text(name_node, source) == class_name
      end
      result
    end

    private def model_attribute_suppliers(root : LibTreeSitter::TSNode,
                                          source : String,
                                          class_name : String) : Array(ModelAttributeSupplier)
      suppliers = [] of ModelAttributeSupplier
      class_decl = find_class(root, source, class_name)
      return suppliers unless class_decl
      body = Noir::TreeSitter.field(class_decl, "body")
      return suppliers unless body

      Noir::TreeSitter.each_named_child(body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "method_declaration"
        ann = annotation_node_on(member, source, "ModelAttribute")
        next unless ann

        return_type = method_return_type(member, source)
        unless return_type.empty? || return_type == "void"
          attr_name = annotation_string_arg(ann, source) || default_model_attribute_name(return_type)
          if path_only_model_attribute_supplier?(member, source)
            suppliers << ModelAttributeSupplier.new(attr_name, simple_type_name(return_type))
          end
        end

        suppliers.concat(model_put_suppliers(member, source))
      end

      suppliers.uniq { |supplier| {supplier.name, supplier.type_name} }
    end

    private def model_put_suppliers(method : LibTreeSitter::TSNode,
                                    source : String) : Array(ModelAttributeSupplier)
      suppliers = [] of ModelAttributeSupplier
      text = Noir::TreeSitter.node_text(method, source)
      declarations = Hash(String, String).new

      text.scan(/\b([A-Z][A-Za-z0-9_.$]*(?:\s*<[^;=()]*>)?)\s+([a-z][A-Za-z0-9_]*)\s*=/m) do |match|
        declarations[match[2]] = simple_type_name(match[1])
      end

      text.scan(/\b[A-Za-z_][A-Za-z0-9_]*\.put\(\s*"([^"]+)"\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/m) do |match|
        attr_name = match[1]
        var_name = match[2]
        if type_name = declarations[var_name]?
          suppliers << ModelAttributeSupplier.new(attr_name, type_name)
        end
      end

      suppliers
    end

    private def path_only_model_attribute_supplier?(method : LibTreeSitter::TSNode, source : String) : Bool
      params = Noir::TreeSitter.field(method, "parameters")
      return false unless params

      saw_path_variable = false
      Noir::TreeSitter.each_named_child(params) do |param|
        next unless Noir::TreeSitter.node_type(param) == "formal_parameter"
        next if framework_model_output_param?(param, source)

        ann = annotation_node_on(param, source, "PathVariable")
        return false unless ann
        return false if annotation_text(ann, source).includes?("required = false") ||
                        annotation_text(ann, source).includes?("required=false")
        saw_path_variable = true
      end

      saw_path_variable
    end

    private def framework_model_output_param?(param : LibTreeSitter::TSNode, source : String) : Bool
      type_node = Noir::TreeSitter.field(param, "type")
      return false unless type_node

      type_name = simple_type_name(Noir::TreeSitter.node_text(type_node, source)).downcase
      type_name == "map" || type_name == "model" || type_name == "modelmap"
    end

    private def method_return_type(method : LibTreeSitter::TSNode, source : String) : String
      if type_node = Noir::TreeSitter.field(method, "type")
        return simple_type_name(Noir::TreeSitter.node_text(type_node, source))
      end

      ""
    end

    private def annotation_node_on(decl : LibTreeSitter::TSNode,
                                   source : String,
                                   annotation_name : String) : LibTreeSitter::TSNode?
      mods = find_modifiers(decl)
      return unless mods
      Noir::TreeSitter.each_named_child(mods) do |ann|
        ty = Noir::TreeSitter.node_type(ann)
        next unless ty == "annotation" || ty == "marker_annotation"
        n = Noir::TreeSitter.field(ann, "name")
        next unless n
        return ann if simple_name(Noir::TreeSitter.node_text(n, source)) == annotation_name
      end
      nil
    end

    private def annotation_string_arg(ann : LibTreeSitter::TSNode, source : String) : String?
      args = Noir::TreeSitter.field(ann, "arguments")
      return unless args

      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "string_literal"
          return decode_string_literal(arg, source)
        when "element_value_pair"
          key = Noir::TreeSitter.field(arg, "key")
          val = Noir::TreeSitter.field(arg, "value")
          next unless key && val
          next unless Noir::TreeSitter.node_text(key, source) == "value" ||
                      Noir::TreeSitter.node_text(key, source) == "name"
          return decode_string_literal(val, source) if Noir::TreeSitter.node_type(val) == "string_literal"
        end
      end
      nil
    end

    private def annotation_text(ann : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.node_text(ann, source)
    end

    private def default_model_attribute_name(type_name : String) : String
      simple = simple_type_name(type_name)
      return "" if simple.empty?

      simple[0].downcase.to_s + simple[1..]
    end

    private def simple_type_name(type_name : String) : String
      name = type_name.strip
      name = name.sub(/\A(?:public|protected|private|static|final|abstract)\s+/, "")
      if idx = name.index('<')
        name = name[...idx]
      end
      name = name.gsub(/\[\s*\]/, "")
      if idx = name.rindex('.')
        name = name[(idx + 1)..]
      end
      name.strip
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
      declared = [] of Tuple(String, String, String, String?, String, {String?, String?}?) # name, access, init_value, json_name, type, unwrap
      setter_targets = Set(String).new
      # Jackson drops a property any accessor `@JsonIgnore`s, unless another
      # one names it with `@JsonProperty` (the write-only password idiom:
      # `@JsonIgnore` getter, `@JsonProperty` setter).
      json_ignored = Set(String).new
      json_kept = Set(String).new
      # `@JsonProperty("hh") setH(..)`: the accessor names the property's key.
      renamed = Hash(String, String).new

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
          type_name = type_node ? Noir::TreeSitter.node_text(type_node, source) : ""
          dec = Noir::TreeSitter.field(member, "declarator")
          next unless dec
          name_node = Noir::TreeSitter.field(dec, "name")
          next unless name_node
          name = Noir::TreeSitter.node_text(name_node, source)
          init = ""
          if value_node = Noir::TreeSitter.field(dec, "value")
            init = Noir::TreeSitter.node_text(value_node, source)
          end
          declared << {name, access, init, json_property_name(member, source), type_name, json_unwrap(member, source)}
          json_ignored << name if json_ignore?(member, source)
          json_kept << name if annotation_node_on(member, source, "JsonProperty")
        when "method_declaration"
          mn = Noir::TreeSitter.field(member, "name")
          next unless mn
          name = Noir::TreeSitter.node_text(mn, source)
          accessor = name.match(/\A(?:get|set|is)([A-Z]\w*)\z/)
          property = accessor.try { |found| found[1][0].downcase.to_s + found[1][1..] }
          json_ignored << property if property && json_ignore?(member, source)
          # `@JsonSetter("encryptedValue") setEncryptedValueBase64(..)` binds
          # the key it names, whatever the method is called.
          {"JsonProperty", "JsonSetter"}.each do |binding|
            next unless ann = annotation_node_on(member, source, binding)
            named = annotation_string_arg(ann, source).presence
            json_kept << named if named
            if property
              json_kept << property
              renamed[property] ||= named if named
            end
          end
          next unless name.starts_with?("set") && name.size > 3
          # Convert `setFoo` → `foo` for field-name matching.
          base = name[3].downcase.to_s + name[4..]
          setter_targets << base
        end
      end

      declared.map do |name, access, init, json_name, type_name, unwrap|
        has_setter = lombok_setters || setter_targets.includes?(name)
        json_name ||= renamed[name]?
        ignored = json_ignored.includes?(name) && !json_kept.includes?(name) && !(json_name && json_kept.includes?(json_name))
        FieldInfo.new(name, access, has_setter, init, json_name, type_name, unwrap, ignored)
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
                                      current_class : String,
                                      model_attributes = [] of ModelAttributeSupplier,
                                      injected_annotations = Set(String).new,
                                      converted_types = Set(String).new,
                                      disallowed_fields = [] of String) : Array(Param)
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
        current_format = emit_param_for(fp, method, source, verb, current_format, parameter_format, class_fields, constants, current_class, params, model_attributes, injected_annotations, converted_types, disallowed_fields)
      end

      # A JSON body and a form body cannot share one request: a value Spring
      # binds implicitly next to a JSON `@RequestBody` (`create(type: String,
      # @RequestBody req: Ev)`) can only arrive on the query string.
      if params.any? { |param| param.param_type == "json" }
        params.map! do |param|
          param.param_type = "query" if param.param_type == "form"
          param
        end
      end

      # Collapse duplicate `(name, type)` params. A handler binding two
      # command objects that share an inherited field — e.g. an `Owner`
      # and a `Pet` both extending a base entity with `id` — otherwise
      # surfaces `id` once per object, but the wire form carries a
      # single `id`. Distinct types (path `id` vs query `id`) are kept.
      seen = Set({String, String}).new
      params.select! { |param| seen.add?({param.name, param.param_type}) }
      params
    end

    private def emit_param_for(fp : LibTreeSitter::TSNode,
                               method : LibTreeSitter::TSNode,
                               source : String,
                               verb : String,
                               parameter_format : String?,
                               method_format : String?,
                               class_fields : Hash(String, Array(FieldInfo)),
                               constants : Hash(String, String),
                               current_class : String,
                               sink : Array(Param),
                               model_attributes = [] of ModelAttributeSupplier,
                               injected_annotations = Set(String).new,
                               converted_types = Set(String).new,
                               disallowed_fields = [] of String) : String?
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
      injected_param = false
      validated_param = false
      model_attribute_name : String? = nil
      pageable_default : LibTreeSitter::TSNode? = nil
      if mods = find_modifiers(fp)
        Noir::TreeSitter.each_named_child(mods) do |ann|
          ty = Noir::TreeSitter.node_type(ann)
          next unless ty == "annotation" || ty == "marker_annotation"
          n = Noir::TreeSitter.field(ann, "name")
          next unless n
          sn = simple_name(Noir::TreeSitter.node_text(n, source))
          injected_param = true if INJECTED_PARAM_ANNOTATIONS.includes?(sn) || injected_annotations.includes?(sn)
          validated_param = true if sn == "Valid" || sn == "Validated"
          model_attribute_name = annotation_string_arg(ann, source) if sn == "ModelAttribute"
          pageable_default = ann if sn == "PageableDefault"
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
          when "RequestPart"
            # One multipart part: a file, or a value (usually JSON) a
            # message converter reads whole. Either way it is one body
            # input named after the part, never the DTO's fields.
            ann_kind = :part
            ann_node = ann
            break
          end
        end
      end

      return parameter_format if ann_kind == :path # legacy: @PathVariable is not emitted

      # An argument-resolver parameter (`@AuthenticationPrincipal`, …) with
      # no request-binding annotation is server-supplied, not a request
      # input — drop it before the implicit-binding path can expand its
      # (often DTO-typed) fields into phantom params.
      return parameter_format if ann_kind.nil? && injected_param
      if ann_kind.nil? && !validated_param &&
         supplied_model_attribute_param?(arg_name, type_name, model_attribute_name, model_attributes)
        return parameter_format
      end

      effective_format = parameter_format
      # A carried-over "json"/"header"/"cookie" format came from a
      # *previous* parameter's own annotation (`@RequestBody`,
      # `@RequestHeader`, `@CookieValue`) and describes how that
      # parameter was bound — it says nothing about how Spring binds
      # *this*, un-annotated one. Drop it here so the un-annotated
      # branch below recomputes the correct verb-based format ("form"
      # on POST, "query" otherwise) instead of mislabeling this
      # parameter with the previous one's transport. "query" is left
      # sticky on purpose: it already matches the implicit-binding
      # default and existing fixtures rely on the carry-over.
      #
      # A command object, `HttpServletRequest` or `Pageable` takes no part in
      # that carry-over at all: its location depends on the verb and the
      # method's `consumes`, not on which argument happens to precede it.
      simple_param = simple_bindable_param?(type_name)
      if ann_kind.nil? && !simple_param
        effective_format = method_format == "form" ? "form" : nil
      elsif ann_kind.nil? && (effective_format == "json" || effective_format == "header" || effective_format == "cookie")
        effective_format = nil
      end
      case ann_kind
      when :body
        # The body's media type comes from the method's `consumes`, never
        # from the carry-over of a preceding parameter's binding.
        effective_format = method_format || "json"
      when :query
        effective_format = "query"
      when :header
        effective_format = "header"
      when :cookie
        effective_format = "cookie"
      when :part
        effective_format = "form"
      end
      if effective_format.nil?
        # No parameter annotation and no `consumes` hint. Spring still
        # binds the argument implicitly:
        #   * a scalar (or array/collection of scalars) and a command
        #     object both bind from request values for every verb — query
        #     string on GET/DELETE/…, form body on POST;
        #   * a framework argument-resolver type (Model,
        #     HttpServletRequest, Pageable, Authentication, BindingResult,
        #     …) binds from neither and must not surface.
        # Emit only the first two kinds; recognise a command object by its
        # presence in the resolved DTO field map. POST keeps the legacy
        # "form" classification; other verbs use "query" (no implicit
        # request body). Applying this per-parameter — rather than
        # pre-seeding the whole method — lets an explicit `@RequestBody` on
        # the same POST resolve to "json" instead of being dragged along.
        bindable = simple_param || class_fields.has_key?(type_name) ||
                   SERVLET_REQUEST_TYPES.includes?(type_name) || pageable_type?(type_name)
        return parameter_format unless bindable
        effective_format = verb == "POST" ? "form" : "query"
      end
      # Format handed to the next argument; see the carry-over note above.
      carry_format = ann_kind == :body || ann_kind == :part || (ann_kind.nil? && !simple_param) ? parameter_format : effective_format
      # A multipart file is a body part even when `@RequestParam` names it.
      effective_format = "form" if multipart_type?(type_name)

      default_value : String? = nil
      parameter_name = arg_name

      # Walk `@RequestParam(value = "x", defaultValue = "y")` / single-arg shorthand.
      if ann_node
        if args = Noir::TreeSitter.field(ann_node, "arguments")
          Noir::TreeSitter.each_named_child(args) do |arg|
            arg_type = Noir::TreeSitter.node_type(arg)
            if annotation_string_value_node?(arg_type)
              parameter_name = resolve_annotation_string_value(arg, source, constants, current_class) || parameter_name
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
                parameter_name = resolve_annotation_string_value(val, source, constants, current_class) || parameter_name
              when "defaultValue"
                default_value = resolve_annotation_string_value(val, source, constants, current_class)
              end
            end
          end
        end
      end

      # An explicit single-value annotation binds one request value whatever
      # the type: Spring converts it (enum, `valueOf`/`from` value class).
      single_value = (ann_kind == :query || ann_kind == :header || ann_kind == :cookie || ann_kind == :part) &&
                     !MAP_LIKE_TYPES.includes?(simple_type_name(type_name))
      if simple_param || single_value
        sink << Param.new(parameter_name, default_value || "", effective_format)
      elsif SERVLET_REQUEST_TYPES.includes?(type_name)
        scan_accessor_calls(method, source, arg_name, {"getParameter" => effective_format, "getHeader" => "header"}, sink)
      elsif (ann_kind == :query || ann_kind == :header || ann_kind == :body) && MAP_LIKE_TYPES.includes?(simple_type_name(type_name))
        # A `@RequestParam Map` / `@RequestHeader HttpHeaders` / `@RequestBody
        # Map` holds every value; the ones the handler reads by literal key
        # are its inputs.
        # A form-encoded `@RequestBody MultiValueMap` is a form body; a
        # reassigned variable no longer holds the request's values.
        map_format = ann_kind == :body && simple_type_name(type_name).ends_with?("MultiValueMap") ? "form" : effective_format
        unless reassigned?(method, source, arg_name)
          scan_accessor_calls(method, source, arg_name, MAP_ACCESSORS.to_h { |accessor| {accessor, map_format} }, sink)
        end
      elsif ann_kind.nil? && pageable_type?(type_name)
        PAGEABLE_PARAMS.each do |name|
          sink << Param.new(name, pageable_default_value(pageable_default, name, source, constants, current_class) || "", "query")
        end
      elsif ann_kind.nil? || ann_kind == :body
        return carry_format unless fields = class_fields[type_name]? || class_fields[collection_element_type(type_name)]?
        # `@RequestBody` is deserialised by Jackson, which populates every
        # non-static instance field by reflection (and via
        # all-args/`@Builder` constructors) regardless of setter
        # visibility — so a Lombok `@Getter`-only or constructor-bound DTO
        # still binds all its fields. Form/model-attribute binding goes
        # through Spring's `WebDataBinder`, which needs a public field or a
        # setter, so keep that stricter gate for non-JSON formats.
        json_body = effective_format == "json"
        fields.each do |field|
          next unless json_body || field.access_modifier == "public" || field.has_setter?
          next if json_body && field.json_ignored?
          # `default_value` comes from an annotation and is already literal;
          # `init_value` is raw Java source and only becomes a value when it
          # is one. See `Noir::JvmLiteral`.
          expanded_default = default_value || Noir::JvmLiteral.value_of(field.init_value)
          # `WebDataBinder` binds a nested bean's properties by dotted path
          # (`pager.offset`), unless a registered `Formatter`/`Converter`
          # turns one value into it (`converted_types`). One level only;
          # JSON keeps the nested key.
          unless json_body || simple_bindable_param?(field.type_name) || converted_types.includes?(field.type_name)
            nested = class_fields[field.type_name]?
          end
          if nested
            nested.each do |sub|
              next unless sub.access_modifier == "public" || sub.has_setter?
              next if disallowed_field?("#{field.name}.#{sub.name}", disallowed_fields)
              sink << Param.new("#{field.name}.#{sub.name}", Noir::JvmLiteral.value_of(sub.init_value), effective_format)
            end
          else
            # `WebDataBinder#setDisallowedFields` drops the property from binding.
            next if !json_body && disallowed_field?(field.name_for(effective_format), disallowed_fields)
            field_format = !json_body && multipart_type?(field.type_name) ? "form" : effective_format
            sink << Param.new(field.name_for(effective_format), expanded_default, field_format)
          end
        end
      end

      carry_format
    end

    # Spring `PatternMatchUtils.simpleMatch`: `*` matches any run of characters.
    private def disallowed_field?(name : String, patterns : Array(String)) : Bool
      patterns.any? do |pattern|
        pattern.includes?('*') ? name.matches?(Regex.new("\\A#{pattern.split('*').map { |part| Regex.escape(part) }.join(".*")}\\z")) : name == pattern
      end
    end

    private def multipart_type?(type_name : String) : Bool
      MULTIPART_TYPES.includes?(simple_param_base(type_name))
    end

    private def pageable_type?(type_name : String) : Bool
      simple_type_name(type_name) == "Pageable"
    end

    # `@PageableDefault(size = 20, sort = "id")` default for one Pageable
    # request parameter (`value` aliases `size`).
    private def pageable_default_value(ann : LibTreeSitter::TSNode?, name : String, source : String,
                                       constants : Hash(String, String), current_class : String) : String?
      return unless ann
      return unless args = Noir::TreeSitter.field(ann, "arguments")
      Noir::TreeSitter.each_named_child(args) do |arg|
        if Noir::TreeSitter.node_type(arg) == "element_value_pair"
          key = Noir::TreeSitter.field(arg, "key").try { |node| Noir::TreeSitter.node_text(node, source) }
          next unless key == name || (name == "size" && key == "value")
          next unless val = Noir::TreeSitter.field(arg, "value")
          value = resolve_annotation_string_value(val, source, constants, current_class)
          value ||= Noir::TreeSitter.node_text(val, source) if Noir::TreeSitter.node_type(val).ends_with?("_literal")
          return value
        elsif name == "size"
          return Noir::TreeSitter.node_text(arg, source) # `@PageableDefault(20)`
        end
      end
    end

    private def supplied_model_attribute_param?(arg_name : String,
                                                type_name : String,
                                                model_attribute_name : String?,
                                                model_attributes : Array(ModelAttributeSupplier)) : Bool
      return false if model_attributes.empty?

      param_type = simple_type_name(type_name)
      model_attributes.any? do |supplier|
        supplier.type_name == param_type &&
          (supplier.name == arg_name || (!model_attribute_name.nil? && supplier.name == model_attribute_name))
      end
    end

    # True when `type_name` is a scalar Spring binds from one request
    # value, including its array (`Integer[]`), varargs, and
    # single-argument collection (`List<Long>`, `Optional<String>`)
    # forms. Drives both the un-annotated implicit-binding gate and the
    # final emit dispatch, so an annotated `@RequestParam Integer[] ids`
    # surfaces too (the bare `PRIMITIVE_TYPES` lookup missed array forms).
    private def simple_bindable_param?(type_name : String) : Bool
      SIMPLE_PARAM_TYPES.includes?(simple_param_base(type_name))
    end

    # Reduce a parameter type to its lower-cased element-type simple name:
    # strip a single-argument collection/`Optional` wrapper, array
    # brackets and varargs, then drop any package/outer-class qualifier.
    private def simple_param_base(type_name : String) : String
      base = type_name.strip
      if match = base.match(/\A(?:java\.util\.)?(?:List|Set|Collection|Iterable|Optional)\s*<\s*(.+?)\s*>\z/)
        base = match[1].strip
      end
      base = base.gsub(/\[\s*\]/, "")
      base = base.rstrip(". ")
      if idx = base.rindex('.')
        base = base[(idx + 1)..]
      end
      base.downcase
    end

    # Case-preserving counterpart to `simple_param_base`: strips the same
    # single-argument collection/`Optional` wrapper and array/varargs
    # brackets, but keeps the original casing so the result can be used
    # as a `class_fields` DTO-index lookup key (which is indexed by the
    # class's exact simple name, e.g. "ItemDto", not "itemdto"). Lets
    # `@RequestBody List<ItemDto> items` / `@RequestBody ItemDto[] items`
    # resolve to the same field set as a bare `@RequestBody ItemDto item`.
    private def collection_element_type(type_name : String) : String
      base = type_name.strip
      if match = base.match(/\A(?:java\.util\.)?(?:List|Set|Collection|Iterable|Optional)\s*<\s*(.+?)\s*>\z/)
        base = match[1].strip
      end
      base = base.gsub(/\[\s*\]/, "")
      base = base.rstrip(". ")
      if idx = base.rindex('.')
        base = base[(idx + 1)..]
      end
      base
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
    def normalise_http_header_constant(raw : String) : String
      return raw unless raw.starts_with?("HttpHeaders.")
      header_key = raw["HttpHeaders.".size..]
      normalised = header_key.split('_').map(&.capitalize).join('-')
      HTTP_HEADER_SPECIAL_CASES[normalised]? || normalised
    end

    # Walk a method body for `<arg>.<accessor>("x")` calls
    # (`request.getParameter("x")`, `params.get("key")`), turning each into
    # a Param whose location `accessors` maps the accessor to. `arg_name` is
    # the declared parameter. A same-class helper the handler hands the
    # argument to (`getKeys(keysStr, params)`) is read one level deep under
    # the name its own parameter gives it; a helper of another class is not.
    private def scan_accessor_calls(method : LibTreeSitter::TSNode,
                                    source : String,
                                    arg_name : String,
                                    accessors : Hash(String, String),
                                    sink : Array(Param),
                                    depth : Int32 = 0)
      body = Noir::TreeSitter.field(method, "body")
      return unless body
      Noir::TreeSitter.walk(body) do |node|
        next unless Noir::TreeSitter.node_type(node) == "method_invocation"
        name = Noir::TreeSitter.field(node, "name")
        args = Noir::TreeSitter.field(node, "arguments")
        next unless name && args
        method_name = Noir::TreeSitter.node_text(name, source)
        obj = Noir::TreeSitter.field(node, "object")

        if obj && Noir::TreeSitter.node_type(obj) == "identifier" && Noir::TreeSitter.node_text(obj, source) == arg_name
          next unless format = accessors[method_name]?
          next unless key = Noir::TreeSitter.first_named_child(args)
          next unless Noir::TreeSitter.node_type(key) == "string_literal"
          param_name = decode_string_literal(key, source)
          next if param_name.empty?
          # Match legacy dedupe: same-name params collapse.
          next if sink.any? { |p| p.name == param_name && p.param_type == format }
          sink << Param.new(param_name, "", format)
        elsif depth == 0 && (obj.nil? || Noir::TreeSitter.node_type(obj) == "this")
          positions = [] of Int32
          count = 0
          Noir::TreeSitter.each_named_child(args) do |arg|
            positions << count if Noir::TreeSitter.node_type(arg) == "identifier" && Noir::TreeSitter.node_text(arg, source) == arg_name
            count += 1
          end
          next if positions.empty?
          next unless helper = same_class_method(method, source, method_name, count)
          helper_params = [] of String
          Noir::TreeSitter.field(helper, "parameters").try do |fparams|
            Noir::TreeSitter.each_named_child(fparams) do |fp|
              next unless Noir::TreeSitter.node_type(fp) == "formal_parameter"
              helper_params << (Noir::TreeSitter.field(fp, "name").try { |n| Noir::TreeSitter.node_text(n, source) } || "")
            end
          end
          positions.each do |position|
            next unless helper_name = helper_params[position]?
            scan_accessor_calls(helper, source, helper_name, accessors, sink, depth + 1)
          end
        end
      end
    end

    # Whether `method`'s body assigns `name` (`body = loadOther();`).
    private def reassigned?(method : LibTreeSitter::TSNode, source : String, name : String) : Bool
      return false unless body = Noir::TreeSitter.field(method, "body")
      found = false
      Noir::TreeSitter.walk(body) do |node|
        next if found || Noir::TreeSitter.node_type(node) != "assignment_expression"
        left = Noir::TreeSitter.field(node, "left")
        found = true if left && Noir::TreeSitter.node_type(left) == "identifier" && Noir::TreeSitter.node_text(left, source) == name
      end
      found
    end

    # The only method named `name` with `arity` formal parameters declared
    # in `method`'s own class body; nil when there is none or overloads
    # make it ambiguous.
    private def same_class_method(method : LibTreeSitter::TSNode, source : String, name : String, arity : Int32) : LibTreeSitter::TSNode?
      return unless class_body = Noir::TreeSitter.parent(method)
      found : LibTreeSitter::TSNode? = nil
      Noir::TreeSitter.each_named_child(class_body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "method_declaration"
        next unless Noir::TreeSitter.field(member, "name").try { |n| Noir::TreeSitter.node_text(n, source) } == name
        params = 0
        Noir::TreeSitter.field(member, "parameters").try do |fparams|
          Noir::TreeSitter.each_named_child(fparams) { |fp| params += 1 if Noir::TreeSitter.node_type(fp) == "formal_parameter" }
        end
        next unless params == arity
        return if found
        found = member
      end
      found
    end

    private def decode_string_literal(node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          case Noir::TreeSitter.node_type(child)
          when "string_fragment"
            io << Noir::TreeSitter.node_text(child, source)
          when "escape_sequence"
            io << Noir::TreeSitter.unescape(Noir::TreeSitter.node_text(child, source))
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
    # File contents don't change *during* a run, which is what makes the
    # sharing safe. They do change *between* runs, and the key is a path,
    # so the entry from the previous scan of that path is what a second
    # scan reads. That is a scan-lifetime cache wearing a process-lifetime
    # coat, and it is why the registration below exists.
    @@shared_cache = Hash(String, Index).new
    # Per-file `class -> superclass simple name` map, cached alongside
    # the field index so a file is parsed once for both. Drives the
    # cross-file inheritance merge below.
    @@shared_super_cache = Hash(String, Hash(String, String)).new
    @@shared_cache_mutex = Mutex.new

    # Filesystem-derived memos must not survive into a second scan in the
    # same process (library use, watch mode, a CI daemon scanning one
    # checkout across a `git pull`). Same reasoning, same mechanism as
    # `ImportGraph`'s registration — this cache was simply never wired up,
    # so `ExtractionResultCache.clear_all` at the top of `analysis_endpoints`
    # did not reach it.
    #
    # The observable failure: scan a Spring app whose `PersonDto` has
    # `{name, email}`, change it to `{name, phone}`, scan the same path
    # again in the same process, and every endpoint taking that DTO as a
    # body still reports the deleted `email` and omits the added `phone`.
    Noir::ExtractionResultCache.register_clearer { clear_cache! }

    def self.clear_cache!
      @@shared_cache_mutex.synchronize do
        @@shared_cache.clear
        @@shared_super_cache.clear
      end
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
      # `supers[class] = superclass simple name`, `origin[class] = the
      # file that defined it`. The latter lets the inheritance pass
      # resolve a superclass through the *subclass's* imports — Owner
      # imports `model.Person`, even though the controller that pulled
      # Owner in never mentions the `model` package.
      supers = Hash(String, String).new
      origin = Hash(String, String).new

      package_name = TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
      imports = TreeSitterJavaParameterExtractor.extract_imports_from(root, content)

      # Seed the shared caches for the current file from the
      # already-parsed root so this and any concurrent analyzer's
      # `related_files` loop reuses it.
      current_fields = TreeSitterJavaParameterExtractor.extract_class_fields_from(root, content)
      current_supers = TreeSitterJavaParameterExtractor.extract_class_supertypes_from(root, content)
      @@shared_cache_mutex.synchronize do
        @@shared_cache[path] ||= current_fields
        @@shared_super_cache[path] ||= current_supers
      end

      Noir::ImportGraph.related_files(path, package_name, imports, "java") do |file|
        fields, file_supers = load_file(file)
        absorb!(result, supers, origin, fields, file_supers, file)
      end

      pull_superclass_files!(result, supers, origin) unless supers.empty?
      flatten_unwrapped!(result, origin)
      resolve_inheritance!(result, supers)
      result
    end

    # Replace every `@JsonUnwrapped` field with its type's properties
    # (prefix/suffix applied to the JSON name; the form name keeps the
    # nested `outer.inner` path a data binder would use). Runs on each
    # class's own fields, before inheritance merging, so every unwrapped
    # type is resolved the way Java resolves it from the file that declares
    # the field. A field whose type can't be pinned to one class, whose
    # affix isn't a literal, or that unwraps into itself is dropped: its own
    # name is never a key on the wire.
    private def flatten_unwrapped!(result : Index, origin : Hash(String, String))
      scopes = Hash(String, {String, Array(Noir::ImportGraph::ImportRef)}).new
      result.keys.each do |cls|
        next unless result[cls].any?(&.unwrap)
        file = origin[cls]? || next
        result[cls] = unwrapped_fields(file, cls, scopes, [] of {String, String}) || [] of TreeSitterJavaParameterExtractor::FieldInfo
      end
    end

    # `cls` (declared in `file`) with its unwrapped fields expanded; nil
    # when it is not found or already on the expansion path (a cycle).
    private def unwrapped_fields(file : String, cls : String,
                                 scopes : Hash(String, {String, Array(Noir::ImportGraph::ImportRef)}),
                                 path : Array({String, String})) : Array(TreeSitterJavaParameterExtractor::FieldInfo)?
      return if path.includes?({file, cls}) || path.size > MAX_UNWRAP_DEPTH
      own = load_file(file)[0][cls]? || return

      path << {file, cls}
      flat = [] of TreeSitterJavaParameterExtractor::FieldInfo
      own.each do |field|
        unless unwrap = field.unwrap
          flat << field
          next
        end
        prefix, suffix = unwrap
        next unless prefix && suffix
        target = unwrap_target(field)
        target_file = type_file_for(file, target, scopes) || next
        inner_fields = unwrapped_fields(target_file, target, scopes, path) || next
        inner_fields.each do |inner|
          flat << TreeSitterJavaParameterExtractor::FieldInfo.new("#{field.name}.#{inner.name}", inner.access_modifier,
            inner.has_setter?, inner.init_value, "#{prefix}#{inner.json_name}#{suffix}", inner.type_name, json_ignored: inner.json_ignored?)
        end
      end
      path.pop
      flat
    end

    MAX_UNWRAP_DEPTH = 8

    private def unwrap_target(field : TreeSitterJavaParameterExtractor::FieldInfo) : String
      name = field.type_name.split('<', 2).first.strip
      name.rpartition('.').last
    end

    # The file declaring the type `simple` as seen from `file`, in Java's
    # order: the file itself, a single-type import, the same package, then
    # on-demand imports (nil when none or more than one match).
    private def type_file_for(file : String, simple : String,
                              scopes : Hash(String, {String, Array(Noir::ImportGraph::ImportRef)})) : String?
      return file if load_file(file)[0].has_key?(simple)

      package_name, imports = scopes[file] ||= file_package_imports(file)
      basename = "#{simple}.java"
      if single = imports.find { |imp| !imp.wildcard? && imp.path.rpartition('.').last == simple }
        suffix = "/#{single.path.gsub('.', '/')}.java"
        found = nil
        Noir::ImportGraph.related_files(file, package_name, [single], "java") { |f| found ||= f if f.ends_with?(suffix) }
        return found
      end

      dir = File.dirname(file)
      candidates = [] of String
      Noir::ImportGraph.related_files(file, package_name, imports.select(&.wildcard?), "java") do |f|
        candidates << f if File.basename(f) == basename
      end
      candidates.find { |f| File.dirname(f) == dir } || (candidates.first if candidates.size == 1)
    end

    # Pull a file's `{fields, supertypes}` from the shared cache,
    # parsing it once on a miss. Both maps are populated together so a
    # DTO file is never parsed twice.
    private def load_file(file : String) : {Index, Hash(String, String)}
      cached_fields, cached_supers = @@shared_cache_mutex.synchronize do
        {@@shared_cache[file]?, @@shared_super_cache[file]?}
      end
      return {cached_fields, cached_supers} if cached_fields && cached_supers

      fields = Index.new
      supertypes = Hash(String, String).new
      body = file_body(file)
      Noir::TreeSitter.parse_java(body) do |root|
        fields = TreeSitterJavaParameterExtractor.extract_class_fields_from(root, body)
        supertypes = TreeSitterJavaParameterExtractor.extract_class_supertypes_from(root, body)
      end

      # Multiple analyzers may race here on a cache miss — the `||=`
      # keeps whichever wrote first; the loser silently discards its
      # parse. Acceptable cost vs the per-file lock complexity that
      # strict single-parse would require.
      @@shared_cache_mutex.synchronize do
        @@shared_cache[file] ||= fields
        @@shared_super_cache[file] ||= supertypes
        {@@shared_cache[file], @@shared_super_cache[file]}
      end
    rescue IO::Error
      {Index.new, Hash(String, String).new}
    end

    private def file_body(file : String) : String
      # Detector pre-warms a content cache for every scanned file
      # (size-bounded). Sibling/parent DTO files often live in that
      # cache already — `nil` falls back to a fresh disk read for
      # files outside the budget.
      CodeLocator.instance.content_for(file) ||
        Noir::TextFile.read(file)
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

    # Merge inherited fields into each subclass. First pulls in the
    # files that define still-unresolved superclasses (following
    # `extends` edges the controller never imported directly), then
    # folds each `extends` chain into a single flattened field list.
    private def resolve_inheritance!(result : Index, supers : Hash(String, String))
      return if supers.empty?

      memo = Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)).new
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
        # Already loaded (has fields or a recorded super) — its own
        # `extends` edge, if any, is queued separately.
        next if result.has_key?(sup) || supers.has_key?(sup)
        # Resolve each distinct superclass name at most once, even if
        # several subclasses share it or its file defines nothing
        # useful.
        next unless attempted.add?(sup)
        file = origin[cls]?
        next unless file

        pending.concat(load_superclass_files(result, supers, origin, file))
      end
    end

    # Walk the subclass file's own related files (siblings + imports)
    # and absorb any classes not seen yet. Returns the names added so
    # the caller can chase their `extends` edges in turn.
    private def load_superclass_files(result : Index,
                                      supers : Hash(String, String),
                                      origin : Hash(String, String),
                                      subclass_file : String) : Array(String)
      added = [] of String
      package_name, imports = file_package_imports(subclass_file)

      Noir::ImportGraph.related_files(subclass_file, package_name, imports, "java") do |file|
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
      Noir::TreeSitter.parse_java(body) do |root|
        package_name = TreeSitterJavaParameterExtractor.extract_package_name_from(root, body)
        imports = TreeSitterJavaParameterExtractor.extract_imports_from(root, body)
      end
      {package_name, imports}
    rescue IO::Error
      {"", [] of Noir::ImportGraph::ImportRef}
    end

    # Own fields plus the (already-flattened) superclass fields, deduped
    # by name so an overriding field wins. `visiting` guards against
    # `extends` cycles; `memo` keeps the walk linear.
    private def effective_fields(cls : String,
                                 result : Index,
                                 supers : Hash(String, String),
                                 memo : Hash(String, Array(TreeSitterJavaParameterExtractor::FieldInfo)),
                                 visiting : Set(String)) : Array(TreeSitterJavaParameterExtractor::FieldInfo)
      if cached = memo[cls]?
        return cached
      end

      own = result[cls]? || [] of TreeSitterJavaParameterExtractor::FieldInfo
      sup = supers[cls]?

      # Stop when there's no usable superclass to merge: missing, the
      # class itself, or already on the current resolution path (cycle
      # guard). Written as a positive `if` (rather than `unless` with a
      # negated condition) so `sup` still narrows to non-nil below.
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

    # Backstop against pathological `extends` graphs — far above any
    # real DTO hierarchy depth/fan-out.
    MAX_INHERITANCE_RESOLUTIONS = 512
  end
end
