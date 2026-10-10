# Part of Noir::TreeSitterKotlinRouteExtractor: shared annotation/string/expression decoding helpers.
module Noir
  module TreeSitterKotlinRouteExtractor
    # Comments and string contents blanked, character offsets preserved.
    # See `Noir::KotlinSourceMask`.
    private def visible_kotlin_code(source : String) : String
      Noir::KotlinSourceMask.visible(source)
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
        if entry = annotation_name_and_args(ann, source)
          yield entry[0], entry[1], Noir::TreeSitter.node_start_row(ann)
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
    # `keys` names the keyword arguments that carry the path; Spring's
    # are `value`/`path`, Micronaut's `value`/`uri`/`uris`. Positional
    # arguments are the fallback unless `positional` is off (a key such as
    # `defaultValue` is never passed positionally).
    private def annotation_paths(args_node : LibTreeSitter::TSNode?,
                                 source : String,
                                 string_constants : Hash(String, String),
                                 local_string_constants : Hash(String, String),
                                 keys : Enumerable(String) = {"value", "path"},
                                 positional : Bool = true) : Array(String)
      empty = [] of String
      return empty unless args_node
      return empty unless Noir::TreeSitter.node_type(args_node) == "value_arguments"

      positional_values = [] of String
      keyword = [] of String

      Noir::TreeSitter.each_named_child(args_node) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        kind, key, value_node = classify_value_argument(arg, source)
        next unless value_node

        if kind == :keyword
          next unless keys.includes?(key)
          collect_string_values(value_node, source, keyword, string_constants, local_string_constants)
        elsif kind == :bare_identifier
          if value = local_string_constants[key]?
            positional_values << value unless value.empty?
          end
        else
          collect_string_values(value_node, source, positional_values, string_constants, local_string_constants)
        end
      end

      keyword.empty? && positional ? positional_values : keyword
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

    # Annotation values never legitimately nest more than a few levels
    # (`[arrayOf("/a")]`). The shared `MAX_AST_DEPTH` backstop is too
    # loose for the two value walkers below: their frames are ~10KB in a
    # debug build, so ~900 nested `((...))` / `[[...]]` already overran
    # the fiber stack and aborted the whole scan.
    MAX_ANNOTATION_VALUE_DEPTH = 64

    # Collect path values from a node. Handles string literals,
    # constants, `PATH + "/suffix"`, collection literals, and
    # `arrayOf("/a", PATH)` call expressions.
    private def collect_string_values(node : LibTreeSitter::TSNode,
                                      source : String,
                                      sink : Array(String),
                                      string_constants : Hash(String, String),
                                      local_string_constants : Hash(String, String),
                                      depth : Int32 = 0)
      return if depth > MAX_ANNOTATION_VALUE_DEPTH
      case Noir::TreeSitter.node_type(node)
      when "collection_literal"
        # Kotlin's `[...]` array syntax inside annotations.
        Noir::TreeSitter.each_named_child(node) do |elem|
          collect_string_values(elem, source, sink, string_constants, local_string_constants, depth + 1)
        end
      when "parenthesized_expression"
        # Stray-annotation case: `@RequestMapping("/x")` gets parsed
        # as `annotation` + sibling `parenthesized_expression`
        # carrying a bare `string_literal` (no `value_arguments`
        # wrapper).
        Noir::TreeSitter.each_named_child(node) do |elem|
          collect_string_values(elem, source, sink, string_constants, local_string_constants, depth + 1)
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
                  collect_string_values(v, source, sink, string_constants, local_string_constants, depth + 1)
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

    # `Paths.ITEM` or `com.example.Paths.ITEM` from the cross-file index.
    # A bare `ITEM` is not looked up here: simple names collide across
    # files far more often than type-qualified ones.
    private def fully_qualified_constant(text : String, string_constants : Hash(String, String)) : String?
      return unless text.includes?('.')
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

    # Call sites are located on the visible copy — a commented-out
    # `registry.addEndpoint("/ws-legacy-removed")`, or the same call
    # quoted inside a string, is not a call — but the argument text is
    # sliced out of the raw source, because that is where the literal
    # values the caller wants still exist. `KotlinSourceMask` preserves
    # character offsets, so the two indexes refer to the same place.
    private def each_method_call_arguments(source : String, method_name : String, &)
      visible = visible_kotlin_code(source)
      offset = 0
      name_size = method_name.size

      while marker = visible.index(method_name, offset)
        offset = marker + name_size
        next unless method_call_name?(visible, marker, name_size)

        open_idx = visible.index('(', marker)
        next unless open_idx
        close_idx = find_matching_paren(visible, open_idx)
        next unless close_idx

        args = source[(open_idx + 1)...close_idx]
        line = visible[0...marker].count('\n') + 1
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
      args = Noir::KotlinSourceMask.code_only(args)
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
    private def collect_request_method_values(node : LibTreeSitter::TSNode, source : String, sink : Array(String), depth : Int32 = 0)
      return if depth > MAX_ANNOTATION_VALUE_DEPTH
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
          collect_request_method_values(elem, source, sink, depth + 1)
        end
      when "call_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          next unless Noir::TreeSitter.node_type(child) == "call_suffix"
          Noir::TreeSitter.each_named_child(child) do |suf|
            next unless Noir::TreeSitter.node_type(suf) == "value_arguments"
            Noir::TreeSitter.each_named_child(suf) do |va|
              next unless Noir::TreeSitter.node_type(va) == "value_argument"
              Noir::TreeSitter.each_named_child(va) do |v|
                collect_request_method_values(v, source, sink, depth + 1)
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
            io << Noir::TreeSitter.kotlin_string_content(child, node, source)
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

    # ---- JVM resource-class helpers (JAX-RS, Micronaut) -------------

    alias ResourceAnnotation = Tuple(String, LibTreeSitter::TSNode?, Int32)

    # Kotlin scalars a resource method binds from a single request value,
    # lower-cased like the Java extractors' `PRIMITIVE_TYPES`.
    KOTLIN_SCALAR_TYPES = TreeSitterJaxRsExtractor::PRIMITIVE_TYPES | Set{"any", "unit"}

    # Yield every class/object/interface declaration under `node` with all
    # of its annotations as `{name, args, line}`. That includes the ones
    # tree-sitter-kotlin split off into a preceding `prefix_expression`
    # sibling (see `walk_classes`): it hits the first class after the
    # imports whenever the list opens with a bare annotation such as
    # Quarkus' `@ApplicationScoped @Path("/x")`.
    private def each_annotated_class(node : LibTreeSitter::TSNode,
                                     source : String,
                                     depth : Int32 = 0,
                                     &block : LibTreeSitter::TSNode, Array(ResourceAnnotation) ->)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      strays = [] of ResourceAnnotation
      Noir::TreeSitter.each_named_child(node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "class_declaration", "object_declaration", "interface_declaration"
          annotations = strays
          each_annotation(child, source) { |name, args, line| annotations << {name, args, line} }
          block.call(child, annotations)
          strays = [] of ResourceAnnotation
          each_annotated_class(child, source, depth + 1, &block)
        when "prefix_expression"
          if prefix_expression_has_annotation?(child)
            line = Noir::TreeSitter.node_start_row(child)
            collect_stray_annotations(child, source).each { |(name, args)| strays << {name, args, line} }
          else
            strays = [] of ResourceAnnotation
            each_annotated_class(child, source, depth + 1, &block)
          end
        when "line_comment", "multiline_comment"
          # A comment between stray annotations and their class keeps them paired.
        else
          strays = [] of ResourceAnnotation
          each_annotated_class(child, source, depth + 1, &block)
        end
      end
    end

    # String values of one annotation's arguments. `args` is the usual
    # `value_arguments`, or the bare `parenthesized_expression` a stray
    # annotation carries.
    private def annotation_values(args : LibTreeSitter::TSNode?,
                                  source : String,
                                  string_constants : Hash(String, String),
                                  local_string_constants : Hash(String, String),
                                  keys : Enumerable(String) = {"value"},
                                  positional : Bool = true) : Array(String)
      return [] of String unless args
      if Noir::TreeSitter.node_type(args) == "parenthesized_expression"
        values = [] of String
        collect_string_values(args, source, values, string_constants, local_string_constants) if positional
        return values
      end
      annotation_paths(args, source, string_constants, local_string_constants, keys, positional)
    end

    # Yield `{name, type_node, annotations}` for each parameter of a
    # `function_declaration`. Kotlin keeps a parameter's annotations in a
    # `parameter_modifiers` sibling just before the `parameter` node.
    private def each_function_parameter(func : LibTreeSitter::TSNode, source : String, &)
      Noir::TreeSitter.each_named_child(func) do |child|
        next unless Noir::TreeSitter.node_type(child) == "function_value_parameters"

        annotations = [] of ResourceAnnotation
        Noir::TreeSitter.each_named_child(child) do |entry|
          case Noir::TreeSitter.node_type(entry)
          when "parameter_modifiers"
            Noir::TreeSitter.each_named_child(entry) do |ann|
              next unless Noir::TreeSitter.node_type(ann) == "annotation"
              annotation_name_and_args(ann, source).try { |(name, args)| annotations << {name, args, Noir::TreeSitter.node_start_row(ann)} }
            end
          when "parameter"
            name = ""
            type_node : LibTreeSitter::TSNode? = nil
            Noir::TreeSitter.each_named_child(entry) do |part|
              case Noir::TreeSitter.node_type(part)
              when "simple_identifier" then name = Noir::TreeSitter.node_text(part, source) if name.empty?
              when "user_type", "nullable_type"
                type_node ||= part
              end
            end
            yield name, type_node, annotations unless name.empty?
            annotations = [] of ResourceAnnotation
          end
        end
      end
    end

    private def annotation_name_and_args(ann : LibTreeSitter::TSNode, source : String) : Tuple(String, LibTreeSitter::TSNode?)?
      Noir::TreeSitter.each_named_child(ann) do |child|
        case Noir::TreeSitter.node_type(child)
        when "user_type"
          return {simple_annotation_name(Noir::TreeSitter.node_text(child, source)), nil}
        when "constructor_invocation"
          name = ""
          args : LibTreeSitter::TSNode? = nil
          Noir::TreeSitter.each_named_child(child) do |sub|
            case Noir::TreeSitter.node_type(sub)
            when "user_type"       then name = simple_annotation_name(Noir::TreeSitter.node_text(sub, source))
            when "value_arguments" then args = sub
            end
          end
          return {name, args} unless name.empty?
        end
      end
      nil
    end

    # Simple name of a parameter / return type: `Book` for `Book?`,
    # `List` for `List<Book>`, `Optional` for `java.util.Optional<Book>`.
    # A wrapper named in `unwrap` (`Mono<Book>`) resolves to its first
    # type argument instead.
    private def resource_type_name(node : LibTreeSitter::TSNode?,
                                   source : String,
                                   unwrap : Set(String) = Set(String).new,
                                   depth : Int32 = 0) : String
      return "" unless node && depth < 8

      case Noir::TreeSitter.node_type(node)
      when "nullable_type", "type_projection"
        resource_type_name(Noir::TreeSitter.first_named_child(node), source, unwrap, depth + 1)
      when "user_type"
        outer = ""
        type_args : LibTreeSitter::TSNode? = nil
        Noir::TreeSitter.each_named_child(node) do |child|
          case Noir::TreeSitter.node_type(child)
          when "type_identifier" then outer = Noir::TreeSitter.node_text(child, source)
          when "type_arguments"  then type_args = child
          end
        end
        if (args = type_args) && unwrap.includes?(outer.downcase)
          inner = resource_type_name(Noir::TreeSitter.first_named_child(args), source, unwrap, depth + 1)
          return inner unless inner.empty?
        end
        outer
      else
        ""
      end
    end

    # The declared return type of a `function_declaration` (the type node
    # after its parameter list), or "" for an inferred one.
    private def function_return_type_name(func : LibTreeSitter::TSNode, source : String) : String
      seen_params = false
      Noir::TreeSitter.each_named_child(func) do |child|
        case Noir::TreeSitter.node_type(child)
        when "function_value_parameters" then seen_params = true
        when "user_type", "nullable_type"
          return resource_type_name(child, source) if seen_params
        end
      end
      ""
    end

    # 1-hop callees of a resource method body as `{name, line}`.
    private def function_callees(func : LibTreeSitter::TSNode, source : String) : Array(Tuple(String, Int32))
      Noir::TreeSitter.each_named_child(func) do |child|
        next unless Noir::TreeSitter.node_type(child) == "function_body"
        return Noir::KotlinCalleeExtractor.callees_in_lambda(child, source, "", skip_routing: false).map do |(name, _path, line)|
          {name, line}
        end
      end
      [] of Tuple(String, Int32)
    end

    # `{start_byte, end_byte, callees}` for every function in `source`, so
    # an adapter that finds a route by annotation offset (Quarkus
    # `@Route`) can pick the enclosing function's callees.
    def extract_function_callee_spans(source : String, file_path : String) : Array(Tuple(Int32, Int32, Array(Tuple(String, String, Int32))))
      spans = [] of Tuple(Int32, Int32, Array(Tuple(String, String, Int32)))
      Noir::TreeSitter.parse_kotlin(source) do |root|
        Noir::TreeSitter.walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "function_declaration"
          Noir::TreeSitter.each_named_child(node) do |body|
            next unless Noir::TreeSitter.node_type(body) == "function_body"
            spans << {LibTreeSitter.ts_node_start_byte(node).to_i, LibTreeSitter.ts_node_end_byte(node).to_i,
                      Noir::KotlinCalleeExtractor.callees_in_lambda(body, source, file_path, skip_routing: false)}
          end
        end
      end
      spans
    end

    # DTO fields a body parameter of type `type_name` fans out into, or nil
    # when the type isn't a known Kotlin class. Server-managed fields
    # (`@Id`, audit columns, ...) are never client input.
    private def dto_body_params(type_name : String,
                                dto_index : Hash(String, Array(TreeSitterKotlinParameterExtractor::FieldInfo)),
                                format : String) : Array(Param)?
      fields = dto_index[type_name]?
      return unless fields
      fields.reject(&.server_managed?).map { |field| Param.new(field.name, field.literal_default, format) }
    end
  end
end
