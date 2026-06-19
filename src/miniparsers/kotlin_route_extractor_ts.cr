require "../ext/tree_sitter/tree_sitter"

module Noir
  # Tree-sitter-backed Kotlin route extractor.
  #
  # Scope for this first cut: Spring-style annotation routing —
  # class-level `@RequestMapping`-family annotations composing with
  # method-level mapping annotations. Mirrors `TreeSitterJavaRouteExtractor`
  # but for Kotlin's distinct AST shape (annotations live in
  # `modifiers`, functions use `function_declaration`, primary
  # constructors carry DTO fields, etc.).
  #
  # Covered:
  #
  #   * `@GetMapping`, `@PostMapping`, `@PutMapping`, `@DeleteMapping`,
  #     `@PatchMapping` — each fixes the HTTP verb
  #   * `@RequestMapping` — generic; verb from `method =
  #     RequestMethod.X` (single or array form), or GET when absent
  #   * Class-level mapping annotations contribute a prefix joined
  #     onto the per-method path with exactly one `/` separator
  #   * Path supplied positionally (`@GetMapping("/x")`) or via
  #     `value = "/x"` / `path = "/x"` keyword arguments, including
  #     string arrays (`value = ["/a", "/b"]`)
  #   * Multi-line annotations — the grammar eats whitespace for us
  #
  # Not covered yet (follow-ups):
  #
  #   * Ktor's DSL `routing { get("/x") { ... } }`. That's a
  #     different authoring style and lives in a separate walker.
  #   * Meta-annotations (custom annotations composing `@RequestMapping`).
  module TreeSitterKotlinRouteExtractor
    extend self

    # Spring mapping annotation names → HTTP verb. `nil` means look at
    # the annotation's `method =` argument. Same table as the Java
    # extractor for consistency.
    ANNOTATION_VERBS = {
      "GetMapping"     => "GET",
      "PostMapping"    => "POST",
      "PutMapping"     => "PUT",
      "DeleteMapping"  => "DELETE",
      "PatchMapping"   => "PATCH",
      "RequestMapping" => nil,
    }

    struct Route
      getter verb : String        # upper-cased HTTP verb
      getter path : String        # full path (class prefix + method path)
      getter class_name : String  # enclosing class simple name, or ""
      getter method_name : String # Kotlin function name, or "" when class-level only
      getter line : Int32         # 0-based line of the method annotation
      getter handler_reference : String?
      getter inline_callees : Array(NamedTuple(name: String, line: Int32))
      getter messaging_destinations : Array(String)

      def initialize(@verb, @path, @class_name, @method_name, @line, @handler_reference = nil,
                     @inline_callees = [] of NamedTuple(name: String, line: Int32),
                     @messaging_destinations = [] of String)
      end
    end

    struct ControllerInterfaceImplementation
      getter class_name : String
      getter interface_names : Array(String)
      getter path : String
      getter line : Int32

      def initialize(@class_name, @interface_names, @path, @line)
      end
    end

    struct GraphqlRoute
      getter operation_keyword : String
      getter root_kind : String
      getter field_name : String
      getter line : Int32
      getter class_name : String
      getter method_name : String
      getter arguments : Array(NamedTuple(name: String, type: String))

      def initialize(@operation_keyword, @root_kind, @field_name, @line, @class_name, @method_name, @arguments)
      end
    end

    def extract_routes(source : String, string_constants = Hash(String, String).new) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_kotlin(source) do |root|
        routes = extract_routes_from(root, source, string_constants)
      end
      routes
    end

    def extract_string_constants(source : String) : Hash(String, String)
      constants = Hash(String, String).new
      package_name = ""
      current_type = ""
      current_depth = 0
      # Scrubbed copy (strings/comments blanked, newlines preserved) for brace
      # counting, so a `}` inside a const string value can't close the type early.
      scrubbed_lines = visible_kotlin_code(source).lines

      source.each_line.with_index do |line, idx|
        if package_name.empty?
          if match = line.match(/^\s*package\s+([A-Za-z_][A-Za-z0-9_.]*)/)
            package_name = match[1]
          end
        end

        if match = line.match(/^\s*(?:class|object|interface)\s+([A-Za-z_][A-Za-z0-9_]*)/)
          current_type = match[1]
          current_depth = 0
        end

        if match = line.match(/\b(?:const\s+)?val\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*String)?\s*=\s*"([^"]*)"/)
          name = match[1]
          value = match[2]
          constants[name] ||= value
          unless current_type.empty?
            constants["#{current_type}.#{name}"] ||= value
            constants["#{package_name}.#{current_type}.#{name}"] ||= value unless package_name.empty?
          end
        end

        unless current_type.empty?
          structural = scrubbed_lines[idx]? || line
          current_depth += structural.count("{")
          current_depth -= structural.count("}")
          if current_depth <= 0 && structural.includes?("}")
            current_type = ""
            current_depth = 0
          end
        end
      end

      constants
    end

    # Resolve Kotlin string-template interpolations inside collected
    # constant values, e.g. `const val STATIC_URL = "$PUBLIC_URL/static"`
    # with `PUBLIC_URL = "/public"` becomes `/public/static`. The regex
    # capture in `extract_string_constants` stores the raw `$PUBLIC_URL`
    # text, so without this a path built from such a constant keeps the
    # literal `$VAR` (or, as an inline annotation literal, mis-parses it
    # as a `{VAR}` path placeholder). Unresolved references (e.g. Spring
    # `${config.property}` placeholders) are left untouched. Bounded
    # iterations resolve transitive chains.
    def expand_constant_interpolations(constants : Hash(String, String)) : Hash(String, String)
      return constants unless constants.any? { |_, v| v.includes?('$') }
      result = constants.dup
      3.times do
        changed = false
        result.each do |name, value|
          next unless value.includes?('$')
          expanded = expand_interpolation(value, result)
          if expanded != value
            result[name] = expanded
            changed = true
          end
        end
        break unless changed
      end
      result
    end

    private def expand_interpolation(value : String, constants : Hash(String, String)) : String
      value.gsub(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)/) do
        ident = $~[1]? || $~[2]?
        (ident && constants[ident]?) || $~[0]
      end
    end

    # `_from(root, source)` — accept a pre-parsed root so the Kotlin
    # Spring analyzer can amortise the parse across multiple
    # extractions on the same file. Tree lifetime is the caller's
    # responsibility.
    def extract_routes_from(root : LibTreeSitter::TSNode,
                            source : String,
                            string_constants = Hash(String, String).new,
                            local_string_constants : Hash(String, String)? = nil) : Array(Route)
      routes = [] of Route
      file_constants = local_string_constants || extract_string_constants(source)
      walk_classes(root, source, "", routes, string_constants, file_constants)
      collect_gateway_routes(source, string_constants, routes)
      collect_webflux_functional_routes(source, routes)
      routes
    end

    def extract_interface_routes_from(root : LibTreeSitter::TSNode,
                                      source : String,
                                      string_constants = Hash(String, String).new,
                                      local_string_constants : Hash(String, String)? = nil) : Hash(String, Array(Route))
      routes = Hash(String, Array(Route)).new { |hash, key| hash[key] = [] of Route }
      file_constants = local_string_constants || extract_string_constants(source)
      walk_interface_routes(root, source, routes, string_constants, file_constants)
      routes
    end

    def extract_controller_interface_implementations_from(root : LibTreeSitter::TSNode,
                                                          source : String,
                                                          string_constants = Hash(String, String).new,
                                                          local_string_constants : Hash(String, String)? = nil) : Array(ControllerInterfaceImplementation)
      implementations = [] of ControllerInterfaceImplementation
      file_constants = local_string_constants || extract_string_constants(source)
      walk_controller_interface_implementations(root, source, implementations, string_constants, file_constants)
      implementations
    end

    def extract_stomp_application_prefixes(source : String,
                                           string_constants = Hash(String, String).new,
                                           local_string_constants : Hash(String, String)? = nil) : Array(String)
      prefixes = [] of String
      file_constants = local_string_constants || extract_string_constants(source)
      each_method_call_arguments(source, "setApplicationDestinationPrefixes") do |args, _line|
        top_level_arguments(args).each do |arg|
          resolve_route_expressions(arg, string_constants, file_constants).each do |prefix|
            prefixes << prefix
          end
        end
      end
      prefixes.uniq
    end

    def extract_stomp_routes_from(root : LibTreeSitter::TSNode,
                                  source : String,
                                  string_constants = Hash(String, String).new,
                                  local_string_constants : Hash(String, String)? = nil,
                                  application_prefixes = [""]) : Array(Route)
      routes = [] of Route
      file_constants = local_string_constants || extract_string_constants(source)
      collect_stomp_handshake_routes(source, routes, string_constants, file_constants)
      walk_message_mapping_routes(root, source, string_constants, file_constants, application_prefixes, [""], routes)
      routes
    end

    def extract_graphql_routes_from(root : LibTreeSitter::TSNode,
                                    source : String,
                                    string_constants = Hash(String, String).new,
                                    local_string_constants : Hash(String, String)? = nil) : Array(GraphqlRoute)
      routes = [] of GraphqlRoute
      file_constants = local_string_constants || extract_string_constants(source)
      walk_graphql_mapping_routes(root, source, string_constants, file_constants, routes)
      routes
    end

    # ---- private helpers ----------------------------------------------

    private def walk_classes(node : LibTreeSitter::TSNode,
                             source : String,
                             outer_prefix : String,
                             routes : Array(Route),
                             string_constants : Hash(String, String),
                             local_string_constants : Hash(String, String))
      ty = Noir::TreeSitter.node_type(node)
      if ty == "class_declaration" || ty == "object_declaration" || ty == "interface_declaration"
        process_class(node, source, outer_prefix, [] of LibTreeSitter::TSNode, routes, string_constants, local_string_constants)
        return
      end

      # Walk children in order so we can pair stray leading
      # `prefix_expression` annotation chunks (a tree-sitter-kotlin
      # quirk on top-level annotated classes) with the next class
      # declaration. The grammar sometimes parses
      # `@RestController @RequestMapping("/x") class Foo` as two
      # siblings — a prefix_expression carrying the annotations, and
      # a class_declaration without `modifiers`. Falling through
      # `each_named_child` would lose the class-level mapping prefix.
      pending = [] of LibTreeSitter::TSNode
      orphan_class : Tuple(String, String)? = nil
      count = LibTreeSitter.ts_node_named_child_count(node)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(node, i.to_u32)
        case Noir::TreeSitter.node_type(child)
        when "class_declaration", "object_declaration", "interface_declaration"
          process_class(child, source, outer_prefix, pending, routes, string_constants, local_string_constants)
          orphan_class = recoverable_orphan_class(child, source, outer_prefix, pending, string_constants, local_string_constants)
          pending = [] of LibTreeSitter::TSNode
        when "prefix_expression"
          if recover_split_constructor_prefix(child, source, outer_prefix, routes, string_constants, local_string_constants)
            pending = [] of LibTreeSitter::TSNode
          else
            pending << child if prefix_expression_has_annotation?(child)
          end
          orphan_class = nil
        when "ERROR"
          if ctx = orphan_class
            class_name, class_prefix = ctx
            collect_recovered_function_routes(child, source, class_name, class_prefix, routes, string_constants, local_string_constants)
          else
            walk_classes(child, source, outer_prefix, routes, string_constants, local_string_constants)
          end
          pending = [] of LibTreeSitter::TSNode
          orphan_class = nil
        when "annotation"
          pending = [] of LibTreeSitter::TSNode unless orphan_class
        when "call_expression"
          if ctx = orphan_class
            class_name, class_prefix = ctx
            collect_recovered_function_routes(child, source, class_name, class_prefix, routes, string_constants, local_string_constants)
          else
            walk_classes(child, source, outer_prefix, routes, string_constants, local_string_constants)
          end
          pending = [] of LibTreeSitter::TSNode
          orphan_class = nil
        else
          pending = [] of LibTreeSitter::TSNode
          orphan_class = nil
          walk_classes(child, source, outer_prefix, routes, string_constants, local_string_constants)
        end
      end
    end

    private def recoverable_orphan_class(node : LibTreeSitter::TSNode,
                                         source : String,
                                         outer_prefix : String,
                                         pending : Array(LibTreeSitter::TSNode),
                                         string_constants : Hash(String, String),
                                         local_string_constants : Hash(String, String)) : Tuple(String, String)?
      return if class_body(node)
      return if feign_client?(node, source)
      return if abstract_type?(node, source)

      class_name = type_identifier_text(node, source)
      return if class_name.empty?

      class_prefix = class_mapping_prefix(node, source, pending, string_constants, local_string_constants)
      {class_name, join_paths(outer_prefix, class_prefix)}
    end

    private def abstract_type?(decl : LibTreeSitter::TSNode, source : String) : Bool
      if mods = find_modifiers(decl)
        Noir::TreeSitter.each_named_child(mods) do |child|
          return true if Noir::TreeSitter.node_text(child, source) == "abstract"
        end
      end
      false
    end

    private def recover_split_constructor_prefix(node : LibTreeSitter::TSNode,
                                                 source : String,
                                                 outer_prefix : String,
                                                 routes : Array(Route),
                                                 string_constants : Hash(String, String),
                                                 local_string_constants : Hash(String, String)) : Bool
      text = Noir::TreeSitter.node_text(node, source)
      return false unless text.includes?(" constructor")
      return false unless text.includes?(" fun ")
      return false if text.match(/\babstract\s+class\b/)
      match = text.match(/\bclass\s+([A-Za-z_][A-Za-z0-9_]*)\b/)
      return false unless match

      class_prefix = split_constructor_prefix(node, source, string_constants, local_string_constants)
      collect_recovered_function_routes(
        node, source, match[1], join_paths(outer_prefix, class_prefix), routes, string_constants, local_string_constants
      )
      true
    end

    private def split_constructor_prefix(node : LibTreeSitter::TSNode,
                                         source : String,
                                         string_constants : Hash(String, String),
                                         local_string_constants : Hash(String, String)) : String
      collect_stray_annotations(node, source).each do |entry|
        name, args = entry
        next unless ANNOTATION_VERBS.has_key?(name)
        next unless args
        buf = [] of String
        collect_string_values(args, source, buf, string_constants, local_string_constants)
        return buf.first unless buf.empty?
      end
      text = Noir::TreeSitter.node_text(node, source)
      if match = text.match(/@(?:[A-Za-z_][A-Za-z0-9_.]*\.)?RequestMapping\s*\(\s*"([^"]*)"/)
        return match[1]
      end
      ""
    end

    private def process_class(node : LibTreeSitter::TSNode,
                              source : String,
                              outer_prefix : String,
                              pending : Array(LibTreeSitter::TSNode),
                              routes : Array(Route),
                              string_constants : Hash(String, String),
                              local_string_constants : Hash(String, String))
      class_name = type_identifier_text(node, source)

      # `@FeignClient` (Spring Cloud) interfaces declare OUTBOUND remote
      # client calls with the same `@*Mapping` annotations a controller
      # uses — they are not server routes, so skip the whole declaration
      # to avoid emitting phantom inbound endpoints.
      return if feign_client?(node, source)

      class_prefix = class_mapping_prefix(node, source, pending, string_constants, local_string_constants)
      prefix = join_paths(outer_prefix, class_prefix)

      if body = class_body(node)
        Noir::TreeSitter.each_named_child(body) do |member|
          case Noir::TreeSitter.node_type(member)
          when "function_declaration"
            collect_function_routes(member, source, class_name, prefix, routes, string_constants, local_string_constants)
          when "class_declaration", "object_declaration", "interface_declaration"
            walk_classes(member, source, prefix, routes, string_constants, local_string_constants)
          end
        end
      end
    end

    private def walk_interface_routes(node : LibTreeSitter::TSNode,
                                      source : String,
                                      routes : Hash(String, Array(Route)),
                                      string_constants : Hash(String, String),
                                      local_string_constants : Hash(String, String),
                                      depth : Int32 = 0)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if interface_decl?(node, source)
        return if feign_client?(node, source)
        interface_name = type_identifier_text(node, source)
        unless interface_name.empty?
          class_prefix = class_mapping_prefix(node, source, [] of LibTreeSitter::TSNode, string_constants, local_string_constants)
          if body = class_body(node)
            Noir::TreeSitter.each_named_child(body) do |member|
              next unless Noir::TreeSitter.node_type(member) == "function_declaration"
              collect_function_routes(member, source, interface_name, class_prefix, routes[interface_name], string_constants, local_string_constants)
            end
          end
        end
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_interface_routes(child, source, routes, string_constants, local_string_constants, depth + 1)
      end
    end

    private def walk_controller_interface_implementations(node : LibTreeSitter::TSNode,
                                                          source : String,
                                                          implementations : Array(ControllerInterfaceImplementation),
                                                          string_constants : Hash(String, String),
                                                          local_string_constants : Hash(String, String),
                                                          depth : Int32 = 0)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "class_declaration" && !interface_decl?(node, source)
        interface_names = implemented_interface_names(node, source)
        if !interface_names.empty? && spring_controller_class?(node, source)
          class_name = type_identifier_text(node, source)
          class_prefix = class_mapping_prefix(node, source, [] of LibTreeSitter::TSNode, string_constants, local_string_constants)
          implementations << ControllerInterfaceImplementation.new(
            class_name, interface_names, class_prefix, Noir::TreeSitter.node_start_row(node)
          )
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_controller_interface_implementations(child, source, implementations, string_constants, local_string_constants, depth + 1)
      end
    end

    private def interface_decl?(decl : LibTreeSitter::TSNode, source : String) : Bool
      return false unless Noir::TreeSitter.node_type(decl) == "class_declaration" ||
                          Noir::TreeSitter.node_type(decl) == "interface_declaration"
      return true if Noir::TreeSitter.node_type(decl) == "interface_declaration"
      Noir::TreeSitter.node_text(decl, source).matches?(/\binterface\s+[A-Za-z_][A-Za-z0-9_]*/)
    end

    private def spring_controller_class?(decl : LibTreeSitter::TSNode, source : String) : Bool
      found = false
      each_annotation(decl, source) do |name, _args, _line|
        found = true if name == "Controller" || name == "RestController"
      end
      found
    end

    private def implemented_interface_names(decl : LibTreeSitter::TSNode, source : String) : Array(String)
      names = [] of String
      Noir::TreeSitter.each_named_child(decl) do |child|
        next unless Noir::TreeSitter.node_type(child).includes?("delegation")
        # Kotlin represents implemented interfaces as a bare `user_type`
        # delegation specifier. Superclasses are constructor invocations
        # (`BaseController()`), which are intentionally skipped here.
        Noir::TreeSitter.each_named_child(child) do |sub|
          next unless Noir::TreeSitter.node_type(sub) == "user_type"
          name = leaf_type_name(sub, source)
          names << name unless name.empty? || names.includes?(name)
        end
      end
      names
    end

    private def collect_recovered_function_routes(node : LibTreeSitter::TSNode,
                                                  source : String,
                                                  class_name : String,
                                                  class_prefix : String,
                                                  routes : Array(Route),
                                                  string_constants : Hash(String, String),
                                                  local_string_constants : Hash(String, String))
      if Noir::TreeSitter.node_type(node) == "function_declaration"
        collect_function_routes(node, source, class_name, class_prefix, routes, string_constants, local_string_constants)
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        collect_recovered_function_routes(child, source, class_name, class_prefix, routes, string_constants, local_string_constants)
      end
    end

    # True when the class/interface declaration carries a `@FeignClient`
    # annotation (Spring Cloud declarative HTTP client). Such a type's
    # `@*Mapping` methods describe outbound calls, not server routes.
    private def feign_client?(decl : LibTreeSitter::TSNode, source : String) : Bool
      found = false
      each_annotation(decl, source) do |name, _args, _line|
        found = true if name == "FeignClient"
      end
      found
    end

    # Detect whether a `prefix_expression` node carries annotations
    # — used to recognise the stray-annotation tree-sitter-kotlin
    # quirk where top-level `@A @B class Foo` parses with the
    # annotations as a sibling of `class_declaration`.
    private def prefix_expression_has_annotation?(node : LibTreeSitter::TSNode) : Bool
      Noir::TreeSitter.each_named_child(node) do |child|
        ty = Noir::TreeSitter.node_type(child)
        return true if ty == "annotation"
        return true if ty == "prefix_expression" && prefix_expression_has_annotation?(child)
      end
      false
    end

    # Kotlin's `class_declaration` names its class via a child
    # `type_identifier`. Nested `object_declaration` / `interface_declaration`
    # follow the same shape.
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

    # The class body is a `class_body` named child (not exposed as a
    # `body` field by this grammar version).
    private def class_body(decl : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        return child if Noir::TreeSitter.node_type(child) == "class_body"
      end
      nil
    end

    private def class_mapping_prefix(class_decl : LibTreeSitter::TSNode,
                                     source : String,
                                     stray_annotation_nodes : Array(LibTreeSitter::TSNode) = [] of LibTreeSitter::TSNode,
                                     string_constants = Hash(String, String).new,
                                     local_string_constants = Hash(String, String).new) : String
      each_annotation(class_decl, source) do |name, args|
        next unless ANNOTATION_VERBS.has_key?(name)
        paths = annotation_paths(args, source, string_constants, local_string_constants)
        return paths.first unless paths.empty?
      end

      # Fall back to stray-annotation chunks (top-level
      # `@RequestMapping("/x")` siblings of the class declaration —
      # tree-sitter-kotlin quirk on the first annotated class in a
      # file). The argument node here is a `parenthesized_expression`
      # rather than a `value_arguments`, so we collect string literals
      # directly.
      stray_annotation_nodes.each do |stray|
        collect_stray_annotations(stray, source).each do |entry|
          name, args = entry
          next unless ANNOTATION_VERBS.has_key?(name)
          next unless args
          buf = [] of String
          collect_string_values(args, source, buf, string_constants, local_string_constants)
          return buf.first unless buf.empty?
        end
      end
      ""
    end

    # Walk annotations buried under nested `prefix_expression`
    # chunks and return `{name, args_node_or_nil}` tuples. Returning
    # an array (instead of yielding) sidesteps Crystal's restriction
    # on recursive block expansion in private helpers.
    private def collect_stray_annotations(node : LibTreeSitter::TSNode, source : String) : Array(Tuple(String, LibTreeSitter::TSNode?))
      sink = [] of Tuple(String, LibTreeSitter::TSNode?)
      walk_stray_annotations(node, source, sink)
      sink
    end

    private def walk_stray_annotations(node : LibTreeSitter::TSNode,
                                       source : String,
                                       sink : Array(Tuple(String, LibTreeSitter::TSNode?)))
      Noir::TreeSitter.each_named_child(node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "annotation"
          Noir::TreeSitter.each_named_child(child) do |sub|
            case Noir::TreeSitter.node_type(sub)
            when "user_type"
              name = simple_annotation_name(Noir::TreeSitter.node_text(sub, source))
              # Annotation arguments may live in a sibling
              # `parenthesized_expression` (the
              # `@RequestMapping("/x")` case).
              args = parenthesized_args_following(node, child)
              sink << {name, args}
            when "constructor_invocation"
              inner_name = ""
              ctor_args : LibTreeSitter::TSNode? = nil
              Noir::TreeSitter.each_named_child(sub) do |arg_child|
                case Noir::TreeSitter.node_type(arg_child)
                when "user_type"
                  inner_name = simple_annotation_name(Noir::TreeSitter.node_text(arg_child, source))
                when "value_arguments"
                  ctor_args = arg_child
                end
              end
              sink << {inner_name, ctor_args} unless inner_name.empty?
            end
          end
        when "prefix_expression"
          walk_stray_annotations(child, source, sink)
        end
      end
    end

    # When an annotation parses as `@Foo` followed by a separate
    # `parenthesized_expression` (the stray-annotation quirk), grab
    # the matching `parenthesized_expression` sibling so we can
    # surface it as the annotation's argument node. Returns nil when
    # no such sibling is present (the no-args annotation case).
    private def parenthesized_args_following(parent : LibTreeSitter::TSNode,
                                             ann_node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      seen = false
      result : LibTreeSitter::TSNode? = nil
      Noir::TreeSitter.each_named_child(parent) do |sibling|
        if seen
          result = sibling if Noir::TreeSitter.node_type(sibling) == "parenthesized_expression"
          break
        end
        seen = true if sibling == ann_node
      end
      result
    end

    private def collect_function_routes(func : LibTreeSitter::TSNode,
                                        source : String,
                                        class_name : String,
                                        class_prefix : String,
                                        routes : Array(Route),
                                        string_constants : Hash(String, String),
                                        local_string_constants : Hash(String, String))
      method_name = function_name(func, source)

      each_annotation(func, source) do |ann_name, args, ann_line|
        next unless ANNOTATION_VERBS.has_key?(ann_name)
        verb_default = ANNOTATION_VERBS[ann_name]?

        paths = annotation_paths(args, source, string_constants, local_string_constants)
        paths = [""] if paths.empty?

        verbs =
          if verb_default
            [verb_default]
          else
            methods = annotation_methods(args, source)
            methods.empty? ? ["GET"] : methods
          end

        paths.each do |path|
          full = join_paths(class_prefix, path)
          verbs.each do |verb|
            routes << Route.new(verb, full, class_name, method_name, ann_line)
          end
        end
      end
    end

    private def collect_stomp_handshake_routes(source : String,
                                               routes : Array(Route),
                                               string_constants : Hash(String, String),
                                               local_string_constants : Hash(String, String))
      each_method_call_arguments(source, "addEndpoint") do |args, line|
        top_level_arguments(args).each do |arg|
          resolve_route_expressions(arg, string_constants, local_string_constants).each do |endpoint_path|
            routes << Route.new("GET", endpoint_path, "", "", line - 1)
          end
        end
      end
    end

    private def walk_message_mapping_routes(node : LibTreeSitter::TSNode,
                                            source : String,
                                            string_constants : Hash(String, String),
                                            local_string_constants : Hash(String, String),
                                            application_prefixes : Array(String),
                                            outer_prefixes : Array(String),
                                            routes : Array(Route),
                                            depth = 0,
                                            stray_annotation_nodes = [] of LibTreeSitter::TSNode)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      node_type = Noir::TreeSitter.node_type(node)
      if node_type == "class_declaration" || node_type == "object_declaration" || node_type == "interface_declaration"
        class_name = type_identifier_text(node, source)
        class_paths = message_mapping_paths(node, source, string_constants, local_string_constants, stray_annotation_nodes)
        class_paths = [""] if class_paths.empty?
        prefixes = [] of String
        outer_prefixes.each do |outer_prefix|
          class_paths.each do |class_path|
            prefixes << join_paths(outer_prefix, class_path)
          end
        end

        if body = class_body(node)
          Noir::TreeSitter.each_named_child(body) do |member|
            case Noir::TreeSitter.node_type(member)
            when "function_declaration"
              collect_message_mapping_function_routes(
                member, source, class_name, prefixes, application_prefixes, routes, string_constants, local_string_constants
              )
            when "class_declaration", "object_declaration", "interface_declaration"
              walk_message_mapping_routes(
                member, source, string_constants, local_string_constants, application_prefixes, prefixes, routes, depth + 1
              )
            end
          end
        end
        return
      end

      pending = [] of LibTreeSitter::TSNode
      count = LibTreeSitter.ts_node_named_child_count(node)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(node, i.to_u32)
        case Noir::TreeSitter.node_type(child)
        when "class_declaration", "object_declaration", "interface_declaration"
          walk_message_mapping_routes(
            child, source, string_constants, local_string_constants, application_prefixes, outer_prefixes, routes, depth + 1, pending
          )
          pending = [] of LibTreeSitter::TSNode
        when "prefix_expression"
          if prefix_expression_has_annotation?(child)
            pending << child
          else
            pending = [] of LibTreeSitter::TSNode
            walk_message_mapping_routes(
              child, source, string_constants, local_string_constants, application_prefixes, outer_prefixes, routes, depth + 1
            )
          end
        else
          pending = [] of LibTreeSitter::TSNode
          walk_message_mapping_routes(
            child, source, string_constants, local_string_constants, application_prefixes, outer_prefixes, routes, depth + 1
          )
        end
      end
    end

    private def collect_message_mapping_function_routes(func : LibTreeSitter::TSNode,
                                                        source : String,
                                                        class_name : String,
                                                        class_prefixes : Array(String),
                                                        application_prefixes : Array(String),
                                                        routes : Array(Route),
                                                        string_constants : Hash(String, String),
                                                        local_string_constants : Hash(String, String))
      method_name = function_name(func, source)
      destinations = message_send_destinations(func, source, string_constants, local_string_constants)

      each_annotation(func, source) do |ann_name, args, ann_line|
        verb =
          case ann_name
          when "MessageMapping"   then "SEND"
          when "SubscribeMapping" then "SUBSCRIBE"
          end
        next unless verb

        paths = annotation_paths(args, source, string_constants, local_string_constants)
        paths = [""] if paths.empty?

        application_prefixes.each do |application_prefix|
          class_prefixes.each do |class_prefix|
            paths.each do |path|
              routes << Route.new(
                verb, join_paths(application_prefix, join_paths(class_prefix, path)), class_name, method_name, ann_line,
                messaging_destinations: destinations
              )
            end
          end
        end
      end
    end

    private def message_send_destinations(func : LibTreeSitter::TSNode,
                                          source : String,
                                          string_constants : Hash(String, String),
                                          local_string_constants : Hash(String, String)) : Array(String)
      destinations = [] of String
      each_annotation(func, source) do |name, args|
        next unless name == "SendTo" || name == "SendToUser"
        destinations.concat(annotation_paths(args, source, string_constants, local_string_constants))
      end
      destinations.uniq
    end

    private def message_mapping_paths(class_decl : LibTreeSitter::TSNode,
                                      source : String,
                                      string_constants : Hash(String, String),
                                      local_string_constants : Hash(String, String),
                                      stray_annotation_nodes : Array(LibTreeSitter::TSNode)) : Array(String)
      paths = [] of String
      each_annotation(class_decl, source) do |name, args|
        next unless name == "MessageMapping"
        paths.concat(annotation_paths(args, source, string_constants, local_string_constants))
      end

      stray_annotation_nodes.each do |stray|
        collect_stray_annotations(stray, source).each do |entry|
          name, args = entry
          next unless name == "MessageMapping"
          next unless args
          collect_string_values(args, source, paths, string_constants, local_string_constants)
        end
      end

      paths
    end

    private def walk_graphql_mapping_routes(node : LibTreeSitter::TSNode,
                                            source : String,
                                            string_constants : Hash(String, String),
                                            local_string_constants : Hash(String, String),
                                            routes : Array(GraphqlRoute),
                                            depth = 0)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "class_declaration" || Noir::TreeSitter.node_type(node) == "object_declaration"
        class_name = type_identifier_text(node, source)
        if body = class_body(node)
          Noir::TreeSitter.each_named_child(body) do |member|
            case Noir::TreeSitter.node_type(member)
            when "function_declaration"
              collect_graphql_function_routes(member, source, class_name, string_constants, local_string_constants, routes)
            when "class_declaration", "object_declaration"
              walk_graphql_mapping_routes(member, source, string_constants, local_string_constants, routes, depth + 1)
            end
          end
        end
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_graphql_mapping_routes(child, source, string_constants, local_string_constants, routes, depth + 1)
      end
    end

    private def collect_graphql_function_routes(func : LibTreeSitter::TSNode,
                                                source : String,
                                                class_name : String,
                                                string_constants : Hash(String, String),
                                                local_string_constants : Hash(String, String),
                                                routes : Array(GraphqlRoute))
      method_name = function_name(func, source)
      return if method_name.empty?

      each_annotation(func, source) do |ann_name, args, ann_line|
        operation =
          case ann_name
          when "QueryMapping"
            {"query", "Query"}
          when "MutationMapping"
            {"mutation", "Mutation"}
          when "SubscriptionMapping"
            {"subscription", "Subscription"}
          when "SchemaMapping"
            type_names = schema_mapping_type_names(args, source, string_constants, local_string_constants)
            type_names = [graphql_schema_source_type(func, source)] if type_names.empty?
            type_names = type_names.reject(&.empty?)
            next if type_names.empty?

            field_names = schema_mapping_field_names(args, source, string_constants, local_string_constants)
            field_names = [method_name] if field_names.empty?

            field_names.each do |field_name|
              field = field_name.lstrip('/').strip
              next if field.empty?
              type_names.each do |type_name|
                routes << GraphqlRoute.new(
                  "field", type_name, field, ann_line, class_name, method_name,
                  graphql_arguments(func, source, string_constants, local_string_constants)
                )
              end
            end
            next
          end
        next unless operation

        operation_keyword, root_kind = operation
        names = annotation_paths(args, source, string_constants, local_string_constants)
        names = [method_name] if names.empty?

        names.each do |name|
          field_name = name.lstrip('/').strip
          next if field_name.empty?
          routes << GraphqlRoute.new(
            operation_keyword, root_kind, field_name, ann_line, class_name, method_name,
            graphql_arguments(func, source, string_constants, local_string_constants)
          )
        end
      end
    end

    private def schema_mapping_field_names(args : LibTreeSitter::TSNode?,
                                           source : String,
                                           string_constants : Hash(String, String),
                                           local_string_constants : Hash(String, String)) : Array(String)
      graphql_annotation_string_values(args, source, ["value", "field"], string_constants, local_string_constants)
    end

    private def schema_mapping_type_names(args : LibTreeSitter::TSNode?,
                                          source : String,
                                          string_constants : Hash(String, String),
                                          local_string_constants : Hash(String, String)) : Array(String)
      graphql_annotation_string_values(args, source, ["typeName"], string_constants, local_string_constants)
    end

    private def graphql_annotation_string_values(args_node : LibTreeSitter::TSNode?,
                                                 source : String,
                                                 allowed_keys : Array(String),
                                                 string_constants : Hash(String, String),
                                                 local_string_constants : Hash(String, String)) : Array(String)
      values = [] of String
      return values unless args_node
      return values unless Noir::TreeSitter.node_type(args_node) == "value_arguments"

      positional = [] of String
      keyword = [] of String
      Noir::TreeSitter.each_named_child(args_node) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        kind, key, value_node = classify_value_argument(arg, source)
        next unless value_node

        if kind == :keyword
          next unless allowed_keys.includes?(key)
          collect_string_values(value_node, source, keyword, string_constants, local_string_constants)
        elsif allowed_keys.includes?("value")
          collect_string_values(value_node, source, positional, string_constants, local_string_constants)
        end
      end

      keyword.empty? ? positional : keyword
    end

    private def graphql_schema_source_type(func : LibTreeSitter::TSNode, source : String) : String
      params_node = function_parameters(func)
      return "" unless params_node

      pending_modifiers : LibTreeSitter::TSNode? = nil
      Noir::TreeSitter.each_named_child(params_node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "parameter_modifiers"
          pending_modifiers = child
        when "parameter"
          if pending_modifiers && graphql_argument_modifier?(pending_modifiers, source)
            pending_modifiers = nil
            next
          end

          type_name = kotlin_parameter_type(child, source)
          return type_name unless type_name.empty?
          pending_modifiers = nil
        else
          pending_modifiers = nil
        end
      end

      ""
    end

    private def graphql_arguments(func : LibTreeSitter::TSNode,
                                  source : String,
                                  string_constants : Hash(String, String),
                                  local_string_constants : Hash(String, String)) : Array(NamedTuple(name: String, type: String))
      params_node = function_parameters(func)
      return [] of NamedTuple(name: String, type: String) unless params_node

      args = [] of NamedTuple(name: String, type: String)
      pending_argument : String? = nil
      count = LibTreeSitter.ts_node_named_child_count(params_node)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(params_node, i.to_u32)
        child_type = Noir::TreeSitter.node_type(child)
        case child_type
        when "parameter_modifiers"
          pending_argument = graphql_argument_override(child, source, string_constants, local_string_constants) if graphql_argument_modifier?(child, source)
        when "simple_identifier"
          next unless pending_argument
          param_name = Noir::TreeSitter.node_text(child, source)
          arg_name = pending_argument.empty? ? param_name : pending_argument
          arg_type = graphql_argument_type(params_node, source, (i + 1).to_i32)
          args << {name: arg_name, type: arg_type}
          pending_argument = nil
        when "parameter"
          next unless pending_argument
          param_name = kotlin_parameter_name(child, source)
          next if param_name.empty?
          arg_name = pending_argument.empty? ? param_name : pending_argument
          args << {name: arg_name, type: kotlin_parameter_type(child, source)}
          pending_argument = nil
        else
          pending_argument = nil if pending_argument && child_type != "annotation"
        end
      end

      args
    end

    private def function_parameters(func : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(func) do |child|
        return child if Noir::TreeSitter.node_type(child) == "function_value_parameters"
      end
      nil
    end

    private def kotlin_parameter_name(node : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.each_named_child(node) do |child|
        return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "simple_identifier"
      end
      ""
    end

    private def kotlin_parameter_type(node : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.each_named_child(node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "user_type", "nullable_type"
          return Noir::TreeSitter.node_text(child, source).rstrip('?')
        end
      end
      "String"
    end

    private def graphql_argument_modifier?(node : LibTreeSitter::TSNode, source : String) : Bool
      Noir::TreeSitter.node_text(node, source).includes?("@Argument")
    end

    private def graphql_argument_override(node : LibTreeSitter::TSNode,
                                          source : String,
                                          string_constants : Hash(String, String),
                                          local_string_constants : Hash(String, String)) : String
      text = Noir::TreeSitter.node_text(node, source)
      if match = text.match(/@Argument\s*\(\s*"([^"]+)"/)
        return match[1]
      end
      if match = text.match(/@Argument\s*\([^)]*\b(?:name|value)\s*=\s*"([^"]+)"/)
        return match[1]
      end

      annotation_argument_values(node, source).each do |key, value_node|
        next unless key.empty? || key == "name" || key == "value"
        if value = resolve_string_value(value_node, source, string_constants, local_string_constants)
          return value unless value.empty?
        end
      end

      ""
    end

    private def annotation_argument_values(node : LibTreeSitter::TSNode,
                                           source : String) : Array(Tuple(String, LibTreeSitter::TSNode))
      values = [] of Tuple(String, LibTreeSitter::TSNode)
      Noir::TreeSitter.each_named_child(node) do |child|
        if Noir::TreeSitter.node_type(child) == "value_arguments"
          Noir::TreeSitter.each_named_child(child) do |arg|
            next unless Noir::TreeSitter.node_type(arg) == "value_argument"
            _, key, value_node = classify_value_argument(arg, source)
            values << {key, value_node} if value_node
          end
        else
          values.concat(annotation_argument_values(child, source))
        end
      end
      values
    end

    private def graphql_argument_type(params_node : LibTreeSitter::TSNode,
                                      source : String,
                                      start_index : Int32) : String
      count = LibTreeSitter.ts_node_named_child_count(params_node)
      index = start_index
      while index < count
        child = LibTreeSitter.ts_node_named_child(params_node, index.to_u32)
        case Noir::TreeSitter.node_type(child)
        when "user_type", "nullable_type"
          return Noir::TreeSitter.node_text(child, source).rstrip('?')
        when "parameter_modifiers", "simple_identifier"
          return "String"
        end
        index += 1
      end
      "String"
    end

    private struct GatewayRoute
      getter verb : String
      getter path : String

      def initialize(@verb, @path)
      end
    end

    private def collect_gateway_routes(source : String,
                                       string_constants : Hash(String, String),
                                       routes : Array(Route))
      visible_source = visible_kotlin_code(source)
      helpers = gateway_predicate_helpers(source, visible_source, string_constants)
      return if helpers.empty?

      visible_source.each_line.with_index do |line, idx|
        next if line.includes?("fun PredicateSpec.")

        helpers.each do |name, route|
          next unless line.includes?(".#{name}(")
          routes << Route.new(route.verb, route.path, "", "", idx)
        end
      end
    end

    private def gateway_predicate_helpers(source : String,
                                          visible_source : String,
                                          string_constants : Hash(String, String)) : Hash(String, GatewayRoute)
      helpers = Hash(String, GatewayRoute).new
      lines = source.lines
      visible_lines = visible_source.lines
      i = 0

      while i < lines.size
        line = visible_lines[i]
        match = line.match(/\bfun\s+PredicateSpec\.([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*(?::\s*[^=]+)?=/)
        unless match
          i += 1
          next
        end

        name = match[1]
        expr = lines[i][(match.end(0) || line.size)..]? || ""
        j = i
        broke_on_decl = false
        unless expr.includes?(".path(")
          j = i + 1
          while j < lines.size
            visible_next_line = visible_lines[j]
            if visible_next_line.match(/^\s*(?:[A-Za-z_][A-Za-z0-9_<>.]*\s+)*fun\b/) ||
               visible_next_line.match(/^\s*(?:class|object|interface|companion\s+object)\b/)
              broke_on_decl = true
              break
            end
            break if visible_next_line.strip == "}"
            expr += "\n#{lines[j]}"
            break if visible_next_line.includes?(".path(")
            j += 1
          end
        end

        if route = gateway_route_from_expression(expr, string_constants)
          helpers[name] = route
        end

        # If the scan stopped ON a new declaration line, re-examine it rather than
        # skipping it — otherwise a back-to-back PredicateSpec helper is missed.
        i = broke_on_decl ? j : j + 1
      end

      helpers
    end

    private struct FunctionalNest
      getter depth : Int32
      getter path : String

      def initialize(@depth, @path)
      end
    end

    # Spring WebFlux Kotlin DSL:
    #
    #   coRouter {
    #     "/posts".nest {
    #       GET("/{id}", postHandler::get)
    #     }
    #   }
    #
    # This is source-only by design: no file I/O and no Ktor-style
    # lowercase verbs. Handler method references are threaded through
    # the Route so the analyzer can reuse the existing Kotlin callee
    # walker when the handler type is visible in the router function
    # signature.
    private def collect_webflux_functional_routes(source : String, routes : Array(Route))
      handler_types = functional_handler_types(source)
      visible_lines = visible_kotlin_code(source).lines
      lines = source.lines

      router_depth : Int32? = nil
      depth = 0
      nests = [] of FunctionalNest

      lines.each_with_index do |line, idx|
        visible = visible_lines[idx]? || line
        opens = visible.count("{")
        closes = visible.count("}")

        if router_depth.nil? && visible.match(/\b(?:coRouter|router)\s*\{/)
          router_depth = depth + opens - closes
          router_depth = depth + 1 if router_depth <= depth
        end

        if rd = router_depth
          if visible.match(/\.nest\s*\{/) && (match = line.match(/"([^"]*)"\s*\.\s*nest\s*\{/))
            nests << FunctionalNest.new(depth + 1, match[1])
          end

          if visible.match(/\b(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s*\(/) &&
             (match = line.match(/\b(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s*\(\s*"([^"]*)"/))
            verb = match[1]
            path = join_functional_paths(nests.map(&.path), match[2])
            class_name = ""
            method_name = ""
            handler_reference : String? = nil

            if handler_match = line.match(/([A-Za-z_][A-Za-z0-9_]*)\s*::\s*([A-Za-z_][A-Za-z0-9_]*)/)
              receiver = handler_match[1]
              method_name = handler_match[2]
              class_name = handler_types[receiver]? || ""
              handler_reference = "#{receiver}::#{method_name}"
            end

            inline_callees = handler_reference ? [] of NamedTuple(name: String, line: Int32) : inline_functional_route_callees(line, idx + 1)
            routes << Route.new(verb, path, class_name, method_name, idx, handler_reference, inline_callees)
          end

          depth += opens - closes
          nests.reject! { |nest| nest.depth > depth }
          router_depth = nil if depth < rd
        else
          depth += opens - closes
        end
      end
    end

    private def inline_functional_route_callees(line : String, line_number : Int32) : Array(NamedTuple(name: String, line: Int32))
      open_idx = line.index('{')
      close_idx = line.rindex('}')
      return [] of NamedTuple(name: String, line: Int32) unless open_idx && close_idx && close_idx > open_idx

      body = line[(open_idx + 1)...close_idx]
      callees = [] of NamedTuple(name: String, line: Int32)
      body.scan(/(?:(\b[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?(\b[A-Za-z_][A-Za-z0-9_]*)\s*\(/) do |match|
        receiver = match[1]?
        leaf = match[2]
        name = receiver ? "#{receiver}.#{leaf}" : leaf
        callees << {name: name, line: line_number}
      end
      callees
    end

    private def functional_handler_types(source : String) : Hash(String, String)
      types = Hash(String, String).new
      source.scan(/\bfun\s+[A-Za-z_][A-Za-z0-9_]*\s*\(([^)]*)\)/) do |match|
        collect_functional_parameter_types(match[1], types)
      end
      source.scan(/\bclass\s+[A-Za-z_][A-Za-z0-9_]*\s*\(([^)]*)\)/) do |match|
        collect_functional_parameter_types(match[1], types)
      end
      types
    end

    private def collect_functional_parameter_types(parameter_list : String, types : Hash(String, String))
      parameter_list.scan(/(?:\b(?:private|protected|public|internal)\s+)*(?:val|var)?\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z_][A-Za-z0-9_.]*)/) do |param|
        types[param[1]] ||= param[2].split('.').last
      end
    end

    private def join_functional_paths(prefixes : Array(String), path : String) : String
      prefix = prefixes.reduce("") { |memo, item| join_paths(memo, item) }
      join_paths(prefix, path)
    end

    private def visible_kotlin_code(source : String) : String
      slash = '/'.ord.to_u8
      star = '*'.ord.to_u8
      double_quote = '"'.ord.to_u8
      single_quote = '\''.ord.to_u8
      backslash = '\\'.ord.to_u8
      newline = '\n'.ord.to_u8
      space = ' '.ord.to_u8

      bytes = source.to_slice
      mode = :code
      quote = 0_u8
      raw_string = false
      escaped = false
      i = 0

      String.build(source.bytesize) do |io|
        while i < bytes.size
          byte = bytes[i]

          case mode
          when :line_comment
            if byte == newline
              io.write_byte(byte)
              mode = :code
            else
              io.write_byte(space)
            end
            i += 1
          when :block_comment
            if byte == newline
              io.write_byte(byte)
              i += 1
            elsif i + 1 < bytes.size && byte == star && bytes[i + 1] == slash
              io.write_byte(space)
              io.write_byte(space)
              i += 2
              mode = :code
            else
              io.write_byte(space)
              i += 1
            end
          when :string
            if raw_string && i + 2 < bytes.size && byte == double_quote && bytes[i + 1] == double_quote && bytes[i + 2] == double_quote
              io.write_byte(space)
              io.write_byte(space)
              io.write_byte(space)
              i += 3
              mode = :code
              raw_string = false
            elsif !raw_string && byte == quote && !escaped
              io.write_byte(space)
              i += 1
              mode = :code
            else
              io.write_byte(byte == newline ? byte : space)
              if raw_string
                i += 1
              elsif escaped
                escaped = false
                i += 1
              else
                escaped = byte == backslash
                i += 1
              end
            end
          else
            if i + 1 < bytes.size && byte == slash && bytes[i + 1] == slash
              io.write_byte(space)
              io.write_byte(space)
              i += 2
              mode = :line_comment
            elsif i + 1 < bytes.size && byte == slash && bytes[i + 1] == star
              io.write_byte(space)
              io.write_byte(space)
              i += 2
              mode = :block_comment
            elsif i + 2 < bytes.size && byte == double_quote && bytes[i + 1] == double_quote && bytes[i + 2] == double_quote
              io.write_byte(space)
              io.write_byte(space)
              io.write_byte(space)
              i += 3
              mode = :string
              raw_string = true
            elsif byte == double_quote || byte == single_quote
              io.write_byte(space)
              quote = byte
              raw_string = false
              escaped = false
              i += 1
              mode = :string
            else
              io.write_byte(byte)
              i += 1
            end
          end
        end
      end
    end

    private def gateway_route_from_expression(expr : String, string_constants : Hash(String, String)) : GatewayRoute?
      verb_match = expr.match(/method\s*\(\s*(?:HttpMethod|RequestMethod)\.([A-Z]+)\s*\)/)
      return unless verb_match

      path_match = expr.match(/\.path\s*\(\s*([^)]+?)\s*\)/)
      return unless path_match

      path = resolve_gateway_path(path_match[1], string_constants)
      return if path.empty?

      GatewayRoute.new(verb_match[1], path)
    end

    private def resolve_gateway_path(raw : String, string_constants : Hash(String, String)) : String
      value = raw.strip
      if match = value.match(/^"([^"]*)"$/)
        return match[1]
      end

      if resolved = string_constants[value]?
        return resolved
      end

      if idx = value.rindex('.')
        short_name = value[(idx + 1)..]
        if resolved = string_constants[short_name]?
          return resolved
        end
      end

      ""
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

    # Walk every annotation on a class/function declaration. Kotlin
    # wraps annotations in a `modifiers` child, and each `annotation`
    # node has either a `user_type` (for `@Foo`) or a
    # `constructor_invocation` (for `@Foo("x")`/`@Foo(a = b)`).
    # Yields `(simple_name, args_node_or_nil, line)`.
    private def each_annotation(decl : LibTreeSitter::TSNode, source : String, &)
      mods = find_modifiers(decl)
      return unless mods
      Noir::TreeSitter.each_named_child(mods) do |ann|
        next unless Noir::TreeSitter.node_type(ann) == "annotation"
        Noir::TreeSitter.each_named_child(ann) do |child|
          case Noir::TreeSitter.node_type(child)
          when "user_type"
            name = simple_annotation_name(Noir::TreeSitter.node_text(child, source))
            yield name, nil, Noir::TreeSitter.node_start_row(ann)
          when "constructor_invocation"
            # `user_type` + `value_arguments` pair.
            inner_name = ""
            args : LibTreeSitter::TSNode? = nil
            Noir::TreeSitter.each_named_child(child) do |sub|
              case Noir::TreeSitter.node_type(sub)
              when "user_type"
                inner_name = simple_annotation_name(Noir::TreeSitter.node_text(sub, source))
              when "value_arguments"
                args = sub
              end
            end
            yield inner_name, args, Noir::TreeSitter.node_start_row(ann) unless inner_name.empty?
          end
        end
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

    private def simple_annotation_name(full : String) : String
      if idx = full.rindex('.')
        full[(idx + 1)..]
      else
        full
      end
    end

    # Kotlin `value_arguments` contains `value_argument` children.
    # Each argument is either positional (a single child that's a
    # literal) or named (has a `simple_identifier` + expression).
    private def annotation_paths(args_node : LibTreeSitter::TSNode?,
                                 source : String,
                                 string_constants : Hash(String, String),
                                 local_string_constants : Hash(String, String)) : Array(String)
      empty = [] of String
      return empty unless args_node
      return empty unless Noir::TreeSitter.node_type(args_node) == "value_arguments"

      positional = [] of String
      keyword = [] of String

      Noir::TreeSitter.each_named_child(args_node) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        kind, key, value_node = classify_value_argument(arg, source)
        next unless value_node

        if kind == :keyword
          next unless key == "value" || key == "path"
          collect_string_values(value_node, source, keyword, string_constants, local_string_constants)
        elsif kind == :bare_identifier
          if value = local_string_constants[key]?
            positional << value unless value.empty?
          end
        else
          collect_string_values(value_node, source, positional, string_constants, local_string_constants)
        end
      end

      keyword.empty? ? positional : keyword
    end

    # Return `{:keyword | :positional | :bare_identifier, key_or_nil, value_node}`.
    private def classify_value_argument(arg : LibTreeSitter::TSNode, source : String) : Tuple(Symbol, String, LibTreeSitter::TSNode?)
      children = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(arg) do |child|
        children << child
      end
      if children.size <= 1
        child = children.first?
        if child && Noir::TreeSitter.node_type(child) == "simple_identifier"
          return {:bare_identifier, Noir::TreeSitter.node_text(child, source), child}
        end
        return {:positional, "", child}
      end

      key = ""
      value : LibTreeSitter::TSNode? = nil
      named = false
      children.each do |entry|
        case Noir::TreeSitter.node_type(entry)
        when "simple_identifier"
          if named
            # second identifier is actually the value expression
            value = entry
          else
            key = Noir::TreeSitter.node_text(entry, source)
            named = true
          end
        else
          value = entry if value.nil?
        end
      end
      {named ? :keyword : :positional, key, value}
    end

    # Collect path values from a node. Handles string literals,
    # constants, `PATH + "/suffix"`, collection literals, and
    # `arrayOf("/a", PATH)` call expressions.
    private def collect_string_values(node : LibTreeSitter::TSNode,
                                      source : String,
                                      sink : Array(String),
                                      string_constants : Hash(String, String),
                                      local_string_constants : Hash(String, String))
      case Noir::TreeSitter.node_type(node)
      when "collection_literal"
        # Kotlin's `[...]` array syntax inside annotations.
        Noir::TreeSitter.each_named_child(node) do |elem|
          collect_string_values(elem, source, sink, string_constants, local_string_constants)
        end
      when "parenthesized_expression"
        # Stray-annotation case: `@RequestMapping("/x")` gets parsed
        # as `annotation` + sibling `parenthesized_expression`
        # carrying a bare `string_literal` (no `value_arguments`
        # wrapper).
        Noir::TreeSitter.each_named_child(node) do |elem|
          collect_string_values(elem, source, sink, string_constants, local_string_constants)
        end
      when "call_expression"
        # `arrayOf("/a", "/b")` — walk the value_arguments.
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
      else
        if value = resolve_string_value(node, source, string_constants, local_string_constants)
          sink << value unless value.empty?
        end
      end
    end

    private def resolve_string_value(node : LibTreeSitter::TSNode,
                                     source : String,
                                     string_constants : Hash(String, String),
                                     local_string_constants : Hash(String, String)) : String?
      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        decode_string_literal(node, source, string_constants, local_string_constants)
      when "simple_identifier"
        # A bare const reference. Spring controllers idiomatically keep
        # their path constants in a shared `Paths.kt` and reference them
        # unqualified (`@RequestMapping(path = [PUBLIC_URL])`), so fall
        # back to the cross-file constant map when the name isn't local.
        name = Noir::TreeSitter.node_text(node, source)
        local_string_constants[name]? || string_constants[name]?
      when "navigation_expression"
        text = Noir::TreeSitter.node_text(node, source)
        local_string_constants[text]? || fully_qualified_constant(text, string_constants)
      when "parenthesized_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          return resolve_string_value(child, source, string_constants, local_string_constants)
        end
      when "additive_expression"
        parts = [] of String
        Noir::TreeSitter.each_named_child(node) do |child|
          part = resolve_string_value(child, source, string_constants, local_string_constants)
          return unless part
          parts << part
        end
        parts.join
      end
    end

    private def fully_qualified_constant(text : String, string_constants : Hash(String, String)) : String?
      return unless text.count('.') >= 2
      string_constants[text]?
    end

    private def last_navigation_segment(node : LibTreeSitter::TSNode, source : String) : String
      result = ""
      Noir::TreeSitter.each_named_child(node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "simple_identifier"
          result = Noir::TreeSitter.node_text(child, source)
        when "navigation_suffix"
          Noir::TreeSitter.each_named_child(child) do |sub|
            if Noir::TreeSitter.node_type(sub) == "simple_identifier"
              result = Noir::TreeSitter.node_text(sub, source)
            end
          end
        end
      end
      result
    end

    # Extract verbs from `method = RequestMethod.X` / `method =
    # [RequestMethod.X, RequestMethod.Y]` / `method = arrayOf(...)`.
    private def annotation_methods(args_node : LibTreeSitter::TSNode?, source : String) : Array(String)
      empty = [] of String
      return empty unless args_node
      return empty unless Noir::TreeSitter.node_type(args_node) == "value_arguments"

      methods = [] of String
      Noir::TreeSitter.each_named_child(args_node) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        kind, key, value_node = classify_value_argument(arg, source)
        next unless kind == :keyword
        next unless key == "method"
        next unless value_node
        collect_request_method_values(value_node, source, methods)
      end
      methods
    end

    private def each_method_call_arguments(source : String, method_name : String, &)
      offset = 0
      name_size = method_name.size

      while marker = source.index(method_name, offset)
        offset = marker + name_size
        next unless method_call_name?(source, marker, name_size)

        open_idx = source.index('(', marker)
        next unless open_idx
        close_idx = find_matching_paren(source, open_idx)
        next unless close_idx

        args = source[(open_idx + 1)...close_idx]
        line = source[0...marker].count('\n') + 1
        yield args, line
      end
    end

    private def method_call_name?(source : String, marker : Int32, name_size : Int32) : Bool
      before = marker.zero? ? '\0' : source[marker - 1]
      return false if before.ascii_alphanumeric? || before == '_'

      after_idx = marker + name_size
      while after_idx < source.size && source[after_idx].ascii_whitespace?
        after_idx += 1
      end
      after_idx < source.size && source[after_idx] == '('
    end

    private def top_level_arguments(args : String) : Array(String)
      result = [] of String
      start = 0
      depth = 0
      in_string = false
      escaped = false

      args.each_char.with_index do |char, index|
        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"'
          in_string = true
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when ','
          if depth.zero?
            result << args[start...index].strip
            start = index + 1
          end
        end
      end

      tail = args[start..]?.try(&.strip)
      result << tail if tail && !tail.empty?
      result
    end

    private def resolve_route_expression(expression : String,
                                         string_constants : Hash(String, String),
                                         local_string_constants : Hash(String, String),
                                         depth = 0) : String?
      return if depth > 8
      value = expression.strip
      return if value.empty?

      if value.starts_with?('"') && value.ends_with?('"')
        return value[1...-1]
      end

      if value.starts_with?("arrayOf(") && value.ends_with?(")")
        inner = value["arrayOf(".size...-1]
        values = top_level_arguments(inner).compact_map do |entry|
          resolve_route_expression(entry, string_constants, local_string_constants, depth + 1)
        end
        return values.first?
      end

      if value.includes?('+')
        parts = top_level_plus_parts(value)
        if parts.size > 1
          resolved_parts = parts.compact_map do |part|
            resolve_route_expression(part, string_constants, local_string_constants, depth + 1)
          end
          return resolved_parts.join if resolved_parts.size == parts.size
        end
      end

      if resolved = local_string_constants[value]?
        return resolved
      end
      if resolved = string_constants[value]?
        return resolved
      end

      if idx = value.rindex('.')
        short_name = value[(idx + 1)..]
        if resolved = local_string_constants[short_name]?
          return resolved
        end
        if resolved = string_constants[short_name]?
          return resolved
        end
      end

      nil
    end

    # Resolve an argument to every string value it denotes. `arrayOf(a, b)`
    # yields all elements; any other expression yields its single resolved
    # value. Used for vararg/array sinks (STOMP `addEndpoint(...)` /
    # `setApplicationDestinationPrefixes(...)`) where keeping only the first
    # entry would drop real endpoints/prefixes.
    private def resolve_route_expressions(expression : String,
                                          string_constants : Hash(String, String),
                                          local_string_constants : Hash(String, String)) : Array(String)
      value = expression.strip
      if value.starts_with?("arrayOf(") && value.ends_with?(")")
        inner = value["arrayOf(".size...-1]
        return top_level_arguments(inner).compact_map do |entry|
          resolve_route_expression(entry, string_constants, local_string_constants)
        end
      end

      if resolved = resolve_route_expression(value, string_constants, local_string_constants)
        [resolved]
      else
        [] of String
      end
    end

    private def top_level_plus_parts(value : String) : Array(String)
      parts = [] of String
      start = 0
      depth = 0
      in_string = false
      escaped = false

      value.each_char.with_index do |char, index|
        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"'
          in_string = true
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when '+'
          if depth.zero?
            parts << value[start...index].strip
            start = index + 1
          end
        end
      end

      tail = value[start..]?.try(&.strip)
      parts << tail if tail && !tail.empty?
      parts
    end

    private def find_matching_paren(source : String, open_idx : Int32) : Int32?
      depth = 0
      in_string = false
      escaped = false
      quote = '\0'

      source.each_char.with_index do |char, index|
        next if index < open_idx

        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
          next
        end

        case char
        when '"', '\''
          in_string = true
          quote = char
        when '('
          depth += 1
        when ')'
          depth -= 1
          return index if depth.zero?
        end
      end

      nil
    end

    # `RequestMethod.GET` is parsed as `navigation_expression` with a
    # `navigation_suffix` carrying the verb. Array forms recurse.
    private def collect_request_method_values(node : LibTreeSitter::TSNode, source : String, sink : Array(String))
      case Noir::TreeSitter.node_type(node)
      when "navigation_expression"
        # Walk to the final `navigation_suffix` child for the verb name.
        Noir::TreeSitter.each_named_child(node) do |child|
          next unless Noir::TreeSitter.node_type(child) == "navigation_suffix"
          Noir::TreeSitter.each_named_child(child) do |id|
            sink << Noir::TreeSitter.node_text(id, source).upcase if Noir::TreeSitter.node_type(id) == "simple_identifier"
          end
        end
      when "simple_identifier"
        sink << Noir::TreeSitter.node_text(node, source).upcase
      when "collection_literal"
        Noir::TreeSitter.each_named_child(node) do |elem|
          collect_request_method_values(elem, source, sink)
        end
      when "call_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          next unless Noir::TreeSitter.node_type(child) == "call_suffix"
          Noir::TreeSitter.each_named_child(child) do |suf|
            next unless Noir::TreeSitter.node_type(suf) == "value_arguments"
            Noir::TreeSitter.each_named_child(suf) do |va|
              next unless Noir::TreeSitter.node_type(va) == "value_argument"
              Noir::TreeSitter.each_named_child(va) do |v|
                collect_request_method_values(v, source, sink)
              end
            end
          end
        end
      end
    end

    # Kotlin `string_literal` wraps content in `string_content`
    # children, same shape as Java. A `$VAR` / `${VAR}` interpolation
    # that names a known compile-time constant (e.g.
    # `@GetMapping("$PUBLIC_URL/version")`) resolves to the constant's
    # value; anything else (a real runtime template) is preserved as a
    # `{VAR}` placeholder. Literal `{id}` path params live in
    # `string_content`, so they're never affected by this resolution.
    private def decode_string_literal(node : LibTreeSitter::TSNode,
                                      source : String,
                                      constants : Hash(String, String)? = nil,
                                      local_constants : Hash(String, String)? = nil) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          case Noir::TreeSitter.node_type(child)
          when "string_content"
            io << Noir::TreeSitter.node_text(child, source)
          when "interpolated_identifier", "interpolated_expression"
            ident = Noir::TreeSitter.node_text(child, source).strip
            resolved = (local_constants.try &.[ident]?) || (constants.try &.[ident]?)
            if resolved
              io << resolved
            else
              io << '{' << ident << '}'
            end
          end
        end
      end
      buf
    end

    # Empty-path semantics mirror the Java extractor: a bare method
    # mapping collapses onto the class prefix, so `@RequestMapping("/api")`
    # + `@GetMapping` (no path) maps to `/api`, not `/api/` (see the
    # empty-path branch below).
    private def join_paths(prefix : String, path : String) : String
      return path if prefix.empty?
      # A bare method mapping (`@GetMapping` with no path arg) on a class
      # mapped to `/api/article` resolves to `/api/article` in Spring —
      # the empty segment is absorbed, not turned into `/api/article/`.
      # An explicit `@GetMapping("/")` still carries its own `/` segment
      # and falls through to the last branch. Only an all-slash class
      # prefix (`@RequestMapping("/")`) keeps the root `/`.
      if path.empty?
        trimmed = prefix.rstrip('/')
        return trimmed.empty? ? "/" : trimmed
      end
      "#{prefix.rstrip('/')}/#{path.lstrip('/')}"
    end
  end
end
