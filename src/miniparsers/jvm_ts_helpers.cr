require "../ext/tree_sitter/tree_sitter"

module Noir
  # Private tree-sitter helpers that several JVM extractors used to carry
  # byte-identical copies of. Each group is mixed in (`extend` on the
  # `extend self` extractor modules, `include` on analyzer classes) only by
  # the extractors that had that exact copy.
  #
  # A mixer must not define a same-named, same-arity method of its own:
  # these helpers call each other through `self`, so a local definition
  # would silently replace the shared one for every caller.
  module JvmTsHelpers
    # Java call/argument plumbing: Helidon SE and the lambda-DSL extractor
    # (Javalin, Spark, Vert.x Web, ...).
    module JavaCalls
      private def argument_list_node(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
        Noir::TreeSitter.each_named_child(call) do |child|
          return child if Noir::TreeSitter.node_type(child) == "argument_list"
        end
        nil
      end

      # `app.get("/x", ...)` and `Spark.get("/x", ...)` both produce
      # a `method_invocation` whose last `identifier` child before the
      # `argument_list` is the method name. Static unqualified calls
      # (`get("/x", ...)` after a static import) only have a single
      # `identifier` child preceding the `argument_list`.
      private def method_invocation_method_name(call : LibTreeSitter::TSNode, source : String) : String
        if name_node = Noir::TreeSitter.field(call, "name")
          return Noir::TreeSitter.node_text(name_node, source)
        end

        result = ""
        Noir::TreeSitter.each_named_child(call) do |child|
          ty = Noir::TreeSitter.node_type(child)
          case ty
          when "identifier"
            result = Noir::TreeSitter.node_text(child, source)
          when "argument_list"
            break
          end
        end
        result
      end

      private def lambda_or_reference_argument?(call : LibTreeSitter::TSNode) : Bool
        args = argument_list_node(call)
        return false unless args
        Noir::TreeSitter.each_named_arg(args) do |arg|
          return true if {"lambda_expression", "method_reference"}.includes?(Noir::TreeSitter.node_type(arg))
        end
        false
      end

      private def first_string_argument(call : LibTreeSitter::TSNode,
                                        source : String,
                                        constants : Hash(String, String)) : String?
        args = argument_list_node(call)
        return unless args
        Noir::TreeSitter.each_named_arg(args) do |arg|
          case Noir::TreeSitter.node_type(arg)
          when "string_literal", "identifier", "field_access", "scoped_identifier", "binary_expression", "parenthesized_expression"
            if value = resolve_string_value(arg, source, constants)
              return value
            end
          end
        end
        nil
      end

      private def resolve_string_value(node : LibTreeSitter::TSNode,
                                       source : String,
                                       constants : Hash(String, String),
                                       depth = 0) : String?
        return if depth > 16

        case Noir::TreeSitter.node_type(node)
        when "string_literal"
          Noir::TreeSitter.decode_string_literal(node, source)
        when "identifier", "field_access", "scoped_identifier"
          resolve_constant_reference(Noir::TreeSitter.node_text(node, source), constants)
        when "binary_expression"
          return unless Noir::TreeSitter.node_text(node, source).includes?("+")
          left = Noir::TreeSitter.field(node, "left")
          right = Noir::TreeSitter.field(node, "right")
          return unless left && right
          left_value = resolve_string_value(left, source, constants, depth + 1)
          right_value = resolve_string_value(right, source, constants, depth + 1)
          return unless left_value && right_value
          "#{left_value}#{right_value}"
        when "parenthesized_expression"
          Noir::TreeSitter.each_named_child(node) do |child|
            if value = resolve_string_value(child, source, constants, depth + 1)
              return value
            end
          end
        end
      end

      private def resolve_constant_reference(name : String, constants : Hash(String, String)) : String?
        if resolved = constants[name]?
          return resolved
        end

        suffix = ".#{name}"
        matches = constants.compact_map do |key, value|
          key.ends_with?(suffix) ? value : nil
        end.uniq!
        matches.size == 1 ? matches.first : nil
      end

      private def first_class_literal_type(call : LibTreeSitter::TSNode, source : String) : String?
        args = argument_list_node(call)
        return unless args
        Noir::TreeSitter.each_named_arg(args) do |arg|
          next unless Noir::TreeSitter.node_type(arg) == "class_literal"
          Noir::TreeSitter.each_named_child(arg) do |child|
            if Noir::TreeSitter.node_type(child) == "type_identifier"
              return Noir::TreeSitter.node_text(child, source)
            end
          end
        end
        nil
      end

      # Pull the lambda's body (`block` or expression) out of the
      # call's argument list. Returns nil if no lambda is passed.
      private def lambda_body_in_args(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
        args = argument_list_node(call)
        return unless args
        Noir::TreeSitter.each_named_arg(args) do |arg|
          next unless Noir::TreeSitter.node_type(arg) == "lambda_expression"
          Noir::TreeSitter.each_named_arg(arg) do |child|
            ty = Noir::TreeSitter.node_type(child)
            # The lambda parameter list (identifier / formal_parameters /
            # inferred_parameters) precedes the body — skip it.
            next if ty == "identifier" || ty == "formal_parameters" || ty == "inferred_parameters"
            return child
          end
        end
        nil
      end

      private def method_body_index(root : LibTreeSitter::TSNode, source : String) : Hash(String, LibTreeSitter::TSNode)
        bodies = Hash(String, LibTreeSitter::TSNode).new

        walk_method_declarations(root) do |method|
          name_node = Noir::TreeSitter.field(method, "name")
          body = Noir::TreeSitter.field(method, "body")
          next unless name_node && body

          name = Noir::TreeSitter.node_text(name_node, source)
          bodies[name] ||= body
        end

        bodies
      end

      private def walk_method_declarations(node : LibTreeSitter::TSNode, depth : Int32 = 0, &block : LibTreeSitter::TSNode ->)
        # Real code never nests method declarations anywhere near
        # MAX_AST_DEPTH, so this is output-preserving; it only stops runaway
        # recursion on pathologically deep input (see extractor_recursion_depth_spec).
        return if depth > Noir::TreeSitter::MAX_AST_DEPTH

        if Noir::TreeSitter.node_type(node) == "method_declaration"
          block.call(node)
        end

        Noir::TreeSitter.each_named_child(node) do |child|
          walk_method_declarations(child, depth + 1, &block)
        end
      end
    end

    # Java `implements` / supertype names: Spring, JAX-RS and Micronaut.
    module JavaSupertypes
      # Simple names of the `implements` interfaces, read straight from the
      # tree-sitter `interfaces` field (a `super_interfaces` node wrapping a
      # `type_list`).
      #
      # Reading the field rather than slicing the class node's text at the
      # first `{` matters: the node text starts at the `modifiers` child, so
      # a class-level annotation whose arguments contain a brace —
      # `@Produces({MediaType.APPLICATION_JSON})`, `@RequestMapping({"/api"})`,
      # `@CrossOrigin(origins = {...})` — was mistaken for the class body and
      # cut the header off before `implements` was ever reached, silently
      # killing interface route inheritance.
      private def implemented_interface_names(class_decl : LibTreeSitter::TSNode, source : String) : Array(String)
        names = [] of String
        return names unless interfaces = Noir::TreeSitter.field(class_decl, "interfaces")

        Noir::TreeSitter.each_named_child(interfaces) do |child|
          if Noir::TreeSitter.node_type(child) == "type_list"
            Noir::TreeSitter.each_named_child(child) do |type_node|
              append_simple_type_name(type_node, source, names)
            end
          else
            append_simple_type_name(child, source, names)
          end
        end
        names
      end

      # Appends the simple name of a type node — generics dropped, package
      # qualifier dropped, any leading `@Annotation` on an `annotated_type`
      # discarded — skipping empties and duplicates.
      private def append_simple_type_name(type_node : LibTreeSitter::TSNode, source : String, names : Array(String))
        name = strip_generic_arguments(Noir::TreeSitter.node_text(type_node, source))
        name = name.split(/\s+/).last? || name
        return if name.empty?
        if idx = name.rindex('.')
          name = name[(idx + 1)..]
        end
        names << name unless name.empty? || names.includes?(name)
      end

      private def strip_generic_arguments(text : String) : String
        String.build do |io|
          depth = 0
          text.each_char do |char|
            case char
            when '<'
              depth += 1
            when '>'
              depth -= 1 if depth > 0
            else
              io << char if depth == 0
            end
          end
        end.strip
      end
    end

    # Java declaration and annotation node readers: JAX-RS and Micronaut.
    module JavaDecls
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

      private def method_name_of(method : LibTreeSitter::TSNode, source : String) : String?
        Noir::TreeSitter.each_named_child(method) do |child|
          return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "identifier"
        end
        nil
      end

      private def formal_parameters_node(method : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
        Noir::TreeSitter.each_named_child(method) do |child|
          return child if Noir::TreeSitter.node_type(child) == "formal_parameters"
        end
        nil
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
    end

    # The `modifiers` child and an annotation's simple name, Java and Kotlin.
    module Modifiers
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
    end

    # Kotlin class-declaration readers: the Kotlin route and parameter
    # extractors. Needs `Modifiers` alongside.
    module KotlinDecls
      private def abstract_type?(decl : LibTreeSitter::TSNode, source : String) : Bool
        if mods = find_modifiers(decl)
          Noir::TreeSitter.each_named_child(mods) do |child|
            return true if Noir::TreeSitter.node_text(child, source) == "abstract"
          end
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
    end

    # Kotlin `navigation_expression` tail: http4k, Ktor and the Kotlin
    # route extractor.
    module KotlinNavigation
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
    end
  end
end
