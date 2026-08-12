require "../../utils/url_path"
require "../../ext/tree_sitter/tree_sitter"

module Noir
  # Tree-sitter-backed Kotlin route extractor.
  #
  # Spring-style annotation routing — class-level `@RequestMapping`-family
  # annotations composing with method-level mapping annotations. Mirrors
  # `TreeSitterJavaRouteExtractor` but for Kotlin's distinct AST shape
  # (annotations live in `modifiers`, functions use
  # `function_declaration`, primary constructors carry DTO fields, etc.).
  #
  # This file holds the class-tree walking, mapping prefixes and
  # controller/interface/Feign routes; the sibling files in this
  # directory reopen the module with one concern each (STOMP, GraphQL,
  # gateway, WebFlux functional DSL, shared decoding helpers).
  #
  # Ktor's DSL `routing { get("/x") { ... } }` is a different authoring
  # style and lives in a separate walker
  # (kotlin_ktor_route_extractor_ts.cr).
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
      {class_name, Noir::URLPath.join_absorbing(outer_prefix, class_prefix)}
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
        node, source, match[1], Noir::URLPath.join_absorbing(outer_prefix, class_prefix), routes, string_constants, local_string_constants
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
      prefix = Noir::URLPath.join_absorbing(outer_prefix, class_prefix)

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
          full = Noir::URLPath.join_absorbing(class_prefix, path)
          verbs.each do |verb|
            routes << Route.new(verb, full, class_name, method_name, ann_line)
          end
        end
      end
    end

    private struct FunctionalNest
      getter depth : Int32
      getter path : String

      def initialize(@depth, @path)
      end
    end
  end
end
