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

      def initialize(@verb, @path, @class_name, @method_name, @line)
      end
    end

    def extract_routes(source : String) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_kotlin(source) do |root|
        walk_classes(root, source, "", routes)
      end
      routes
    end

    # ---- private helpers ----------------------------------------------

    private def walk_classes(node : LibTreeSitter::TSNode,
                             source : String,
                             outer_prefix : String,
                             routes : Array(Route))
      ty = Noir::TreeSitter.node_type(node)
      if ty == "class_declaration" || ty == "object_declaration" || ty == "interface_declaration"
        process_class(node, source, outer_prefix, [] of LibTreeSitter::TSNode, routes)
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
      count = LibTreeSitter.ts_node_named_child_count(node)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(node, i.to_u32)
        case Noir::TreeSitter.node_type(child)
        when "class_declaration", "object_declaration", "interface_declaration"
          process_class(child, source, outer_prefix, pending, routes)
          pending = [] of LibTreeSitter::TSNode
        when "prefix_expression"
          pending << child if prefix_expression_has_annotation?(child)
        else
          pending = [] of LibTreeSitter::TSNode
          walk_classes(child, source, outer_prefix, routes)
        end
      end
    end

    private def process_class(node : LibTreeSitter::TSNode,
                              source : String,
                              outer_prefix : String,
                              pending : Array(LibTreeSitter::TSNode),
                              routes : Array(Route))
      class_name = type_identifier_text(node, source)
      class_prefix = class_mapping_prefix(node, source, pending)
      prefix = join_paths(outer_prefix, class_prefix)

      if body = class_body(node)
        Noir::TreeSitter.each_named_child(body) do |member|
          case Noir::TreeSitter.node_type(member)
          when "function_declaration"
            collect_function_routes(member, source, class_name, prefix, routes)
          when "class_declaration", "object_declaration", "interface_declaration"
            walk_classes(member, source, prefix, routes)
          end
        end
      end
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
                                     stray_annotation_nodes : Array(LibTreeSitter::TSNode) = [] of LibTreeSitter::TSNode) : String
      each_annotation(class_decl, source) do |name, args|
        next unless ANNOTATION_VERBS.has_key?(name)
        paths = annotation_paths(args, source)
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
          collect_string_values(args, source, buf)
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
                                        routes : Array(Route))
      method_name = function_name(func, source)

      each_annotation(func, source) do |ann_name, args, ann_line|
        next unless ANNOTATION_VERBS.has_key?(ann_name)
        verb_default = ANNOTATION_VERBS[ann_name]?

        paths = annotation_paths(args, source)
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
    private def annotation_paths(args_node : LibTreeSitter::TSNode?, source : String) : Array(String)
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
          collect_string_values(value_node, source, keyword)
        else
          collect_string_values(value_node, source, positional)
        end
      end

      keyword.empty? ? positional : keyword
    end

    # Return `{:keyword | :positional, key_or_nil, value_node}`.
    private def classify_value_argument(arg : LibTreeSitter::TSNode, source : String) : Tuple(Symbol, String, LibTreeSitter::TSNode?)
      key = ""
      value : LibTreeSitter::TSNode? = nil
      named = false
      Noir::TreeSitter.each_named_child(arg) do |child|
        case Noir::TreeSitter.node_type(child)
        when "simple_identifier"
          if named
            # second identifier is actually the value expression
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

    # Collect string literal values from a node. Handles a single
    # `string_literal`, a `collection_literal` with string children,
    # or `arrayOf("/a", "/b")` call expressions.
    private def collect_string_values(node : LibTreeSitter::TSNode, source : String, sink : Array(String))
      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        text = decode_string_literal(node, source)
        sink << text unless text.empty?
      when "collection_literal"
        # Kotlin's `[...]` array syntax inside annotations.
        Noir::TreeSitter.each_named_child(node) do |elem|
          collect_string_values(elem, source, sink)
        end
      when "parenthesized_expression"
        # Stray-annotation case: `@RequestMapping("/x")` gets parsed
        # as `annotation` + sibling `parenthesized_expression`
        # carrying a bare `string_literal` (no `value_arguments`
        # wrapper).
        Noir::TreeSitter.each_named_child(node) do |elem|
          collect_string_values(elem, source, sink)
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
                  collect_string_values(v, source, sink) if Noir::TreeSitter.node_type(v) == "string_literal"
                end
              end
            end
          end
        end
      end
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
    # children, same shape as Java.
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

    # Trailing-slash semantics match Spring's runtime and mirror the
    # Java extractor: `prefix + "" = prefix/` so `@GetMapping("")` on
    # a class-prefixed route emits `/prefix/`.
    private def join_paths(prefix : String, path : String) : String
      return path if prefix.empty?
      return "#{prefix.rstrip('/')}/" if path.empty?
      "#{prefix.rstrip('/')}/#{path.lstrip('/')}"
    end
  end
end
